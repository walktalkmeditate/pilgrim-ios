import SwiftUI

struct PilgrimLogoView: View {

    var size: CGFloat = 80
    var color: Color = .stone
    var animated: Bool = false
    @Binding var breathing: Bool

    @State private var appeared = false
    @State private var breathScale: CGFloat = 1.0
    @AppStorage("selectedVoiceGuidePackId") private var selectedGuideId: String?
    @AppStorage("voiceGuideEnabled") private var voiceGuideEnabled = false

    private static let guideIds: Set<String> = ["breeze", "drift", "dusk", "ember", "river", "sage", "stone"]

    private var logoImageName: String {
        if voiceGuideEnabled, let id = selectedGuideId, Self.guideIds.contains(id) {
            return "pilgrimLogo-\(id)"
        }
        return "pilgrimLogo"
    }

    init(size: CGFloat = 80, color: Color = .stone, animated: Bool = false, breathing: Binding<Bool> = .constant(false)) {
        self.size = size
        self.color = color
        self.animated = animated
        self._breathing = breathing
    }

    var body: some View {
        Image(logoImageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            .scaleEffect(breathScale)
            .opacity(animated && !appeared ? 0 : 1)
            .onAppear {
                if animated {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        appeared = true
                    }
                }
            }
            .onChange(of: breathing) { _, isBreathing in
                if isBreathing {
                    withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                        breathScale = 1.02
                    }
                } else {
                    withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) {
                        breathScale = 1.0
                    }
                }
            }
    }

    static func appIconName(for guideId: String?) -> String? {
        guard let id = guideId, guideIds.contains(id) else { return nil }
        return "AppIcon\(id.prefix(1).uppercased())\(id.dropFirst())"
    }
}
