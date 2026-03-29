import SwiftUI

struct GoshuinView: View {

    let walks: [Walk]
    let onSelectWalk: (UUID) -> Void

    @State private var activeFilter: WalkFavicon?
    @State private var shareURL: URL?
    @Environment(\.dismiss) private var dismiss

    private var filteredWalks: [Walk] {
        guard let filter = activeFilter else { return walks }
        return walks.filter { WalkFavicon(rawValue: $0.favicon ?? "") == filter }
    }

    private var pages: [[Walk]] {
        stride(from: 0, to: filteredWalks.count, by: 6).map { start in
            Array(filteredWalks[start..<min(start + 6, filteredWalks.count)])
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                bookContent
                shareButton
            }
            .background(Color.parchment)
            .navigationTitle("Goshuin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Constants.Typography.button)
                        .foregroundColor(.stone)
                }
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.UI.Padding.small) {
                filterToggle(nil, label: "All")
                ForEach(WalkFavicon.allCases, id: \.self) { fav in
                    filterToggle(fav, label: fav.label)
                }
            }
            .padding(.horizontal, Constants.UI.Padding.normal)
        }
        .padding(.vertical, Constants.UI.Padding.small)
    }

    private func filterToggle(_ favicon: WalkFavicon?, label: String) -> some View {
        let isActive = activeFilter == favicon
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeFilter = favicon
            }
        } label: {
            HStack(spacing: 4) {
                if let fav = favicon {
                    Image(systemName: fav.icon)
                        .font(Constants.Typography.caption)
                }
                Text(label)
                    .font(Constants.Typography.caption)
            }
            .padding(.horizontal, Constants.UI.Padding.small)
            .padding(.vertical, 6)
            .background(isActive ? Color.stone.opacity(0.15) : Color.clear)
            .cornerRadius(12)
            .foregroundStyle(isActive ? Color.stone : Color.fog)
        }
    }

    // MARK: - Book Content

    private var bookContent: some View {
        Group {
            if pages.isEmpty {
                emptyState
            } else {
                TabView {
                    ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, pageWalks in
                        GoshuinPageView(
                            walks: pageWalks,
                            allWalks: walks,
                            totalWalkCount: walks.count,
                            globalStartIndex: pageIndex * 6,
                            onSelectWalk: { uuid in
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onSelectWalk(uuid)
                                }
                            }
                        )
                        .padding(.horizontal, Constants.UI.Padding.normal)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Image(systemName: "seal")
                .font(Constants.Typography.displayLarge)
                .foregroundStyle(Color.fog.opacity(0.4))
            Text("Your goshuin will fill as you walk")
                .font(Constants.Typography.body)
                .foregroundStyle(Color.fog)
        }
    }

    // MARK: - Share

    private var shareButton: some View {
        Button {
            renderShareImage()
        } label: {
            Text("Share Goshuin")
                .font(Constants.Typography.button)
                .foregroundStyle(Color.stone)
                .padding(.vertical, Constants.UI.Padding.small)
                .frame(maxWidth: .infinity)
        }
        .padding(Constants.UI.Padding.normal)
        .opacity(pages.isEmpty ? 0 : 1)
    }

    private func renderShareImage() {
        let inputs = filteredWalks.map { SealInput(walk: $0) }
        let allInputs = walks.map { SealInput(walk: $0) }
        Task.detached(priority: .userInitiated) {
            let input = GoshuinShareRenderer.Input(walks: inputs, allWalks: allInputs)
            let image = GoshuinShareRenderer.render(input: input)
            let url = WalkSharingButtons.writeToTemp(image: image, name: "pilgrim-goshuin-\(UUID().uuidString.prefix(8))")
            await MainActor.run { shareURL = url }
        }
    }
}
