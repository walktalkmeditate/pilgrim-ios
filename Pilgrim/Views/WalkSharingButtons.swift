import SwiftUI

struct WalkSharingButtons: View {

    let walk: WalkInterface
    @State private var showJourneySheet = false
    @State private var shareURL: URL?
    @State private var isGenerating = false

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()

    private var hasRoute: Bool {
        walk.routeData.count >= 2
    }

    private var cachedShare: ShareService.CachedShare? {
        guard let uuid = walk.uuid else { return nil }
        return ShareService.cachedShare(for: uuid)
    }

    private static let expiryFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

    var body: some View {
        if hasRoute {
            VStack(spacing: Constants.UI.Padding.normal) {
                imageShareRow
                divider
                journeySection
            }
            .padding(Constants.UI.Padding.normal)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
            .sheet(isPresented: $showJourneySheet) {
                WalkShareView(walk: walk)
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Image Share Row

    private var imageShareRow: some View {
        HStack(spacing: Constants.UI.Padding.big) {
            Spacer()
            shareButton(
                icon: "seal.fill",
                label: "Goshuin",
                subtitle: "Share as image"
            ) {
                isGenerating = true
                let input = SealInput(walk: walk)
                let suffix = Self.dateTimeFormatter.string(from: walk.startDate)
                Task.detached(priority: .userInitiated) {
                    let image = SealGenerator.generate(from: input, size: 512)
                    let url = Self.writeToTemp(image: image, name: "pilgrim-seal-\(suffix)")
                    await MainActor.run {
                        isGenerating = false
                        shareURL = url
                    }
                }
            }
            shareButton(
                icon: "paintbrush.pointed.fill",
                label: "Etegami",
                subtitle: "Share as postcard"
            ) {
                isGenerating = true
                let input = SealInput(walk: walk)
                let suffix = Self.dateTimeFormatter.string(from: walk.startDate)
                Task.detached(priority: .userInitiated) {
                    let image = EtegamiGenerator.generate(from: input)
                    let url = Self.writeToTemp(image: image, name: "pilgrim-etegami-\(suffix)")
                    await MainActor.run {
                        isGenerating = false
                        shareURL = url
                    }
                }
            }
            Spacer()
        }
        .disabled(isGenerating)
        .overlay {
            if isGenerating {
                SwiftUI.ProgressView()
                    .tint(.stone)
            }
        }
    }

    private func shareButton(
        icon: String,
        label: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Constants.UI.Padding.xs) {
                Image(systemName: icon)
                    .font(Constants.Typography.displayMedium)
                    .frame(width: 52, height: 52)
                    .background(Color.stone.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.stone.opacity(0.2), lineWidth: 1)
                    )
                Text(label)
                    .font(Constants.Typography.caption)
                Text(subtitle)
                    .font(Constants.Typography.micro)
                    .foregroundColor(.fog)
            }
            .foregroundColor(.stone)
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Color.fog.opacity(0.15))
            .frame(height: 0.5)
            .padding(.horizontal, Constants.UI.Padding.big)
    }

    // MARK: - Journey Section

    @ViewBuilder
    private var journeySection: some View {
        if let cached = cachedShare {
            if cached.isExpired {
                returnedSection(cached)
            } else {
                activeShareSection(cached)
            }
        } else {
            neverSharedSection
        }
    }

    private var neverSharedSection: some View {
        VStack(spacing: Constants.UI.Padding.xs) {
            Button {
                showJourneySheet = true
            } label: {
                HStack(spacing: Constants.UI.Padding.small) {
                    Image(systemName: "square.and.arrow.up")
                        .font(Constants.Typography.body)
                    Text("Share Journey")
                        .font(Constants.Typography.button)
                }
                .foregroundColor(.stone)
            }

            Text("Create a web page")
                .font(Constants.Typography.micro)
                .foregroundColor(.fog)

            Text("walk.pilgrimapp.org")
                .font(Constants.Typography.micro)
                .foregroundColor(.fog)
                .tracking(1.0)
        }
    }

    // MARK: - Active Share

    private func activeShareSection(_ cached: ShareService.CachedShare) -> some View {
        VStack(spacing: Constants.UI.Padding.xs) {
            Text(cached.url)
                .font(Constants.Typography.caption)
                .foregroundColor(.stone)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Returns to the trail on \(Self.expiryFormatter.string(from: cached.expiry))")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .italic()
        }
    }

    // MARK: - Returned to Trail

    private func returnedSection(_ cached: ShareService.CachedShare) -> some View {
        VStack(spacing: Constants.UI.Padding.xs) {
            Text("This walk has returned to the trail")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .italic()

            Button {
                showJourneySheet = true
            } label: {
                Text("Share again")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.stone)
            }
        }
    }

    // MARK: - File Helpers

    static func writeToTemp(image: UIImage, name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try? image.pngData()?.write(to: url, options: .atomic)
        return url
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
