import SwiftUI

/// Two staffs leaning together: dōgyō ninin, the ink-scroll mark of a walk
/// that honored a Way to its end.
struct StaffsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.minX + w * 0.20, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.55, y: rect.minY + h * 0.08))
        path.move(to: CGPoint(x: rect.minX + w * 0.80, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.45, y: rect.minY + h * 0.08))
        path.addEllipse(in: CGRect(x: rect.minX + w * 0.42, y: rect.minY, width: w * 0.16, height: h * 0.10))
        return path.strokedPath(StrokeStyle(lineWidth: max(1, w * 0.08), lineCap: .round))
    }
}
