-- =============================================================================
-- RushGuard — Row Level Security
--
-- Run this whole file in the Supabase SQL editor (Database → SQL Editor → New
-- query). It is idempotent: safe to run more than once.
--
-- WHAT THIS DOES
--   1. Adds an `is_admin()` helper that can be used inside policies without
--      causing infinite recursion on `profiles`.
--   2. Drops every existing policy on the five app tables. Permissive policies
--      are combined with OR, so a single unrestricted policy would cancel out
--      every restrictive policy beside it.
--   3. Enables RLS on all five tables and installs a minimal, restrictive set.
--   4. Blocks client-side writes to `profiles.role` (privilege escalation).
--   5. Provides `SECURITY DEFINER` functions for the operations owner-scoped RLS
--      would otherwise block (seat availability, redemption, resale bookkeeping),
--      each performing its own authorization check.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Admin helper
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER so that reading `profiles` from inside a `profiles` policy
-- does not re-enter RLS and recurse. STABLE so Postgres can cache it per
-- statement. `search_path` is pinned: a SECURITY DEFINER function with a
-- caller-controlled search_path is itself a privilege-escalation vector.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM public;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;


-- -----------------------------------------------------------------------------
-- 2. Drop every existing policy on the app tables
-- -----------------------------------------------------------------------------
-- Done by enumeration rather than by name, so no pre-existing policy survives
-- regardless of what it was called.
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname, tablename
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('tickets', 'profiles', 'active_movies',
                        'showtimes', 'marketplace_listings')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                   pol.policyname, pol.tablename);
  END LOOP;
END $$;


-- -----------------------------------------------------------------------------
-- 3. Enable RLS
-- -----------------------------------------------------------------------------
ALTER TABLE public.tickets              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.active_movies        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.showtimes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_listings ENABLE ROW LEVEL SECURITY;


-- -----------------------------------------------------------------------------
-- 4. profiles
-- -----------------------------------------------------------------------------
-- A user may read and update only their own row. Admins may read any row —
-- the ticket-verification screen shows the holder's wallet address.
-- Nobody may read another customer's `solana_public_key` through the API.

CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "profiles_select_admin"
  ON public.profiles FOR SELECT TO authenticated
  USING (public.is_admin());

-- Sign-up inserts this row from the client (AuthViewModel.signUp). The role is
-- pinned here as well as in the trigger below: without the `role` clause a
-- crafted sign-up request could simply insert itself as 'admin', which the
-- UPDATE trigger would never see.
CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = id
    AND (role IS NULL OR role = 'user')
  );

CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- No DELETE policy: profiles are not deletable through the API.


-- `role` must not be writable by the client. Without this, `profiles_update_own`
-- above is enough for any user to run
--     UPDATE profiles SET role = 'admin' WHERE id = auth.uid()
-- and promote themselves to cinema staff.
--
-- The check is scoped to requests arriving through PostgREST (where the session
-- role is `authenticated` or `anon`), so role assignment from the SQL editor or
-- with the service_role key still works.
-- Deliberately SECURITY INVOKER (the default): a SECURITY DEFINER trigger runs
-- as its owner, so `current_user` would always read 'postgres' and the check
-- below would never fire. As an invoker function it sees the real caller —
-- 'authenticated' via PostgREST, 'postgres' from the SQL editor, and 'postgres'
-- again when reached from inside one of the SECURITY DEFINER RPCs, which is
-- exactly the behaviour we want in all three cases.
CREATE OR REPLACE FUNCTION public.prevent_role_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role
     AND current_user IN ('authenticated', 'anon')
  THEN
    RAISE EXCEPTION 'profiles.role is not client-modifiable';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS profiles_no_role_change ON public.profiles;
CREATE TRIGGER profiles_no_role_change
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.prevent_role_change();


-- -----------------------------------------------------------------------------
-- 5. active_movies / showtimes — public catalog, admin-only writes
-- -----------------------------------------------------------------------------
CREATE POLICY "active_movies_select_all"
  ON public.active_movies FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY "active_movies_write_admin"
  ON public.active_movies FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "showtimes_select_all"
  ON public.showtimes FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY "showtimes_write_admin"
  ON public.showtimes FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());


