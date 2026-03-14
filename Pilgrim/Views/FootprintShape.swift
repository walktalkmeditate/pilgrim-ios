import SwiftUI

struct FootprintShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Heel — rounded oval at the bottom
        path.addEllipse(in: CGRect(
            x: w * 0.22, y: h * 0.75,
            width: w * 0.50, height: h * 0.25
        ))

        // Outer edge — connects heel to ball along the pinky side
        path.addEllipse(in: CGRect(
            x: w * 0.50, y: h * 0.48,
            width: w * 0.22, height: h * 0.34
        ))

        // Ball of foot — wide pad below the toes
        path.addEllipse(in: CGRect(
            x: w * 0.08, y: h * 0.38,
            width: w * 0.62, height: h * 0.22
        ))

        // Big toe — largest, on the inner (left) side
        path.addEllipse(in: CGRect(
            x: w * 0.10, y: h * 0.18,
            width: w * 0.24, height: h * 0.24
        ))

        // Second toe — slightly smaller, tucked next to big toe
        path.addEllipse(in: CGRect(
            x: w * 0.32, y: h * 0.10,
            width: w * 0.18, height: h * 0.22
        ))

        // Third toe — middle
        path.addEllipse(in: CGRect(
            x: w * 0.48, y: h * 0.06,
            width: w * 0.16, height: h * 0.20
        ))

        // Fourth toe — smaller
        path.addEllipse(in: CGRect(
            x: w * 0.62, y: h * 0.10,
            width: w * 0.14, height: h * 0.18
        ))

        // Pinky toe — smallest, set back
        path.addEllipse(in: CGRect(
            x: w * 0.72, y: h * 0.18,
            width: w * 0.12, height: h * 0.14
        ))

        return path
    }
}
