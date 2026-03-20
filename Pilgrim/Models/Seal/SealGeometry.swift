import Foundation

struct SealGeometry {

    struct Ring {
        let radius: CGFloat
        let strokeWidth: CGFloat
        let opacity: CGFloat
        let dashLength: CGFloat?
        let gapLength: CGFloat?
    }

    struct RadialLine {
        let innerPoint: CGPoint
        let outerPoint: CGPoint
        let strokeWidth: CGFloat
        let opacity: CGFloat
    }

    struct ArcSegment {
        let startPoint: CGPoint
        let endPoint: CGPoint
        let radius: CGFloat
        let largeArc: Bool
    }

    struct Dot {
        let center: CGPoint
        let radius: CGFloat
    }

    let rings: [Ring]
    let radialLines: [RadialLine]
    let arcSegments: [ArcSegment]
    let dots: [Dot]
    let rotation: CGFloat
    let center: CGPoint
    let outerRadius: CGFloat

    init(bytes: [UInt8], size: CGFloat, meditateRatio: Double, talkRatio: Double) {
        let cx = size / 2
        let cy = size / 2
        let outerR = size * 0.44

        self.center = CGPoint(x: cx, y: cy)
        self.outerRadius = outerR
        self.rotation = (CGFloat(bytes[0]) / 255.0) * 360.0

        let baseRingCount = 3 + Int(bytes[1]) % 3
        let extraRipples = meditateRatio > 0.2 ? Int(meditateRatio * 6) : 0
        let ringCount = min(baseRingCount + extraRipples, 8)

        var computedRings: [Ring] = []
        for i in 0..<ringCount {
            let radiusOffset = CGFloat(bytes[2 + (i % 6)]) / 255.0 * 0.08
            let r = outerR - CGFloat(i) * (size * (0.04 + radiusOffset * 0.02))
            guard r >= size * 0.15 else { break }

            let dashByte = bytes[6 + (i % 6)]
            let dashLen: CGFloat? = i == 0 ? nil : CGFloat(2 + Int(dashByte) % 8)
            let gapLen: CGFloat? = i == 0 ? nil : CGFloat(1 + Int(dashByte >> 4) % 6)
            let strokeW: CGFloat = i == 0 ? 1.5 : 0.8 + CGFloat(Int(bytes[i]) % 3) * 0.3
            let opacity: CGFloat = 0.7 - CGFloat(i) * 0.06

            computedRings.append(Ring(radius: r, strokeWidth: strokeW, opacity: opacity, dashLength: dashLen, gapLength: gapLen))
        }
        self.rings = computedRings

        let baseLineCount = 4 + Int(bytes[8]) % 5
        let extraLines = talkRatio > 0.1 ? Int(talkRatio * 8) : 0
        let lineCount = min(baseLineCount + extraLines, 12)

        var computedLines: [RadialLine] = []
        for i in 0..<lineCount {
            let angle = (CGFloat(bytes[8 + (i % 8)]) / 255.0 * 360.0 + CGFloat(i) * (360.0 / CGFloat(lineCount))).truncatingRemainder(dividingBy: 360)
            let rad = angle * .pi / 180.0

            let innerExtent = 0.25 + CGFloat(bytes[16 + (i % 4)]) / 255.0 * 0.15
            let outerExtent = 0.85 + CGFloat(bytes[20 + (i % 4)]) / 255.0 * 0.15

            let x1 = cx + cos(rad) * outerR * innerExtent
            let y1 = cy + sin(rad) * outerR * innerExtent
            let x2 = cx + cos(rad) * outerR * outerExtent
            let y2 = cy + sin(rad) * outerR * outerExtent

            let strokeW: CGFloat = 0.5 + CGFloat(Int(bytes[i % 32]) % 3) * 0.3
            let opacity: CGFloat = 0.3 + CGFloat(bytes[(i + 12) % 32]) / 255.0 * 0.3

            computedLines.append(RadialLine(
                innerPoint: CGPoint(x: x1, y: y1),
                outerPoint: CGPoint(x: x2, y: y2),
                strokeWidth: strokeW,
                opacity: opacity
            ))
        }
        self.radialLines = computedLines

        let arcCount = 2 + Int(bytes[24]) % 3
        var computedArcs: [ArcSegment] = []
        for i in 0..<arcCount {
            let startAngle = CGFloat(bytes[24 + i]) / 255.0 * 360.0
            let sweep = 20.0 + CGFloat(bytes[26 + (i % 2)]) / 255.0 * 60.0
            let r = outerR * (0.55 + CGFloat(bytes[28 + (i % 2)]) / 255.0 * 0.25)

            let startRad = startAngle * .pi / 180.0
            let endRad = (startAngle + sweep) * .pi / 180.0

            computedArcs.append(ArcSegment(
                startPoint: CGPoint(x: cx + cos(startRad) * r, y: cy + sin(startRad) * r),
                endPoint: CGPoint(x: cx + cos(endRad) * r, y: cy + sin(endRad) * r),
                radius: r,
                largeArc: sweep > 180
            ))
        }
        self.arcSegments = computedArcs

        let dotCount = 3 + Int(bytes[28]) % 5
        var computedDots: [Dot] = []
        for i in 0..<dotCount {
            let angle = CGFloat(bytes[28 + (i % 4)]) / 255.0 * 360.0 + CGFloat(i) * 47.0
            let rad = angle * .pi / 180.0
            let dist = outerR * (0.3 + CGFloat(bytes[29 + (i % 3)]) / 255.0 * 0.5)

            let x = cx + cos(rad) * dist
            let y = cy + sin(rad) * dist
            let dotR: CGFloat = CGFloat(1 + Int(bytes[i % 32]) % 2)

            computedDots.append(Dot(center: CGPoint(x: x, y: y), radius: dotR))
        }
        self.dots = computedDots
    }
}
