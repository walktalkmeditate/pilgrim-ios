import SwiftUI

/// The shared volume-row idiom: label, live percentage, stone-tinted slider
/// persisting through the caller's closure on change.
struct VolumeSliderRow: View {
    let title: String
    @Binding var volume: Double
    var labelColor: Color = .ink
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(Constants.Typography.body)
                    .foregroundColor(labelColor)
                Spacer()
                Text("\(Int(volume * 100))%")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
            Slider(value: $volume, in: 0...1)
                .tint(.stone)
                .onChange(of: volume) { _, value in
                    onChange(value)
                }
        }
    }
}
