import Foundation

struct WayCoordinate: Codable, Equatable {
    let lat: Double
    let lon: Double
}

struct WayPoint: Codable, Equatable {
    let lat: Double
    let lon: Double
    let alt: Double?
    /// Seconds since departure. Wall clock: the original walker's pauses
    /// are inside it, so the companion rests where they rested.
    let t: Double
}

enum VoiceKind: String, Codable { case spoken, ambient }

enum WayMedia: Codable, Equatable {
    /// Relative to `Ways/{id}/media/`.
    case file(String)
    /// Own walk: relative to the Documents directory.
    case recording(relativePath: String)
    /// Own walk: PhotoKit asset.
    case photoAsset(localIdentifier: String)
}

enum WayMomentKind: Codable, Equatable {
    case voice(endFrac: Double, duration: Double, kind: VoiceKind, media: WayMedia)
    case photo(media: WayMedia)
    case waypoint(label: String, icon: String)
    case rest(minutes: Int)
    case meditation(minutes: Int, isEstimate: Bool)
}

struct WayMoment: Codable, Equatable, Identifiable {
    let id: String
    /// Distance fraction along the route: orders moments and gates progress.
    let frac: Double
    /// The true place when the source knows it. Triggers fire on this;
    /// nil falls back to `WayGeometry.coordinate(atFrac:)`.
    let at: WayCoordinate?
    let kind: WayMomentKind
    /// The street or place the sharer's page names for a voice, when the
    /// worker had one. Optional and last: older `way.json` files lack it.
    var place: String?
    /// What they said, when the source transcribed it: the walker's own
    /// recordings carry one; shared walks carry the worker's. Optional and
    /// last, like `place`.
    var transcript: String?

    /// The first sentence of the transcript, for a card that has one line
    /// to spare. Nil when there is nothing to quote.
    var transcriptLine: String? { WayMoment.firstSentence(of: transcript, maxCharacters: 120) }

    static let maxTranscriptCharacters = 600

    /// Trims, drops the empty, and caps at `maxTranscriptCharacters`.
    static func trimmedTranscript(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxTranscriptCharacters))
    }

    static func firstSentence(of transcript: String?, maxCharacters: Int) -> String? {
        guard let transcript = trimmedTranscript(transcript) else { return nil }
        var sentence = transcript
        if let end = transcript.firstIndex(where: { ".!?".contains($0) }) {
            sentence = String(transcript[...end])
        }
        if sentence.count > maxCharacters {
            let cut = sentence.prefix(maxCharacters)
            let atWord = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
            return atWord + "…"
        }
        return sentence
    }

    var isVoice: Bool {
        if case .voice = kind { return true }
        return false
    }

    /// The file behind a voice or photo moment; nil for the other kinds.
    var media: WayMedia? {
        switch kind {
        case .voice(_, _, _, let media): return media
        case .photo(let media): return media
        case .waypoint, .rest, .meditation: return nil
        }
    }
}

enum WaySource: Codable, Equatable {
    case ownWalk(UUID)
    case share(id: String, pageURL: URL)
}

struct WayWeather: Codable, Equatable {
    let condition: String
    let temperatureC: Double?
}

enum WaySpanKind: String, Codable {
    case meditating, talking
}

/// A stretch of the Way walked in a practice other than walking, by distance
/// fraction. The ghost line colors these the way the walk's own route does.
struct WaySpan: Codable, Equatable {
    let startFrac: Double
    let endFrac: Double
    let kind: WaySpanKind
}

struct Way: Codable, Equatable {
    let id: String
    let source: WaySource
    let title: String
    let departedAt: Date
    let tzIdentifier: String?
    let expires: Date?
    let route: [WayPoint]
    let totalDistanceMeters: Double
    let theirActiveSeconds: Double
    let moments: [WayMoment]
    let weather: WayWeather?
    /// Optional and last so a `way.json` written before spans existed still
    /// decodes (as an all-walking Way) and every call site keeps its shape.
    var spans: [WaySpan]?

    var voiceCount: Int { moments.filter(\.isVoice).count }
    var photoCount: Int {
        moments.filter { if case .photo = $0.kind { return true } else { return false } }.count
    }
}

/// `id` is already the store's folder name, so `.sheet(item:)` can key the
/// overview off the Way itself.
extension Way: Identifiable {}
