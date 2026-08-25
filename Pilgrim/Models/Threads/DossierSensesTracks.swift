import Foundation
import CoreLocation

// MARK: - Track 1: place-theme resonance (cross-walk)

extension DossierSenses {

    struct PlaceCluster {
        let mentionCount: Int
        let walkCount: Int
        let spread: CLLocationDistance
    }

    static func placeResonance(input: Input, suppressed: Set<String>) -> SenseLine? {
        guard input.backfillComplete else { return nil }
        let windowStart = input.walkStart.addingTimeInterval(-ThreadStore.recurrenceWindow)
        func inWindow(_ uuid: UUID) -> Bool {
            guard let instant = input.recordingTimestamps[uuid] else { return false }
            return instant >= windowStart && instant <= input.walkEnd
        }
        func qualifiedCoordinate(_ uuid: UUID) -> Coordinate? {
            guard let fix = input.fixes[uuid], qualifies(fix) else { return nil }
            return fix.coordinate
        }
        // Baseline spread: median pairwise distance across ALL in-window
        // mention recordings, any theme — the specificity guard's denominator.
        var mentionCoordinates: [UUID: Coordinate] = [:]
        for thread in input.threads {
            for appearance in thread.appearances where inWindow(appearance.recordingUUID) {
                if let coordinate = qualifiedCoordinate(appearance.recordingUUID) {
                    mentionCoordinates[appearance.recordingUUID] = coordinate
                }
            }
        }
        let ordered = mentionCoordinates.sorted { $0.key.uuidString < $1.key.uuidString }.map(\.value)
        guard ordered.count >= 2 else { return nil }
        var pairwise: [Double] = []
        for i in 0..<(ordered.count - 1) {
            for j in (i + 1)..<ordered.count {
                pairwise.append(distance(ordered[i], ordered[j]))
            }
        }
        let baseline = median(pairwise)

        for thread in activeThreads(in: input).prefix(placeCandidateThemeCap)
        where !suppressed.contains(thread.lemma) {
            let distinctWalks = Set(
                thread.appearances
                    .filter { $0.date >= windowStart && $0.date <= input.walkEnd }
                    .map(\.walkUUID)
            )
            guard distinctWalks.count >= 2 else { continue }
            let members = thread.appearances
                .filter { inWindow($0.recordingUUID) }
                .compactMap { appearance in
                    qualifiedCoordinate(appearance.recordingUUID).map { (appearance: appearance, coordinate: $0) }
                }
                .sorted { $0.appearance.recordingUUID.uuidString < $1.appearance.recordingUUID.uuidString }
            guard let cluster = bestCluster(members: members),
                  // Strict: a walker whose every recording shares one spot has
                  // baseline 0 — nothing can be "more specific" than routine.
                  cluster.spread < baseline / 2 else { continue }
            let times = cluster.mentionCount == 2 ? "twice" : "\(cluster.mentionCount) times"
            return SenseLine(
                text: "'\(thread.displayTerm)' has surfaced on \(distinctWalks.count) walks — \(times) near the same stretch of ground.",
                lemma: thread.lemma
            )
        }
        return nil
    }

    /// Deterministic seed-centered clustering: for each member in UUID order,
    /// the candidate cluster is everything within the radius of that seed;
    /// best by mention count, then smallest spread, then seed order.
    static func bestCluster(
        members: [(appearance: ThreadAppearance, coordinate: Coordinate)]
    ) -> PlaceCluster? {
        var best: PlaceCluster?
        for seed in members {
            let near = members.filter { distance(seed.coordinate, $0.coordinate) <= placeClusterRadius }
            let mentionCount = near.reduce(0) { $0 + $1.appearance.mentionCount }
            let walkCount = Set(near.map(\.appearance.walkUUID)).count
            guard mentionCount >= 2, walkCount >= 2 else { continue }
            var spread: CLLocationDistance = 0
            for i in 0..<near.count {
                for j in (i + 1)..<near.count {
                    spread = max(spread, distance(near[i].coordinate, near[j].coordinate))
                }
            }
            if best == nil
                || mentionCount > best!.mentionCount
                || (mentionCount == best!.mentionCount && spread < best!.spread) {
                best = PlaceCluster(mentionCount: mentionCount, walkCount: walkCount, spread: spread)
            }
        }
        return best
    }
}

extension DossierSenses {

    static func moonLine(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }
}

// MARK: - Track 4: intention lineage (cross-walk)

extension DossierSenses {

    static func intentionLemmas(in intention: String) -> Set<String> {
        Set(TranscriptNLP.contentLemmas(in: intention)).subtracting(SpokenStoplist.scaffoldLemmas)
    }

