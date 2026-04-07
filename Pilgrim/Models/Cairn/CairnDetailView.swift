import SwiftUI

struct CairnDetailView: View {

    let cairn: CachedCairn
    let canPlaceStone: Bool
    let onPlaceStone: (() -> Void)?

    @State private var appeared = false
    @State private var breathing = false

    private var tier: CairnTier { cairn.tier }
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    var body: some View {
        VStack(spacing: 0) {
            heroSection
            infoSection
            if let next = tier.nextTier {
                progressSection(next: next)
            } else {
                eternalBadge
            }
            if canPlaceStone, let onPlaceStone {
                placeButton(action: onPlaceStone)
            }
        }
        .padding(Constants.UI.Padding.big)
        .background(tierGradient)
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                appeared = true
            }
            if tier.rawValue >= CairnTier.large.rawValue {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            // Kanji watermark
            Text(tierKanji)
                .font(.system(size: 120, weight: .ultraLight))
                .foregroundColor(tierAccentColor.opacity(kanjiOpacity))

            // Glow ring for great+ tiers
            if tier.rawValue >= CairnTier.great.rawValue {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowColor.opacity(breathing ? glowIntensity : glowIntensity * 0.5), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: breathing ? 90 : 80
                        )
                    )
                    .frame(width: 180, height: 180)
            }

            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .light))
                .foregroundStyle(iconGradient)
                .scaleEffect(appeared ? 1.0 : entryScale)
                .opacity(appeared ? 1.0 : 0)
                .scaleEffect(breathing ? 1.03 : 1.0)
        }
        .frame(height: 140)
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(spacing: Constants.UI.Padding.xs) {
            Text("\(cairn.stoneCount)")
                .font(Constants.Typography.displayLarge)
                .foregroundColor(.ink)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

            Text(cairn.stoneCount == 1 ? "stone" : "stones")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)

            Text(tierDescription)
                .font(Constants.Typography.body.italic())
                .foregroundColor(.stone)
                .multilineTextAlignment(.center)
                .padding(.top, Constants.UI.Padding.xs)

            timestamps
                .padding(.top, Constants.UI.Padding.small)
        }
    }

    // MARK: - Progress

    private func progressSection(next: CairnTier) -> some View {
        let stonesNeeded = next.threshold - cairn.stoneCount
        let range = next.threshold - tier.threshold
        let progress = range > 0 ? Double(cairn.stoneCount - tier.threshold) / Double(range) : 0

        return VStack(spacing: Constants.UI.Padding.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.fog.opacity(0.15))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressBarColor.opacity(0.6))
                        .frame(width: geo.size.width * max(0.02, appeared ? progress : 0), height: 4)
                }
            }
            .frame(height: 4)

            Text("\(stonesNeeded) more to become \(nextTierName(next))")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
        .padding(.top, Constants.UI.Padding.normal)
    }

    private var eternalBadge: some View {
        Text("108")
            .font(.system(size: 14, weight: .light, design: .serif))
            .foregroundColor(.dawn.opacity(breathing ? 0.8 : 0.5))
            .tracking(4)
            .padding(.top, Constants.UI.Padding.normal)
    }

    // MARK: - Place Button

    private func placeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Place a Stone")
                .font(Constants.Typography.button)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.stone)
                .foregroundColor(.parchment)
                .cornerRadius(Constants.UI.CornerRadius.normal)
        }
        .padding(.top, Constants.UI.Padding.normal)
    }

    // MARK: - Timestamps

    private var timestamps: some View {
        VStack(spacing: 2) {
            if let created = parseDate(cairn.createdAt) {
                Text("First stone \(Self.relativeFormatter.localizedString(for: created, relativeTo: Date()))")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog.opacity(0.6))
            }
            if let lastPlaced = parseDate(cairn.lastPlacedAt),
               cairn.stoneCount > 1 {
                Text("Last stone \(Self.relativeFormatter.localizedString(for: lastPlaced, relativeTo: Date()))")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog.opacity(0.6))
            }
        }
    }

    // MARK: - Tier Properties

    private var iconName: String {
        tier.rawValue >= CairnTier.medium.rawValue ? "mountain.2.fill" : "mountain.2"
    }

    private var iconSize: CGFloat {
        switch tier {
        case .faint: return 32
        case .small: return 38
        case .medium: return 44
        case .large: return 50
        case .great: return 56
        case .sacred: return 62
        case .eternal: return 68
        }
    }

    private var entryScale: CGFloat {
        switch tier {
        case .faint: return 0.8
        case .small: return 0.6
        default: return 0.4
        }
    }

    private var iconGradient: LinearGradient {
        switch tier {
        case .faint, .small:
            return LinearGradient(colors: [Color.fog.opacity(0.5), Color.fog.opacity(0.3)], startPoint: .top, endPoint: .bottom)
        case .medium, .large:
            return LinearGradient(colors: [Color.stone.opacity(0.8), Color.stone.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        case .great, .sacred:
            return LinearGradient(colors: [Color.stone, Color.dawn.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        case .eternal:
            return LinearGradient(colors: [Color.dawn, Color.stone], startPoint: .top, endPoint: .bottom)
        }
    }

    private var tierKanji: String {
        switch tier {
        case .faint: return "\u{77F3}"   // 石 stone
        case .small: return "\u{7A4D}"   // 積 stack
        case .medium: return "\u{9053}"  // 道 path
        case .large: return "\u{5C0E}"   // 導 guide
        case .great: return "\u{5C71}"   // 山 mountain
        case .sacred: return "\u{8056}"  // 聖 sacred
        case .eternal: return "\u{6C38}" // 永 eternal
        }
    }

    private var kanjiOpacity: Double {
        switch tier {
        case .faint: return 0.04
        case .small: return 0.05
        case .medium, .large: return 0.06
        case .great, .sacred: return 0.07
        case .eternal: return 0.08
        }
    }

    private var glowColor: Color {
        switch tier {
        case .great: return .stone
        case .sacred: return .dawn
        case .eternal: return .dawn
        default: return .clear
        }
    }

    private var glowIntensity: Double {
        switch tier {
        case .great: return 0.15
        case .sacred: return 0.22
        case .eternal: return 0.3
        default: return 0
        }
    }

    private var progressBarColor: Color {
        switch tier {
        case .faint, .small, .medium: return .stone
        case .large, .great: return .stone
        case .sacred, .eternal: return .dawn
        }
    }

    private var tierGradient: some ShapeStyle {
        LinearGradient(
            colors: [tierAccentColor.opacity(0.06), Color.clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var tierAccentColor: Color {
        switch tier {
        case .faint, .small, .medium: return .fog
        case .large, .great: return .stone
        case .sacred, .eternal: return .dawn
        }
    }

    private var tierDescription: String {
        switch tier {
        case .faint: return "A mark barely visible"
        case .small: return "A small gathering of stones"
        case .medium: return "A cairn takes shape"
        case .large: return "A steady guide on the path"
        case .great: return "Many hands have built this"
        case .sacred: return "A place of reverence"
        case .eternal: return "An eternal cairn"
        }
    }

    private func nextTierName(_ next: CairnTier) -> String {
        switch next {
        case .faint: return "a faint mark"
        case .small: return "a small cairn"
        case .medium: return "a growing cairn"
        case .large: return "a steady cairn"
        case .great: return "a great cairn"
        case .sacred: return "a sacred cairn"
        case .eternal: return "eternal"
        }
    }

    private func parseDate(_ string: String) -> Date? {
        Self.isoFormatter.date(from: string)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
