//
//  PhaseTimer.swift
//  diplomski
//
//  Created by Karlo Šibalić on 22.08.2026..
//

import Foundation

/// Measures how long each stage of a multi-step operation takes.
///
/// The breakdown matters more than the total: it shows which stages — biometric
/// authentication, IPFS pinning, transaction building, broadcast, confirmation —
/// account for the time a user waits.
///
/// Durations are wall-clock and include biometric prompts, so they measure what the
/// user experiences rather than CPU time.
///
/// `mark` attributes everything since the previous mark to the named phase, so a mark
/// must only be placed where that phase actually happened.
///
/// ```swift
/// let timer = PhaseTimer("kupnja")
/// timer.mark("faceid")
/// timer.mark("ipfs")
/// timer.dump()
/// // MJERENJE;kupnja;faceid=1.842;ipfs=2.117;UKUPNO=3.959
/// ```
final class PhaseTimer {
    private let label: String
    private let start = Date()
    private var last = Date()

    /// Ordered phase names, so a repeated phase keeps its original position.
    private var order: [String] = []
    /// Accumulated duration per phase. Repeats are summed, so a three-seat purchase
    /// records one `ipfs` total rather than three entries.
    private var totals: [String: Double] = [:]

    init(_ label: String) {
        self.label = label
    }

    /// Records the time elapsed since the previous mark (or since creation) against
    /// `phase`, and resets the clock.
    func mark(_ phase: String) {
        let now = Date()
        let elapsed = now.timeIntervalSince(last)
        last = now

        if totals[phase] == nil {
            order.append(phase)
            totals[phase] = elapsed
        } else {
            totals[phase]! += elapsed
        }
    }

    /// Phases in the order they first occurred, with their accumulated durations.
    var rows: [(phase: String, duration: Double)] {
        order.map { ($0, totals[$0] ?? 0) }
    }

    var total: TimeInterval { Date().timeIntervalSince(start) }

    /// Prints one semicolon-separated line and files the run with `PhaseStats`.
    ///
    /// The format pastes straight into a spreadsheet: split on `;`, then on `=`.
    @discardableResult
    func dump(record: Bool = true) -> String {
        let elapsed = total
        var line = "MJERENJE;\(label)"
        for (phase, duration) in rows {
            line += ";\(phase)=\(String(format: "%.3f", duration))"
        }
        line += ";UKUPNO=\(String(format: "%.3f", elapsed))"

        print(line)

        if record {
            PhaseStats.shared.record(label: label, rows: rows, total: elapsed)
        }
        return line
    }
}

/// Aggregates repeated runs of the same operation.
///
/// `summary()` reports mean, sample standard deviation, minimum and maximum per phase.
/// The spread is informative in itself: network-bound phases vary far more than local
/// ones.
final class PhaseStats {
    static let shared = PhaseStats()

    private let lock = NSLock()
    private var runs: [String: [(rows: [(phase: String, duration: Double)], total: Double)]] = [:]

    private init() {}

    func record(label: String, rows: [(phase: String, duration: Double)], total: Double) {
        lock.lock()
        defer { lock.unlock() }
        runs[label, default: []].append((rows, total))
    }

    func reset() {
        lock.lock()
        runs.removeAll()
        lock.unlock()
    }

    /// Prints a per-phase table for every operation recorded so far.
    @discardableResult
    func summary() -> String {
        lock.lock()
        let snapshot = runs
        lock.unlock()

        var out = ""
        for (label, samples) in snapshot.sorted(by: { $0.key < $1.key }) {
            out += "\n=== \(label) — \(samples.count) run(s) ===\n"
            out += Self.pad("faza", 14)
                + Self.pad("sr.vr.", 9)
                + Self.pad("sd", 9)
                + Self.pad("min", 9)
                + Self.pad("max", 9) + "\n"

            // Preserve the phase order from the first run.
            var phaseOrder: [String] = []
            for sample in samples {
                for row in sample.rows where !phaseOrder.contains(row.phase) {
                    phaseOrder.append(row.phase)
                }
            }

            for phase in phaseOrder {
                let values = samples.compactMap { sample in
                    sample.rows.first(where: { $0.phase == phase })?.duration
                }
                out += Self.formatRow(phase, values)
            }
            out += Self.formatRow("UKUPNO", samples.map(\.total))
        }

        print(out)
        return out
    }

    private static func formatRow(_ name: String, _ values: [Double]) -> String {
        guard !values.isEmpty else { return "" }
        let mean = values.reduce(0, +) / Double(values.count)
        // Sample standard deviation (n−1). Undefined for a single run, reported as 0.
        let variance = values.count > 1
            ? values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
            : 0

        return pad(name, 14)
            + pad(String(format: "%.3f", mean), 9)
            + pad(String(format: "%.3f", sqrt(variance)), 9)
            + pad(String(format: "%.3f", values.min() ?? 0), 9)
            + pad(String(format: "%.3f", values.max() ?? 0), 9) + "\n"
    }

    /// Left-aligned column padding.
    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}
