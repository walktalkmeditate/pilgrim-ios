import Foundation
import CoreLocation

extension DossierSenses {

    static func placeResonance(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func moonLine(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func markerColoring(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func intentionLineage(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func weatherWeave(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func photoAdjacency(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func questionDensity(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }
}

// MARK: - Track 3: climb anchoring (current walk)

extension DossierSenses {

    struct AscentRun: Equatable {
        let start: Date
        let end: Date
        let gain: Double
        let averageRate: Double
    }

    static func climbAnchoring(input: Input, suppressed: Set<String>) -> SenseLine? {
        guard input.totalAscent >= climbMinTotalAscent,
              let run = steepestSustainedAscent(in: input.elevationSeries) else { return nil }
        for thread in activeThreads(in: input) where !suppressed.contains(thread.lemma) {
            let onClimb = input.currentRecordings.contains { recording in
                recording.themes.contains { $0.lemma == thread.lemma }
                    && recording.start <= run.end && recording.end >= run.start
            }
            if onClimb {
                return SenseLine(
                    text: "'\(thread.displayTerm)' was spoken on the day's steepest climb.",
                    lemma: thread.lemma
                )
            }
        }
        return nil
    }

    /// Centered moving average — raw GPS elevation is noisy per sample and
    /// unsmoothed gradients false-positive on jitter (spec Track 3).
    static func smoothedAltitudes(_ series: [ElevationSample]) -> [ElevationSample] {
        let half = climbSmoothingWindow / 2
        return series.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(series.count - 1, i + half)
            let mean = series[lo...hi].map(\.altitude).reduce(0, +) / Double(hi - lo + 1)
            return ElevationSample(timestamp: series[i].timestamp, altitude: mean)
        }
    }

    /// The maximal-average-rate contiguous run of top-decile positive climb
    /// rates gaining ≥20 m. Rate is over time (m/s) — the series carries no
    /// distance, and "steepest" stays deterministic without one.
    static func steepestSustainedAscent(in series: [ElevationSample]) -> AscentRun? {
        let smoothed = smoothedAltitudes(series)
        guard smoothed.count > 1 else { return nil }
        var segments: [(start: Int, end: Int, rate: Double)] = []
        for i in 1..<smoothed.count {
            let dt = smoothed[i].timestamp.timeIntervalSince(smoothed[i - 1].timestamp)
            guard dt > 0 else { continue }
            segments.append((i - 1, i, (smoothed[i].altitude - smoothed[i - 1].altitude) / dt))
        }
        let positive = segments.map(\.rate).filter { $0 > 0 }.sorted()
        guard !positive.isEmpty else { return nil }
        let threshold = positive[Int(Double(positive.count - 1) * climbTopDecile)]
        var best: AscentRun?
        var runStartIndex: Int?
        func closeRun(endingAt segmentIndex: Int) {
            guard let startSegment = runStartIndex else { return }
            runStartIndex = nil
            let startSample = segments[startSegment].start
            let endSample = segments[segmentIndex].end
            let gain = smoothed[endSample].altitude - smoothed[startSample].altitude
            let duration = smoothed[endSample].timestamp.timeIntervalSince(smoothed[startSample].timestamp)
            guard gain >= climbMinRunGain, duration > 0 else { return }
            let run = AscentRun(
                start: smoothed[startSample].timestamp,
                end: smoothed[endSample].timestamp,
                gain: gain,
                averageRate: gain / duration
            )
            if best == nil || run.averageRate > best!.averageRate {
                best = run
            }
        }
        for (index, segment) in segments.enumerated() {
            if segment.rate >= threshold && segment.rate > 0 {
                if runStartIndex == nil { runStartIndex = index }
                if index == segments.count - 1 { closeRun(endingAt: index) }
            } else if runStartIndex != nil {
                closeRun(endingAt: index - 1)
            }
        }
        return best
    }
}

// MARK: - Track 4: speech shape (current walk)

extension DossierSenses {

    static func speechShape(input: Input, suppressed: Set<String>) -> SenseLine? {
        let worded = input.currentRecordings.filter { $0.wordCount > 0 }
        guard !worded.isEmpty else { return nil }
        let span = input.walkEnd.timeIntervalSince(input.walkStart)
        guard span > 0 else { return nil }
        let firstThirdEnd = input.walkStart.addingTimeInterval(span / 3)
        guard worded.allSatisfy({ $0.end <= firstThirdEnd }),
              let lastEnd = worded.map(\.end).max() else { return nil }
        let remainder = input.walkEnd.timeIntervalSince(lastEnd)
        guard remainder > speechShapeMinWordlessRemainder else { return nil }
        let minutes = Int(remainder / 60)
        return SenseLine(
            text: "All the words came in the first third; the last \(minutes) minutes were wordless.",
            lemma: nil
        )
    }
}