-- -----------------------------------------------------------------------------
-- 6. tickets
-- -----------------------------------------------------------------------------
-- Owner-scoped. A user sees only their own tickets; admins see all (needed by
-- the scan-verification screen). Note there is deliberately NO client UPDATE
-- path for `user_id` or `is_used` — resale and redemption go through the
-- SECURITY DEFINER functions in section 8, so that the two-step operations
-- stay atomic and authorized server-side.

CREATE POLICY "tickets_select_own"
  ON public.tickets FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "tickets_select_admin"
  ON public.tickets FOR SELECT TO authenticated
  USING (public.is_admin());

CREATE POLICY "tickets_insert_own"
  ON public.tickets FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "tickets_update_own"
  ON public.tickets FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- No DELETE policy: a ticket is never destroyed from the client.


-- Even with `tickets_update_own`, a user must not be able to un-redeem their
-- own ticket (`is_used` true -> false) or move it to somebody else's account.
-- SECURITY INVOKER, for the same reason as prevent_role_change() above.
CREATE OR REPLACE FUNCTION public.protect_ticket_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
      RAISE EXCEPTION 'tickets.user_id is not client-modifiable';
    END IF;
    IF OLD.is_used AND NOT NEW.is_used THEN
      RAISE EXCEPTION 'a redeemed ticket cannot be un-redeemed';
    END IF;
    IF NEW.is_used AND NOT OLD.is_used THEN
      RAISE EXCEPTION 'redemption must go through redeem_ticket()';
    END IF;
    IF NEW.nft_id IS DISTINCT FROM OLD.nft_id
       OR NEW.seat IS DISTINCT FROM OLD.seat
       OR NEW.showtime IS DISTINCT FROM OLD.showtime
       OR NEW.movie_title IS DISTINCT FROM OLD.movie_title
    THEN
      RAISE EXCEPTION 'ticket identity columns are immutable';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tickets_protect_columns ON public.tickets;
CREATE TRIGGER tickets_protect_columns
  BEFORE UPDATE ON public.tickets
  FOR EACH ROW EXECUTE FUNCTION public.protect_ticket_columns();


-- -----------------------------------------------------------------------------
-- 7. marketplace_listings
-- -----------------------------------------------------------------------------
-- Listings are a public board: any signed-in user may read them. Only the
-- seller may create one, and only for a ticket they actually own.
CREATE POLICY "listings_select_authenticated"
  ON public.marketplace_listings FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "listings_insert_own"
  ON public.marketplace_listings FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = seller_id
    AND EXISTS (
      SELECT 1 FROM public.tickets t
      WHERE t.nft_id = marketplace_listings.nft_id
        AND t.user_id = auth.uid()
        AND NOT t.is_used
    )
  );

CREATE POLICY "listings_delete_own_or_admin"
  ON public.marketplace_listings FOR DELETE TO authenticated
  USING (auth.uid() = seller_id OR public.is_admin());

-- No UPDATE policy: a listing is deleted and re-created rather than edited.


-- -----------------------------------------------------------------------------
-- 8. SECURITY DEFINER RPCs
-- -----------------------------------------------------------------------------
-- Each one bypasses RLS by design, so each one performs its own authorization
-- check as its first statement. A SECURITY DEFINER function without an internal
-- check is a privilege-escalation vector in its own right.

