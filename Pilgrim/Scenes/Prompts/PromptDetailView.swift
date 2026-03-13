import SwiftUI

struct PromptDetailView: View {

    let prompt: GeneratedPrompt
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedFeedback = false
    @State private var showShareSheet = false
    @State private var copyScale: CGFloat = 1.0
    @State private var showAIPills = false
    @State private var copyResetWorkItem: DispatchWorkItem?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.UI.Padding.big) {
                    HStack {
                        Image(systemName: prompt.icon)
                            .font(.title2)
                            .foregroundColor(.stone)
                        Text(prompt.title)
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
        VStack(spacing: Constants.UI.Padding.small) {
            HStack(spacing: Constants.UI.Padding.normal) {
                Button {
                    UIPasteboard.general.string = prompt.text
                    withAnimation(.easeOut(duration: 0.15)) { copyScale = 0.95 }
                    withAnimation(.easeOut(duration: 0.15).delay(0.15)) { copyScale = 1.0 }
                    showCopiedFeedback = true
                    withAnimation(.easeOut(duration: 0.3)) { showAIPills = true }
                    copyResetWorkItem?.cancel()
                    let workItem = DispatchWorkItem {
                        withAnimation {
                            showCopiedFeedback = false
                            showAIPills = false
                        }
                    }
                    copyResetWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
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

            if showAIPills {
                VStack(spacing: Constants.UI.Padding.small) {
                    Text("Paste in your favorite AI")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)

                    HStack(spacing: Constants.UI.Padding.small) {
                        aiPill(name: "ChatGPT", url: "https://chat.openai.com/")
                        aiPill(name: "Claude", url: "https://claude.ai/new")
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func aiPill(name: String, url: String) -> some View {
        Button {
            if let url = URL(string: url) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 4) {
                Text(name)
                    .font(Constants.Typography.caption)
                    .fontWeight(.semibold)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
            }
            .foregroundColor(.stone)
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.vertical, Constants.UI.Padding.small)
            .background(Color.parchmentSecondary)
            .clipShape(Capsule())
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
