import SwiftUI

struct WalkSharingButtons: View {

    let walk: WalkInterface
    @State private var showJourneySheet = false
    @State private var shareURL: URL?
    @State private var isGenerating = false
    @State private var showCopiedToast = false
    @State private var copiedToastGeneration = 0
    @State private var shareVersion = 0

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
            .id(shareVersion)
            .sheet(isPresented: $showJourneySheet, onDismiss: { shareVersion += 1 }) {
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
        ZStack {
            if let kanji = kanjiForOption(cached.expiryOption) {
                Text(kanji)
                    .font(.system(size: 120, weight: .ultraLight))
                    .foregroundColor(Color.stone.opacity(watermarkOpacity(cached)))
            }

            VStack(spacing: Constants.UI.Padding.xs) {
                if let label = labelForOption(cached.expiryOption) {
                    Text(label.uppercased())
                        .font(Constants.Typography.micro)
                        .foregroundColor(.stone)
                        .tracking(1.5)
                }

                Text(cached.url)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.stone)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("Returns to the trail on \(Self.expiryFormatter.string(from: cached.expiry))")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .italic()

                HStack(spacing: Constants.UI.Padding.small) {
                    Button {
                        UIPasteboard.general.string = cached.url
                        copiedToastGeneration += 1
                        let gen = copiedToastGeneration
                        showCopiedToast = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            if copiedToastGeneration == gen { showCopiedToast = false }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                            Text(showCopiedToast ? "Copied" : "Copy")
                                .font(Constants.Typography.button)
                                .minimumScaleFactor(0.8)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.parchmentSecondary)
                        .foregroundColor(.stone)
                        .cornerRadius(Constants.UI.CornerRadius.small)
                    }

                    if let shareURL = URL(string: cached.url) {
                        ShareLink(item: shareURL) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                                    .font(Constants.Typography.button)
                                    .minimumScaleFactor(0.8)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.stone)
                            .foregroundColor(.parchment)
                            .cornerRadius(Constants.UI.CornerRadius.small)
                        }
                    }
                }
            }
        }
    }

    private func watermarkOpacity(_ cached: ShareService.CachedShare) -> Double {
        guard let shareDate = cached.shareDate else { return 0.05 }
        let total = cached.expiry.timeIntervalSince(shareDate)
        guard total > 0 else { return 0.025 }
        let elapsed = Date().timeIntervalSince(shareDate)
        let fraction = min(max(elapsed / total, 0), 1)
        return 0.07 - (fraction * 0.045)
    }

    private func kanjiForOption(_ option: String?) -> String? {
        switch option {
        case "moon": return "\u{6708}"
        case "season": return "\u{5B63}"
        case "cycle": return "\u{5DE1}"
        default: return nil
        }
    }

    private func labelForOption(_ option: String?) -> String? {
        switch option {
        case "moon": return "1 moon"
        case "season": return "1 season"
        case "cycle": return "1 cycle"
        default: return nil
        }
    }

    // MARK: - Returned to Trail

    private func returnedSection(_ cached: ShareService.CachedShare) -> some View {
        VStack(spacing: Constants.UI.Padding.xs) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 24))
                .foregroundColor(.fog)

            Text("This walk has returned to the trail")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .italic()

            if let label = labelForOption(cached.expiryOption) {
                Text("Shared for \(label)")
                    .font(Constants.Typography.micro)
                    .foregroundColor(.fog)
            } else {
                Text("This walk was shared")
                    .font(Constants.Typography.micro)
                    .foregroundColor(.fog)
            }

            Rectangle()
                .fill(Color.fog.opacity(0.15))
                .frame(height: 0.5)
                .padding(.horizontal, Constants.UI.Padding.big)

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
