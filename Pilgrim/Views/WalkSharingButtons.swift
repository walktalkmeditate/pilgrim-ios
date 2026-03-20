import SwiftUI

struct WalkSharingButtons: View {

    let walk: WalkInterface
    @State private var showJourneySheet = false
    @State private var shareItem: NamedImageItem?
    @State private var isGenerating = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var hasRoute: Bool {
        walk.routeData.count >= 2
    }

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
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item])
            }
        }
    }

    // MARK: - Image Share Row

    private var imageShareRow: some View {
        HStack(spacing: Constants.UI.Padding.big) {
            Spacer()
            shareButton(
                icon: "seal.fill",
                label: "Seal",
                subtitle: "Share as image"
            ) {
                isGenerating = true
                let dateSuffix = Self.dateFormatter.string(from: walk.startDate)
                Task.detached(priority: .userInitiated) {
                    let image = SealGenerator.generate(for: walk, size: 512)
                    let item = NamedImageItem(image: image, filename: "pilgrim-seal-\(dateSuffix)")
                    await MainActor.run {
                        isGenerating = false
                        shareItem = item
                    }
                }
            }
            shareButton(
                icon: "paintbrush.pointed.fill",
                label: "Etegami",
                subtitle: "Share as postcard"
            ) {
                isGenerating = true
                let dateSuffix = Self.dateFormatter.string(from: walk.startDate)
                Task.detached(priority: .userInitiated) {
                    let image = EtegamiGenerator.generate(for: walk)
                    let item = NamedImageItem(image: image, filename: "pilgrim-etegami-\(dateSuffix)")
                    await MainActor.run {
                        isGenerating = false
                        shareItem = item
                    }
                }
            }
            Spacer()
        }
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

    private var journeySection: some View {
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
}

// MARK: - Named Image Item Provider

class NamedImageItem: NSObject, UIActivityItemSource, Identifiable {
    let image: UIImage
    let filename: String
    let id = UUID()

    init(image: UIImage, filename: String) {
        self.image = image
        self.filename = filename
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        "public.png"
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        filename
    }
}
