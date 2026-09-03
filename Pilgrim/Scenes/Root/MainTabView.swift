import SwiftUI

enum MainTab {
    case path, journal, settings
}

struct MainTabView: View {

    @State private var selectedTab: MainTab = .path
    @State private var sealShareURL: URL?
    @StateObject private var coordinator = MainCoordinator()
    @EnvironmentObject private var appearanceManager: AppearanceManager

    var body: some View {
        // Touch themeID so the body re-evaluates on appearance flip and
        // .tint(.stone) below recomputes to the new mode's accent color.
        // selectedTab + coordinator @State survive a body re-eval (only
        // identity change resets @State).
        _ = appearanceManager.themeID
        return TabView(selection: $selectedTab) {
            Tab("Path", systemImage: "figure.walk", value: .path) {
                WalkStartView(onStartWalk: { mode in
                    if mode == .honor {
                        coordinator.chooseWay()
                    } else {
                        coordinator.startWalk(mode: mode)
                    }
                })
            }
            .accessibilityIdentifier("tab_path")

            Tab("Journal", systemImage: "book", value: .journal) {
                MainCoordinatorView(coordinator: coordinator)
            }
            .accessibilityIdentifier("tab_journal")

            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
            .accessibilityIdentifier("tab_settings")
        }
        .tint(.stone)
        .fullScreenCover(item: $coordinator.activeWalkViewModel, onDismiss: {
            coordinator.handleActiveWalkDismiss()
        }) { vm in
            ActiveWalkView(viewModel: vm, onCancel: { coordinator.cancelWalk() })
                .constellationDecorated(nebulae: false)
                // A cover sits above the tab view's own overlay, so the
                // "finish this walk first" answer to a link tapped mid-walk
                // has to be repeated here to be seen at all.
                .overlay(alignment: .top) {
                    if let toast = coordinator.pendingLinkToast {
                        HonorLinkToast(text: toast)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut, value: coordinator.pendingLinkToast)
        }
        .sheet(item: $coordinator.completedSnapshot, onDismiss: {
            coordinator.handleSummaryDismiss()
        }) { snapshot in
            WalkSummaryView(walk: snapshot, onWalkAgain: { coordinator.walkAgain($0) })
                .constellationDecorated(nebulae: false)
        }
        .sheet(isPresented: $coordinator.honorWaysPresented, onDismiss: coordinator.promotePendingHonorWay) {
            HonorWaysSheet(
                ownWalks: coordinator.homeViewModel.walks,
                importState: coordinator.honorImportState,
                onChoose: { coordinator.openOverview(for: $0) },
                onPaste: { text in
                    if let id = HonorLink.parse(text: text) { coordinator.openWay(shareId: id) }
                }
            )
        }
        .sheet(item: $coordinator.honorOverviewWay, onDismiss: coordinator.handleOverviewDismiss) { way in
            NavigationStack {
                HonorOverviewView(
                    way: way,
                    importState: coordinator.honorImportState,
                    onBegin: { coordinator.startHonor(way: way) },
                    onClose: { coordinator.honorOverviewWay = nil },
                    onRetryMedia: { coordinator.retryMedia(for: way) },
                    onWalkWithoutMissing: coordinator.walkWithoutMissingVoices
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pilgrimOpenWay)) { note in
            guard let id = note.userInfo?["shareId"] as? String else { return }
            selectedTab = .path
            coordinator.openWay(shareId: id)
        }
        .alert("Save Failed", isPresented: $coordinator.showSaveError) {
            Button("Dismiss") {
                coordinator.activeWalkViewModel = nil
            }
        } message: {
            Text("Your walk could not be saved. Please try again.")
        }
        .alert("Location Required", isPresented: $coordinator.showLocationDenied) {
            Button("Settings", action: coordinator.openSettings)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pilgrim needs location access to track your route. Please enable it in Settings.")
        }
        .overlay {
            if coordinator.showSealReveal, let walk = coordinator.sealRevealWalk {
                SealRevealView(
                    walk: walk,
                    onDismiss: {
                        coordinator.handleSealRevealDismiss()
                    },
                    onShareSeal: { image in
                        let url = WalkSharingButtons.writeToTemp(image: image, name: "pilgrim-seal-\(walk.uuid?.uuidString.prefix(8) ?? "share")")
                        // AF60: dismiss the seal and hold the snapshot; the
                        // summary is presented only after the share sheet
                        // closes, so the two sheets never race.
                        coordinator.handleSealShare()
                        sealShareURL = url
                    }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: coordinator.showSealReveal)
        .sheet(item: $sealShareURL, onDismiss: {
            coordinator.handleSealShareDismiss()
        }) { url in
            ShareSheet(items: [url])
        }
        .overlay(alignment: .top) {
            VStack(spacing: Constants.UI.Padding.xs) {
                if let date = coordinator.recoveredWalkDate {
                    RecoveryBanner(date: date)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let toast = coordinator.pendingLinkToast {
                    HonorLinkToast(text: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut, value: coordinator.recoveredWalkDate != nil)
        .animation(.easeInOut, value: coordinator.pendingLinkToast)
    }
}
