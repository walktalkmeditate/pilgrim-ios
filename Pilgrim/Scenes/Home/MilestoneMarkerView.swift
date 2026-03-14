import SwiftUI

struct MilestoneMarkerView: View {

    let width: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.fog.opacity(0.25))
            .frame(width: width * 0.6, height: 1)
            .accessibilityHidden(true)
    }
}
