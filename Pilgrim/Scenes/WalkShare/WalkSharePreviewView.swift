import SwiftUI
import UIKit

struct WalkSharePreviewView: View {

    @ObservedObject var loader: WebViewLoader
    let shareURL: String
    let onDismiss: () -> Void

    @State private var captionOpacity: Double = 0
    @State private var showCopiedToast = false
    @State private var toastGeneration = 0

    var body: some View {
        ZStack {
            Color.parchment.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                contentArea
                Spacer(minLength: 0)
            }

            VStack {
                Spacer()
                floatingActionBar
            }
        }
        .onAppear {
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            let delay = reduceMotion ? 0.0 : 0.2
            let duration = reduceMotion ? 0.2 : 0.3
            withAnimation(.easeInOut(duration: duration).delay(delay)) {
                captionOpacity = 1
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("Your walk.")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
                .opacity(captionOpacity)

            Spacer()

            Button("Done", action: onDismiss)
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.vertical, Constants.UI.Padding.small)
        .background(Color.parchment)
        .accessibilitySortPriority(3)
    }

    // MARK: - Content area

    private var contentArea: some View {
        ZStack {
            WebViewRepresentable(webView: loader.webView)
                .opacity(loader.loadState == .loaded ? 1 : 0)

            if loader.loadState == .loading {
                skeleton
            }

            if loader.loadState == .failed {
                failureView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: loader.loadState)
        .accessibilitySortPriority(2)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
            Rectangle()
                .fill(Color.fog.opacity(0.2))
                .frame(height: 28)
                .frame(maxWidth: .infinity)

            ForEach(0..<5, id: \.self) { _ in
                Rectangle()
                    .fill(Color.fog.opacity(0.15))
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
            }

            Rectangle()
                .fill(Color.fog.opacity(0.1))
                .frame(height: 140)
                .frame(maxWidth: .infinity)
        }
        .padding(Constants.UI.Padding.big)
        .transition(.opacity)
    }

    private var failureView: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Text("The scroll will appear when your connection returns.")
                .font(Constants.Typography.body)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Constants.UI.Padding.big)

            Button("Retry", action: { loader.retry() })
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
                .padding(.horizontal, Constants.UI.Padding.big)
                .padding(.vertical, 12)
                .overlay(
                    Capsule()
                        .stroke(Color.stone.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Floating action bar

    private var floatingActionBar: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            copyButton
            shareButton
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.vertical, Constants.UI.Padding.small)
        .background(
            Color.parchment
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: -2)
        )
        .accessibilitySortPriority(1)
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = shareURL
            toastGeneration += 1
            let gen = toastGeneration
            showCopiedToast = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                if toastGeneration == gen { showCopiedToast = false }
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
    }

    @ViewBuilder
    private var shareButton: some View {
        if let url = URL(string: shareURL) {
            ShareLink(item: url) {
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