    static func intentionLineage(input: Input, suppressed: Set<String>) -> SenseLine? {
        let windowStart = input.walkStart.addingTimeInterval(-ThreadStore.recurrenceWindow)
        let inWindow = input.walkSnapshots.filter { $0.startDate >= windowStart && $0.startDate <= input.walkEnd }
        guard let today = inWindow.first(where: { $0.walkUUID == input.currentWalkUUID }),
              let todayIntention = today.intention, !todayIntention.isEmpty else { return nil }
        let todayLemmas = intentionLemmas(in: todayIntention)
        guard !todayLemmas.isEmpty else { return nil }
        var familyWalks: [String: Set<UUID>] = [:]
        for row in inWindow {
            guard let intention = row.intention, !intention.isEmpty else { continue }
            for lemma in intentionLemmas(in: intention) {
                familyWalks[lemma, default: []].insert(row.walkUUID)
            }
        }
        let candidate = familyWalks
            .filter { todayLemmas.contains($0.key) && $0.value.count >= lineageMinWalks && !suppressed.contains($0.key) }
            .min { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
        guard let candidate else { return nil }
        return SenseLine(
            text: "\(ordinalWord(candidate.value.count)) walk in the last 30 days carrying some form of '\(candidate.key)'.",
            lemma: candidate.key
        )
    }
}

// MARK: - Track 4: question density (cross-walk)

extension DossierSenses {

    static func questionCount(in text: String) -> Int {
        text.filter { $0 == "?" }.count
    }

    static func questionDensity(input: Input, suppressed: Set<String>) -> SenseLine? {
        let todayCount = input.currentRecordings.reduce(0) { $0 + questionCount(in: $1.text) }
        guard todayCount >= questionMinCount else { return nil }
        let windowStart = input.walkStart.addingTimeInterval(-ThreadStore.recurrenceWindow)
        var countsByWalk: [UUID: Int] = [:]
        for entry in input.historyTranscripts {
            guard let walk = input.walkIndex[entry.recordingUUID],
                  walk.walkUUID != input.currentWalkUUID,
                  let instant = input.recordingTimestamps[entry.recordingUUID],
                  instant >= windowStart, instant <= input.walkEnd else { continue }
            countsByWalk[walk.walkUUID, default: 0] += questionCount(in: entry.transcript)
        }
        guard countsByWalk.count >= questionMinHistoryWalks else { return nil }
        let history = countsByWalk.values.sorted()
        guard Double(todayCount) >= questionMedianRatio * median(history.map(Double.init)),
              todayCount > history.last ?? 0 else { return nil }
        return SenseLine(
            text: "\(capitalizedCount(todayCount)) of today's sentences were questions — more than any walk in the last 30 days.",
            lemma: nil
        )
    }
}

// MARK: - Track 4: theme-marker coloring (current walk)

extension DossierSenses {

    static func markerColoring(input: Input, suppressed: Set<String>) -> SenseLine? {
        for thread in activeThreads(in: input) where !suppressed.contains(thread.lemma) {
            for recording in input.currentRecordings {
                guard let theme = recording.themes.first(where: { $0.lemma == thread.lemma }),
                      let text = markerLine(theme: theme, displayTerm: thread.displayTerm,
                                            text: recording.text) else { continue }
                return SenseLine(text: text, lemma: thread.lemma)
            }
        }
        return nil
    }

    static func markerLine(theme: Theme, displayTerm: String, text: String) -> String? {
        let tokens = TranscriptNLP.wordTokenOffsets(in: text)
        guard !tokens.isEmpty else { return nil }
        var windowIndices = IndexSet()
        for mention in theme.mentions {
            guard let index = tokens.lastIndex(where: { $0.start <= mention.start }) else { continue }
            windowIndices.insert(
                integersIn: max(0, index - markerWindowRadius)...min(tokens.count - 1, index + markerWindowRadius)
            )
        }
        guard !windowIndices.isEmpty else { return nil }
        let windowTokens = windowIndices.map { tokens[$0].token }
        let windowAbsolutist = windowTokens.filter { MarkerLexicons.absolutist.contains($0) }.count
        guard windowAbsolutist >= markerMinWindowAbsolutist else { return nil }
        let totalAbsolutist = tokens.filter { MarkerLexicons.absolutist.contains($0.token) }.count
        let windowDensity = Double(windowAbsolutist) / Double(windowTokens.count)
        let overallDensity = Double(totalAbsolutist) / Double(tokens.count)
        guard overallDensity > 0, windowDensity >= markerMinDensityRatio * overallDensity else { return nil }
        let restTokenCount = tokens.count - windowTokens.count
        let restAbsolutist = totalAbsolutist - windowAbsolutist
        let restDensity = restTokenCount > 0 ? Double(restAbsolutist) / Double(restTokenCount) : 0
        // Vs-rest ratio matches the line's own claim; when the rest holds no
        // absolutist words at all, the vs-overall ratio under-claims — a
        // descriptive line may understate, never overstate.
        let ratio = restDensity > 0 ? windowDensity / restDensity : windowDensity / overallDensity
        return "Absolutist words cluster around '\(displayTerm)' — \(timesPhrase(Int(ratio))) the density of the rest of the walk's speech."
    }
}

// MARK: - Track 4: photo adjacency (current walk, place-tied)

extension DossierSenses {

