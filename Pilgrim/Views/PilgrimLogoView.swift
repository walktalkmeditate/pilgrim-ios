import SwiftUI

struct PilgrimLogoView: View {

    var size: CGFloat = 80
    var color: Color = .stone
    var animated: Bool = false

    @State private var appeared = false

    var body: some View {
        Image("pilgrimLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            .opacity(animated && !appeared ? 0 : 1)
            .onAppear {
                if animated {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        appeared = true
                    }
                }
            }
    }
}
