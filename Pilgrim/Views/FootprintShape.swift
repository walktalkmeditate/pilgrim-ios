import SwiftUI

struct FootprintShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Heel pad
        path.addEllipse(in: CGRect(
            x: w * 0.24, y: h * 0.78,
            width: w * 0.46, height: h * 0.22
        ))

        // Ball of foot (no arch — gap between ball and heel)
        path.addEllipse(in: CGRect(
            x: w * 0.10, y: h * 0.44,
            width: w * 0.58, height: h * 0.20
        ))

        // Outer edge pad (pinky side, connects ball to heel)
        path.addEllipse(in: CGRect(
            x: w * 0.52, y: h * 0.56,
            width: w * 0.16, height: h * 0.26
        ))

        // Big toe — largest, offset inward
        path.addEllipse(in: CGRect(
            x: w * 0.10, y: h * 0.20,
            width: w * 0.22, height: h * 0.20
        ))

        // Second toe
        path.addEllipse(in: CGRect(
            x: w * 0.32, y: h * 0.12,
            width: w * 0.16, height: h * 0.16
        ))

        // Third toe
        path.addEllipse(in: CGRect(
            x: w * 0.49, y: h * 0.08,
            width: w * 0.14, height: h * 0.14
        ))

        // Fourth toe
        path.addEllipse(in: CGRect(
            x: w * 0.63, y: h * 0.12,
            width: w * 0.13, height: h * 0.12
        ))

        // Pinky toe — smallest, set back a bit
        path.addEllipse(in: CGRect(
            x: w * 0.74, y: h * 0.20,
            width: w * 0.11, height: h * 0.10
        ))

        return path
    }
}
