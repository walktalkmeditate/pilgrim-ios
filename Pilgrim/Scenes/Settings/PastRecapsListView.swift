import SwiftUI

/// Closed moons since the walker's first card, newest first — a missed
/// invitation line never costs the month. Each row opens the same
/// live-computed recap sheet.
struct PastRecapsListView: View {

    @State private var lunations: [Lunation] = PastRecapsListView.closedLunations()
    @State private var selected: Lunation?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    static func closedLunations(now: Date = Date(), state: LunationRecapState = .shared) -> [Lunation] {
        guard let firstShown = state.firstCardShownAt else { return [] }
        var result: [Lunation] = []
        var index = LunationCalendar.mostRecentClosed(asOf: now).index
        while index >= 0 {
            let lunation = LunationCalendar.lunation(at: index)
            guard lunation.end > firstShown else { break }
            result.append(lunation)
            index -= 1
        }
        return result
    }

    var body: some View {
        List {
            ForEach(lunations) { lunation in
                Button {
                    // Reading a recap here counts as acting on it — the
                    // summary's invitation row stops nagging about a moon
                    // the walker has already seen (spec-consistent: the
                    // invitation exists to surface the recap, not to be
                    // tapped for its own sake). markActedOn is monotonic,
                    // so opening an OLDER moon never regresses the index.
                    LunationRecapState.shared.markActedOn(lunation)
                    selected = lunation
                } label: {
                    HStack {
                        Text(LunationCalendar.moonName(for: lunation))
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Spacer()
                        Text(Self.dateFormatter.string(from: lunation.end))
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Double tap to open this moon's recap")
                .listRowBackground(Color.parchmentSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Past recaps")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .sheet(item: $selected) { lunation in
            LunationRecapView(lunation: lunation)
        }
    }
}