    static func photoAdjacency(input: Input, suppressed: Set<String>) -> SenseLine? {
        let placedPhotos = input.photos.compactMap { photo -> (capturedAt: Date, coordinate: Coordinate)? in
            photo.coordinate.map { (photo.capturedAt, $0) }
        }
        guard !placedPhotos.isEmpty else { return nil }
        var best: (distance: CLLocationDistance, gap: TimeInterval, capturedAt: Date,
                   lemma: String, displayTerm: String)?
        for thread in activeThreads(in: input) where !suppressed.contains(thread.lemma) {
            for recording in input.currentRecordings
            where recording.themes.contains(where: { $0.lemma == thread.lemma }) {
                guard let fix = input.fixes[recording.uuid], qualifies(fix) else { continue }
                for photo in placedPhotos {
                    let separation = distance(fix.coordinate, photo.coordinate)
                    guard separation <= photoTieRadius else { continue }
                    let gap = intervalGap(photo.capturedAt, start: recording.start, end: recording.end)
                    guard gap <= photoTieMaxInterval else { continue }
                    // Place first, time second, then capture order — the tie
                    // is about ground shared, not clocks.
                    if best == nil
                        || (separation, gap, photo.capturedAt) < (best!.distance, best!.gap, best!.capturedAt) {
                        best = (separation, gap, photo.capturedAt, thread.lemma, thread.displayTerm)
                    }
                }
            }
        }
        guard let best else { return nil }
        return SenseLine(text: "A photo was taken near where '\(best.displayTerm)' was spoken.",
                         lemma: best.lemma)
    }

    static func intervalGap(_ instant: Date, start: Date, end: Date) -> TimeInterval {
        if instant >= start && instant <= end { return 0 }
        return min(abs(instant.timeIntervalSince(start)), abs(instant.timeIntervalSince(end)))
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

// MARK: - Track 3: weather weave (cross-walk)

extension DossierSenses {

    enum WeatherBucket: Hashable {
        case rain, snow, clear, cloud, wind, fog, unknown
    }

    /// Collapses the app's stored `WeatherCondition` rawValues. Anything
    /// unrecognized lands in `unknown`, which excludes the walk from claims —
    /// the drift test keeps this total over the storable vocabulary.
    static func bucket(forStoredCondition raw: String) -> WeatherBucket {
        switch raw {
        case "clear": return .clear
        case "partlyCloudy", "overcast", "haze": return .cloud
        case "lightRain", "heavyRain", "thunderstorm": return .rain
        case "snow": return .snow
        case "fog": return .fog
        case "wind": return .wind
        default: return .unknown
        }
    }

    static func skyPhrase(_ bucket: WeatherBucket) -> String? {
        switch bucket {
        case .rain: return "under rain"
        case .snow: return "under snow"
        case .clear: return "under clear skies"
        case .cloud: return "under cloud"
        case .wind: return "in wind"
        case .fog: return "in fog"
        case .unknown: return nil
        }
    }

    static func weatherWeave(input: Input, suppressed: Set<String>) -> SenseLine? {
        let windowStart = input.walkStart.addingTimeInterval(-ThreadStore.recurrenceWindow)
        let inWindow = input.walkSnapshots.filter { $0.startDate >= windowStart && $0.startDate <= input.walkEnd }
        var buckets: [UUID: WeatherBucket] = [:]
        for row in inWindow {
            buckets[row.walkUUID] = row.weatherCondition.map(bucket(forStoredCondition:)) ?? .unknown
        }
        let known = buckets.values.filter { $0 != .unknown }
        guard !known.isEmpty else { return nil }
        let majority = Dictionary(grouping: known, by: { $0 })
            .first { Double($0.value.count) / Double(known.count) > 0.5 }?.key
        for thread in activeThreads(in: input) where !suppressed.contains(thread.lemma) {
            let walkUUIDs = Set(
                thread.appearances
                    .filter { $0.date >= windowStart && $0.date <= input.walkEnd }
                    .map(\.walkUUID)
            )
            guard walkUUIDs.count >= 2 else { continue }
            let themeBuckets = walkUUIDs.map { buckets[$0] ?? .unknown }
            guard let shared = themeBuckets.first,
                  shared != .unknown,
                  themeBuckets.allSatisfy({ $0 == shared }),
                  shared != majority,
                  let phrase = skyPhrase(shared) else { continue }
            let head = walkUUIDs.count == 2 ? "Both walks" : "All \(walkUUIDs.count) walks"
            return SenseLine(text: "\(head) where '\(thread.displayTerm)' surfaced were \(phrase).",
                             lemma: thread.lemma)
        }
        return nil
    }
}
