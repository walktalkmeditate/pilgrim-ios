import SwiftUI
import CoreStore

struct HomeView: View {

    @ObservedObject var viewModel: HomeViewModel
    @State private var selectedWalk: Walk?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                InkScrollView(
                    snapshots: viewModel.walkSnapshots,
                    onTapWalk: { id in
                        selectedWalk = viewModel.walk(for: id)
                    }
                )

                startButton
            }
            .background(Color.parchment)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Pilgrim")
                            .font(Constants.Typography.displayLarge)
                            .foregroundColor(.ink)
                        Text(dateSubtitle)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedWalk) { walk in
                WalkSummaryView(walk: walk)
            }
        }
    }

    private static let dateSubtitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private var dateSubtitle: String {
        Self.dateSubtitleFormatter.string(from: Date())
    }

    private var startButton: some View {
        Button(action: viewModel.startWalk) {
            Text("Begin")
                .font(Constants.Typography.heading)
                .foregroundColor(.parchment)
                .frame(maxWidth: .infinity)
                .padding(Constants.UI.Padding.normal)
                .background(Color.stone)
                .clipShape(Capsule())
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .padding(.vertical, Constants.UI.Padding.normal)
    }
}

extension Walk: @retroactive Identifiable {
    private static let nilSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public var id: UUID { uuid ?? Self.nilSentinel }
}
