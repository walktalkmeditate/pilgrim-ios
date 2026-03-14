import SwiftUI

struct ToriiGateShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let pillarWidth = w * 0.1

        path.addRect(CGRect(x: w * 0.15, y: h * 0.2, width: pillarWidth, height: h * 0.8))
        path.addRect(CGRect(x: w * 0.75 - pillarWidth, y: h * 0.2, width: pillarWidth, height: h * 0.8))

        path.addRect(CGRect(x: w * 0.05, y: h * 0.15, width: w * 0.9, height: h * 0.08))

        return path
    }
}
