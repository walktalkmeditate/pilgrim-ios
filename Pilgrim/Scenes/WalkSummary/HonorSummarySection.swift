import SwiftUI

struct HonorSummaryData: Equatable {
    let wayTitle: String
    /// Positive when the honoring walker arrived before the companion. Nil
    /// for a stage: there is no companion to arrive before.
    let arrivedBeforeTheirsSeconds: Double?
    /// Every voice the Way carries, not the subset this walk played — the
    /// arrival card's `voicesHeard` is the one that counts what was heard.
    let voicesAlongTheWay: Int
    let repliesMade: Int
    /// Carried explicitly, never inferred from `stageProgressLine`: a stage
    /// walk that earned no ledger entry (the walker never joined the line) is
    /// still a stage walk, and must not be told it walked in someone's steps.
    let isPilgrimageStage: Bool
    /// "14 of 24 km of the stage", from the ledger this walk just wrote.
    let stageProgressLine: String?
    /// The stage's closing line, present only when arrival actually fired.
    let closing: String?
    /// The walker's reply to it, relative to Documents.
    let replyRelativePath: String?
}

enum HonorSummaryModel {
    static func summaryData(for walk: WalkInterface, way: Way?, link: WayLink?,
                            replies: [Int: String], ledger: PilgrimageLedger?) -> HonorSummaryData? {
        let types = walk.workoutEvents.map(\.eventType)
        guard types.contains(.honorMode) else { return nil }
        let stage = way?.stage
        // The dot walked the companion's timeline; the summary reads the
        // numbers the engine recorded at arrival, never a recomputation.
        var delta: Double?
        if stage == nil, let theirs = link?.theirSeconds, let yours = link?.yourSeconds { delta = theirs - yours }
        let arrived = types.contains(.honorArrival)
        return HonorSummaryData(
            wayTitle: way?.title ?? "a way that has been removed",
            arrivedBeforeTheirsSeconds: delta,
            voicesAlongTheWay: way?.voiceCount ?? 0,
            repliesMade: replies.count,
            isPilgrimageStage: stage != nil,
            stageProgressLine: stage.flatMap { stageProgressLine(stage: $0, ledger: ledger) },
            closing: arrived ? stage?.closing : nil,
            replyRelativePath: replies[HonorPersistence.stageReflectionOrigin])
    }

    /// The kilometres the ledger recorded for this stage, against the stage's
    /// own length. Silent when the walk earned no entry.
    static func stageProgressLine(stage: WayStage, ledger: PilgrimageLedger?) -> String? {
        guard let entry = ledger?.stages[String(stage.index)] else { return nil }
        let walked = StatsHelper.string(for: entry.kmWalked * 1000, unit: UnitLength.meters, type: .distance)
        let whole = StatsHelper.string(for: stage.distanceKm * 1000, unit: UnitLength.meters, type: .distance)
        return "\(walked) of \(whole) of the stage"
    }
}

struct HonorSummarySection: View {
    let data: HonorSummaryData
    @StateObject private var player = AudioPlayerModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text(Self.kicker(for: data)).font(Constants.Typography.caption).foregroundColor(.fog)
            Text(data.wayTitle).font(Constants.Typography.heading).foregroundColor(.ink)
            if let stageProgressLine = data.stageProgressLine {
                Text(stageProgressLine).font(Constants.Typography.caption).foregroundColor(.fog)
            }
            if let delta = data.arrivedBeforeTheirsSeconds {
                Text(deltaLine(delta)).font(Constants.Typography.caption).foregroundColor(.fog)
            }
            if let countsLine {
                Text(countsLine).font(Constants.Typography.caption).foregroundColor(.fog)
            }
            if let closing = data.closing {
                Text(closing)
                    .font(Constants.Typography.displayMedium)
                    .foregroundColor(.ink)
                    .padding(.top, Constants.UI.Padding.xs)
            }
            if let replyRelativePath = data.replyRelativePath, let url = replyURL(replyRelativePath) {
                Button { player.toggle(url: url) } label: {
                    Label(player.isPlaying ? "pause" : "your reply",
                          systemImage: player.isPlaying ? "pause.circle" : "play.circle")
                        .font(Constants.Typography.caption).foregroundColor(.stone)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Play your reply to this stage")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Constants.UI.Padding.normal)
        .background(RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal).fill(Color.parchmentSecondary))
        .onDisappear { player.stop() }
    }

    /// The block's opening line. Honor's copy assumes another walker; a
    /// downloaded stage has none, so it names what was actually walked —
    /// the same split `HonorArrivalCardView.title(for:)` makes.
    static func kicker(for data: HonorSummaryData) -> String {
        data.isPilgrimageStage ? "the stage you walked" : "in their steps"
    }

    private var countsLine: String? {
        var parts: [String] = []
        if data.voicesAlongTheWay > 0 {
            parts.append("\(data.voicesAlongTheWay) \(data.voicesAlongTheWay == 1 ? "voice" : "voices") along the way")
        }
        if data.repliesMade > 0 {
            parts.append("\(data.repliesMade) \(data.repliesMade == 1 ? "reply" : "replies")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func deltaLine(_ delta: Double) -> String {
        let minutes = Int(abs(delta) / 60)
        if minutes == 0 { return "you arrived together" }
        let unit = minutes == 1 ? "minute" : "minutes"
        return delta > 0 ? "they arrived \(minutes) \(unit) after you" : "they arrived \(minutes) \(unit) before you"
    }

    /// A relative path from the Way's own replies file: contained under
    /// Documents before it is opened, the way `localMediaURL` does it.
    private func replyURL(_ relativePath: String) -> URL? {
        ActiveWalkViewModel.localMediaURL(for: .recording(relativePath: relativePath),
                                          wayId: "", store: WayStore.shared)
    }
}
