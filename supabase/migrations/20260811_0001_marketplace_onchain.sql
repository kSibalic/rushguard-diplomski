-- ============================================================================
-- On-chain marketplace support
--
-- Resale runs through a Metaplex Auction House instance. This migration stores
-- the one piece of on-chain state the client cannot re-derive on its own.
--
-- Safe to run more than once.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. list_state
--
-- Address of the on-chain SellerTradeState account created when a seller lists.
-- Cancelling a listing requires it, and it is not derivable from the ticket
-- alone, so it has to be stored next to the listing.
--
-- Nullable: a listing without a list_state has no on-chain counterpart, and the
-- app refuses to sell it.
-- ----------------------------------------------------------------------------
ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS list_state text;

COMMENT ON COLUMN public.marketplace_listings.list_state IS
  'On-chain SellerTradeState PDA for this Auction House listing. NULL when the listing has no on-chain counterpart.';

-- ----------------------------------------------------------------------------
-- 2. One live listing per ticket
--
-- Prevents duplicate listings for the same ticket. The Auction House would
-- reject a purchase against an already-consumed delegation, but the buyer would
-- first be asked to authorise a transaction that could not succeed.
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS marketplace_listings_unique_nft
  ON public.marketplace_listings (nft_id);

-- ----------------------------------------------------------------------------
-- 3. buy_marketplace_ticket — record the settling transaction
--
-- Adds the confirmed on-chain signature as a parameter and writes it to the log,
-- so any divergence between database and chain can be traced. Postgres cannot
-- read the ledger, so this is a database update that follows a settled on-chain
-- sale, not the sale itself. If it fails, the buyer still owns the ticket
-- on-chain, which is authoritative; only the database is out of date.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.buy_marketplace_ticket(
  p_listing_id uuid,
  p_tx_signature text DEFAULT NULL
)
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

  RAISE LOG 'marketplace sale settled: nft=% buyer=% tx=%',
    v_listing.nft_id, v_buyer, COALESCE(p_tx_signature, '<none>');

  RETURN v_listing.nft_id;
END $$;

REVOKE ALL ON FUNCTION public.buy_marketplace_ticket(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.buy_marketplace_ticket(uuid, text) TO authenticated;

-- The single-argument version would be ambiguous with the two-argument default,
-- so it is dropped for PostgREST to resolve the call unambiguously.
DROP FUNCTION IF EXISTS public.buy_marketplace_ticket(uuid);
