import SwiftUI
import CoreStore

struct HomeView: View {

    @ObservedObject var viewModel: HomeViewModel
    let onWalkAgain: (WalkInterface) -> Void
    /// The journal's summary sheet is the second road into the Honor
    /// overview, so it owes the coordinator the same promote-on-dismiss the
    /// post-walk summary does (AF60).
    let onSummaryDismiss: () -> Void
    @State private var selectedWalk: Walk?
    @State private var showGoshuin = false
    @State private var unitKey: String = UserPreferences.distanceMeasurementType.safeValue.symbol
    @State private var isWalkExpanded = false

    var body: some View {
        NavigationStack {
            InkScrollView(
                snapshots: viewModel.walkSnapshots,
                onTapWalk: { id in
                    selectedWalk = viewModel.walk(for: id)
                },
                onExpandedChange: { isWalkExpanded = $0 }
            )
            .id(unitKey)
            .canvasBackground()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Pilgrim Log")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
                #if DEBUG
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Seed 32 walks") { seedDebugData() }
                        Button("Clear all walks", role: .destructive) { clearDebugData() }
                    } label: {
                        Image(systemName: "ladybug")
                            .foregroundColor(.ink)
                    }
                }
                #endif
            }
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) {
                if !viewModel.walks.isEmpty && !isWalkExpanded {
                    GoshuinFAB(
                        latestWalk: viewModel.walks.first,
                        action: { showGoshuin = true }
                    )
                    .padding(.trailing, Constants.UI.Padding.normal)
                    .padding(.bottom, Constants.UI.Padding.big)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isWalkExpanded)
            .sheet(item: $selectedWalk, onDismiss: onSummaryDismiss) { walk in
                WalkSummaryView(walk: walk, onWalkAgain: onWalkAgain)
            }
            .sheet(isPresented: $showGoshuin) {
                GoshuinView(
                    walks: viewModel.walks,
                    onSelectWalk: { uuid in
                        selectedWalk = viewModel.walk(for: uuid)
                    }
                )
            }
            .onChange(of: selectedWalk) { old, new in
                if old != nil && new == nil {
                    viewModel.loadWalks()
                }
            }
            .onAppear {
                unitKey = UserPreferences.distanceMeasurementType.safeValue.symbol
                viewModel.loadWalks()
            }
        }
    }

    #if DEBUG
    private func seedDebugData() {
        DebugDataSeeder.seed { count in
            print("[Debug] Seeded \(count) walks")
            viewModel.loadWalks()
        }
    }

    private func clearDebugData() {
        DataManager.deleteAll { success, _ in
            if success {
                print("[Debug] Cleared all walks")
                viewModel.loadWalks()
            }
        }
    }
    #endif
}

extension Walk: Identifiable {
    private static let nilSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public var id: UUID { uuid ?? Self.nilSentinel }
}
