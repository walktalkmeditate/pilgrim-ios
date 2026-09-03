import SwiftUI

/// A photo filling the screen. Three ways out, because a full-screen cover
/// has no system dismissal of its own: the close button, a tap, or a
/// swipe down. Pinch to look closer; a tap while zoomed only zooms back.
struct WayPhotoViewer: View {
    let image: UIImage
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(y: dragOffset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale = max(1, min(4, $0)) }
                        .onEnded { _ in if scale < 1.05 { withAnimation { scale = 1 } } }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if scale == 1 { dragOffset = max(0, value.translation.height) }
                        }
                        .onEnded { value in
                            if scale == 1, value.translation.height > 100 {
                                onClose()
                            } else {
                                withAnimation { dragOffset = 0 }
                            }
                        }
                )
                .onTapGesture {
                    if scale > 1 { withAnimation { scale = 1 } } else { onClose() }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Close photo")
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(Constants.Typography.displayMedium)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(Constants.UI.Padding.normal)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close photo")
        }
    }
}
