import SwiftUI

struct PromptDetailView: View {

    let prompt: GeneratedPrompt
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedFeedback = false
    @State private var showShareSheet = false
    @State private var copyScale: CGFloat = 1.0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.UI.Padding.big) {
                    HStack {
                        Image(systemName: prompt.style.icon)
                            .font(.title2)
                            .foregroundColor(.stone)
                        Text(prompt.style.title)
                            .font(Constants.Typography.displayMedium)
                            .foregroundColor(.ink)
                    }

                    Text(prompt.text)
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                        .textSelection(.enabled)

                    actionButtons
                }
                .padding(Constants.UI.Padding.normal)
            }
            .background(Color.parchment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.stone)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [prompt.text])
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: Constants.UI.Padding.normal) {
            Button {
                UIPasteboard.general.string = prompt.text
                withAnimation(.easeOut(duration: 0.15)) { copyScale = 0.95 }
                withAnimation(.easeOut(duration: 0.15).delay(0.15)) { copyScale = 1.0 }
                showCopiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showCopiedFeedback = false
                }
            } label: {
                Label(
                    showCopiedFeedback ? "Copied!" : "Copy",
                    systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc"
                )
                .font(Constants.Typography.button)
                .foregroundColor(.parchment)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.stone)
                .cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .scaleEffect(copyScale)

            Button {
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(Constants.Typography.button)
                    .foregroundColor(.stone)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                            .stroke(Color.stone, lineWidth: 1.5)
                    )
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
