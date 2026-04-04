import UIKit
import CryptoKit

enum CairnVisualGenerator {

    static func generate(latitude: Double, longitude: Double, stoneCount: Int, size: CGFloat = 256) -> UIImage {
        let hash = hashBytes(latitude: latitude, longitude: longitude)
        let tier = CairnTier.from(stoneCount: stoneCount)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let context = ctx.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)

            let palette = colorPalette(from: hash)

            let visibleStones = min(stoneCount, 12)
            for i in 0..<visibleStones {
                let byteOffset = (i * 3) % hash.count
                let xOffset = CGFloat(hash[byteOffset]) / 255.0 * size * 0.4 - size * 0.2
                let yOffset = CGFloat(hash[(byteOffset + 1) % hash.count]) / 255.0 * size * 0.3 - size * 0.15
                let radius = size * (0.06 + CGFloat(hash[(byteOffset + 2) % hash.count]) / 255.0 * 0.08)

                let stoneCenter = CGPoint(
                    x: center.x + xOffset,
                    y: center.y + yOffset + CGFloat(i) * -size * 0.02
                )

                let colorIndex = i % palette.count
                context.setFillColor(palette[colorIndex].cgColor)

                let rect = CGRect(
                    x: stoneCenter.x - radius,
                    y: stoneCenter.y - radius * 0.8,
                    width: radius * 2,
                    height: radius * 1.6
                )
                context.fillEllipse(in: rect)

                context.setStrokeColor(UIColor.ink.withAlphaComponent(0.15).cgColor)
                context.setLineWidth(0.5)
                context.strokeEllipse(in: rect)
            }

            if tier.glows {
                let glowRadius = size * 0.4
                let colors = [
                    UIColor.stone.withAlphaComponent(0.2).cgColor,
                    UIColor.stone.withAlphaComponent(0.0).cgColor,
                ]
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: colors as CFArray, locations: [0, 1]) {
                    context.drawRadialGradient(
                        gradient,
                        startCenter: center, startRadius: 0,
                        endCenter: center, endRadius: glowRadius,
                        options: []
                    )
                }
            }
        }
    }

    static func hashForCoordinate(latitude: Double, longitude: Double) -> String {
        let input = String(format: "%.6f|%.6f", latitude, longitude)
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func hashBytes(latitude: Double, longitude: Double) -> [UInt8] {
        let input = String(format: "%.6f|%.6f", latitude, longitude)
        let digest = SHA256.hash(data: Data(input.utf8))
        return Array(digest)
    }

    private static func colorPalette(from hash: [UInt8]) -> [UIColor] {
        let baseHue = CGFloat(hash[0]) / 255.0 * 0.12 + 0.06
        let baseSat = CGFloat(hash[1]) / 255.0 * 0.15 + 0.1

        return (0..<5).map { i in
            let hueShift = CGFloat(hash[2 + i]) / 255.0 * 0.04 - 0.02
            let brightness = 0.35 + CGFloat(hash[7 + i]) / 255.0 * 0.25
            return UIColor(
                hue: baseHue + hueShift,
                saturation: baseSat,
                brightness: brightness,
                alpha: 1.0
            )
        }
    }
}
