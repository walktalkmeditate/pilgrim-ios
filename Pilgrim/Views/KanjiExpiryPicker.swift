import SwiftUI

struct KanjiExpiryPicker: View {

    @Binding var selected: ExpiryDuration

    enum ExpiryDuration: String, CaseIterable {
        case oneDay
        case sevenDays
        case oneMonth

        var label: String {
            switch self {
            case .oneDay: return "1 day"
            case .sevenDays: return "1 week"
            case .oneMonth: return "1 month"
            }
        }

        var kanji: String {
            switch self {
            case .oneDay: return "\u{65E5}"
            case .sevenDays: return "\u{9031}"
            case .oneMonth: return "\u{6708}"
            }
        }

        var apiValue: String {
            switch self {
            case .oneDay: return "1d"
            case .sevenDays: return "7d"
            case .oneMonth: return "1m"
            }
        }

        var days: Int {
            switch self {
            case .oneDay: return 1
            case .sevenDays: return 7
            case .oneMonth: return 30
            }
        }
    }

    var body: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            ForEach(ExpiryDuration.allCases, id: \.rawValue) { option in
                button(for: option)
            }
        }
    }

    private func button(for option: ExpiryDuration) -> some View {
        let isSelected = selected == option
        return Button {
            selected = option
        } label: {
            ZStack {
                // CJK glyphs require system font — Cormorant Garamond has no kanji coverage
                Text(option.kanji)
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundColor(isSelected ? .parchment.opacity(0.12) : .fog.opacity(0.06))

                Text(option.label)
                    .font(Constants.Typography.caption)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.stone : Color.parchmentSecondary)
            .foregroundColor(isSelected ? .parchment : .fog)
            .cornerRadius(Constants.UI.CornerRadius.small)
        }
    }
}
