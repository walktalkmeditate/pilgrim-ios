import SwiftUI
import CoreStore

struct HomeView: View {

    @ObservedObject var viewModel: HomeViewModel
    @State private var selectedWalk: Walk?

    var body: some View {
        NavigationStack {
            InkScrollView(
                snapshots: viewModel.walkSnapshots,
                onTapWalk: { id in
                    selectedWalk = viewModel.walk(for: id)
                }
            )
            .background(Color.parchment)
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
            .sheet(item: $selectedWalk) { walk in
                WalkSummaryView(walk: walk)
            }
            .onChange(of: selectedWalk) { old, new in
                if old != nil && new == nil {
                    viewModel.loadWalks()
                }
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

extension Walk: @retroactive Identifiable {
    private static let nilSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public var id: UUID { uuid ?? Self.nilSentinel }
}
