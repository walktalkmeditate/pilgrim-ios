import SwiftUI

struct HonorSummaryData: Equatable {
    let wayTitle: String
    /// Positive when the honoring walker arrived before the companion.
    let arrivedBeforeTheirsSeconds: Double?
    let voicesHeard: Int
    let repliesMade: Int
}

enum HonorSummaryModel {
    static func summaryData(for walk: WalkInterface, way: Way?, link: WayLink?, replies: [Int: String]) -> HonorSummaryData? {
        let types = walk.workoutEvents.map(\.eventType)
        guard types.contains(.honorMode) else { return nil }
        // The dot walked the companion's timeline; the summary reads the
        // numbers the engine recorded at arrival, never a recomputation.
        var delta: Double?
        if let theirs = link?.theirSeconds, let yours = link?.yourSeconds { delta = theirs - yours }
        return HonorSummaryData(
            wayTitle: way?.title ?? "a way that has been removed",
            arrivedBeforeTheirsSeconds: delta,
            voicesHeard: way?.voiceCount ?? 0,
            repliesMade: replies.count)
    }
}

struct HonorSummarySection: View {
    let data: HonorSummaryData

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text("in their steps").font(Constants.Typography.caption).foregroundColor(.fog)
            Text(data.wayTitle).font(Constants.Typography.heading).foregroundColor(.ink)
            if let delta = data.arrivedBeforeTheirsSeconds {
                Text(deltaLine(delta)).font(Constants.Typography.caption).foregroundColor(.fog)
            }
            HStack {
                if data.voicesHeard > 0 { Text("\(data.voicesHeard) voices along the way") }
                if data.repliesMade > 0 { Text("· \(data.repliesMade) replies") }
            }
            .font(Constants.Typography.caption).foregroundColor(.fog)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Constants.UI.Padding.normal)
        .background(RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.big).fill(Color.parchmentSecondary))
    }

    private func deltaLine(_ delta: Double) -> String {
        let minutes = Int(abs(delta) / 60)
        if minutes == 0 { return "you arrived together" }
        return delta > 0 ? "they arrived \(minutes) minutes after you" : "they arrived \(minutes) minutes before you"
    }
}
