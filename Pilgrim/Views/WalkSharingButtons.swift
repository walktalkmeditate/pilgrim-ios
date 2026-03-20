import SwiftUI

struct WalkSharingButtons: View {

    let walk: WalkInterface
    @State private var showJourneySheet = false
    @State private var shareImage: UIImage?

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
            .sheet(item: $shareImage) { image in
                ShareSheet(items: [image])
            }
        }
    }

    // MARK: - Image Share Row

    private var imageShareRow: some View {
        HStack(spacing: Constants.UI.Padding.big) {
            Spacer()
            shareButton(
                icon: "seal.fill",
                label: "Seal"
            ) {
                shareImage = SealGenerator.generate(for: walk, size: 512)
            }
            shareButton(
                icon: "paintbrush.pointed.fill",
                label: "Etegami"
            ) {
                shareImage = EtegamiGenerator.generate(for: walk)
            }
            Spacer()
        }
    }

    private func shareButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Constants.UI.Padding.xs) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(label)
                    .font(Constants.Typography.caption)
            }
            .foregroundColor(.stone)
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Color.fog.opacity(0.3))
            .frame(height: 1)
            .padding(.horizontal, Constants.UI.Padding.normal)
    }

    // MARK: - Journey Section

    private var journeySection: some View {
        VStack(spacing: Constants.UI.Padding.xs) {
            Button {
                showJourneySheet = true
            } label: {
                HStack(spacing: Constants.UI.Padding.small) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                    Text("Share Journey")
                        .font(Constants.Typography.button)
                }
                .foregroundColor(.stone)
            }

            Text("walk.pilgrimapp.org")
                .font(Constants.Typography.micro)
                .foregroundColor(.fog)
                .tracking(1.0)
        }
    }
}

// MARK: - UIImage + Identifiable

extension UIImage: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
