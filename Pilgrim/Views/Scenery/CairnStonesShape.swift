import SwiftUI

/// Stacked stones — the ink-scroll mark of a seek that found places. The
/// stack grows with the walk's arrivals (one stone per found place on a
/// two-stone base), widest at the bottom, each stone leaning slightly
/// off-axis the way real cairns do.
struct CairnStonesShape: Shape {
    var stones: Int = 3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = max(2, min(stones, 5))
        let w = rect.width
        let rowHeight = rect.height / CGFloat(count)

        for index in 0..<count {
            // index 0 = top stone (narrowest), last = base (widest).
            let fraction = count == 1 ? 1.0 : CGFloat(index) / CGFloat(count - 1)
            let stoneWidth = w * (0.38 + 0.44 * fraction)
            let stoneHeight = rowHeight * 1.05
            let lean = index == count - 1
                ? 0
                : (index.isMultiple(of: 2) ? w * 0.05 : -w * 0.06)
            path.addEllipse(in: CGRect(
                x: rect.midX - stoneWidth / 2 + lean,
                y: rect.minY + CGFloat(index) * rowHeight,
                width: stoneWidth,
                height: stoneHeight
            ))
        }
        return path
    }
}