-- 8a. admin_delete_listing
-- Must be SECURITY DEFINER: as SECURITY INVOKER (the Postgres default) it would
-- run under the caller's RLS and could not delete another user's listing. Also
-- frees the underlying ticket so the seller can use it again.
CREATE OR REPLACE FUNCTION public.admin_delete_listing(listing_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_nft_id text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  DELETE FROM public.marketplace_listings
  WHERE id = listing_id
  RETURNING nft_id INTO v_nft_id;

  IF v_nft_id IS NOT NULL THEN
    UPDATE public.tickets
    SET is_listed_on_marketplace = false
    WHERE nft_id = v_nft_id;
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.admin_delete_listing(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_delete_listing(uuid) TO authenticated;


-- 8b. taken_seats
-- The seat grid has to know which seats OTHER users hold. Under owner-scoped
-- RLS a direct SELECT on `tickets` returns only the caller's own seats, which
-- would let every seat be sold repeatedly. This returns seat numbers only —
-- no user ids, no mint addresses, no PII.
-- Known limitation: seats are matched by title and timestamp because `tickets`
-- has no foreign key to `showtimes`. A `showtime_id` column with a unique index
-- on (showtime_id, seat) would be more robust and would also prevent concurrent
-- double booking.
CREATE OR REPLACE FUNCTION public.taken_seats(p_movie_title text, p_showtime timestamptz)
RETURNS TABLE (seat integer)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT t.seat
  FROM public.tickets t
  WHERE t.movie_title = p_movie_title
    AND t.showtime = p_showtime;
$$;

REVOKE ALL ON FUNCTION public.taken_seats(text, timestamptz) FROM public;
GRANT EXECUTE ON FUNCTION public.taken_seats(text, timestamptz) TO authenticated;


-- 8c. redeem_ticket
-- Admin-only. A client-side `UPDATE tickets SET is_used = true` would be
-- rejected by owner-scoped RLS (the admin is not the ticket owner) and by the
-- `tickets_protect_columns` trigger.
-- Returns false if the ticket was already used, so the caller can tell a
-- successful redemption apart from a replayed one.
CREATE OR REPLACE FUNCTION public.redeem_ticket(p_nft_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_updated integer;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  UPDATE public.tickets
  SET is_used = true
  WHERE nft_id = p_nft_id
    AND NOT is_used;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END $$;

REVOKE ALL ON FUNCTION public.redeem_ticket(text) FROM public;
GRANT EXECUTE ON FUNCTION public.redeem_ticket(text) TO authenticated;


-- 8d. buy_marketplace_ticket
-- Under RLS the buyer cannot modify the seller's ticket or listing rows, so the
-- database side of a resale runs here. The listing row is locked FOR UPDATE, so
-- a second concurrent caller blocks and then finds it gone.
--
-- Postgres cannot read the Solana ledger, so this function does not verify that
-- the on-chain sale happened; the client calls it only after the sale has been
-- confirmed on-chain. (Redefined in 20260811_0001_marketplace_onchain.sql.)
CREATE OR REPLACE FUNCTION public.buy_marketplace_ticket(p_listing_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_listing public.marketplace_listings%ROWTYPE;
  v_buyer uuid := auth.uid();
BEGIN
  IF v_buyer IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT * INTO v_listing
  FROM public.marketplace_listings
  WHERE id = p_listing_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'listing no longer available';
  END IF;

  IF v_listing.seller_id = v_buyer THEN
    RAISE EXCEPTION 'cannot buy your own listing';
  END IF;

  IF v_listing.showtime < now() THEN
    RAISE EXCEPTION 'showtime has already passed';
  END IF;

  -- The seller must still own the ticket, and it must be unredeemed.
  IF NOT EXISTS (
    SELECT 1 FROM public.tickets
    WHERE nft_id = v_listing.nft_id
      AND user_id = v_listing.seller_id
      AND NOT is_used
  ) THEN
    RAISE EXCEPTION 'seller no longer owns this ticket';
  END IF;

  UPDATE public.tickets
  SET user_id = v_buyer,
      is_listed_on_marketplace = false
  WHERE nft_id = v_listing.nft_id;

  DELETE FROM public.marketplace_listings WHERE id = p_listing_id;

  RETURN v_listing.nft_id;
END $$;

REVOKE ALL ON FUNCTION public.buy_marketplace_ticket(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.buy_marketplace_ticket(uuid) TO authenticated;


-- 8e. purchase_preflight
-- Cheap read the client makes before asking the user to sign, so an already
-- sold or expired listing is rejected before any transaction is built.
CREATE OR REPLACE FUNCTION public.listing_is_purchasable(p_listing_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.marketplace_listings l
    JOIN public.tickets t ON t.nft_id = l.nft_id
    WHERE l.id = p_listing_id
      AND l.seller_id <> auth.uid()
      AND l.showtime >= now()
      AND t.user_id = l.seller_id
      AND NOT t.is_used
  );
$$;

REVOKE ALL ON FUNCTION public.listing_is_purchasable(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.listing_is_purchasable(uuid) TO authenticated;


-- -----------------------------------------------------------------------------
-- 9. Sanity check
-- -----------------------------------------------------------------------------
-- After running the migration, this should list exactly the policies created
-- above and nothing named allow_all_*.
--
--   SELECT tablename, policyname, cmd, roles
--   FROM pg_policies WHERE schemaname = 'public'
--   ORDER BY tablename, policyname;
--
-- And this should report rowsecurity = true for all five tables:
--
--   SELECT relname, relrowsecurity
--   FROM pg_class
--   WHERE relname IN ('tickets','profiles','active_movies',
--                     'showtimes','marketplace_listings');
