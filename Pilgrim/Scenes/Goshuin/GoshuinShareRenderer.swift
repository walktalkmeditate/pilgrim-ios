import UIKit

enum GoshuinShareRenderer {

    struct Input {
        let walks: [WalkInterface]
        let allWalks: [WalkInterface]
    }

    private static let canvasSize = CGSize(width: 1080, height: 1920)
    private static let borderInset: CGFloat = 40
    private static let sealSize: CGFloat = 220
    private static let columns = 3
    private static let maxSeals = 12

    static func render(input: Input) -> UIImage {
        let selected = selectSeals(from: input.walks, allWalks: input.allWalks)
        let milestoneMap = buildMilestoneMap(selected: selected, allWalks: input.allWalks)
        let stats = computeStats(walks: input.walks)

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            let inkColor = UIColor(named: "ink") ?? UIColor.darkText
            let paperColor = UIColor(named: "parchment") ?? UIColor.systemBackground

            drawBackground(ctx: cgCtx, paperColor: paperColor, walkCount: input.allWalks.count)
            drawPaperGrain(ctx: cgCtx, inkColor: inkColor)
            drawInnerBorder(ctx: cgCtx, inkColor: inkColor)
            drawHeader(stats: stats, inkColor: inkColor)
            drawSeals(ctx: cgCtx, selected: selected, milestoneMap: milestoneMap, inkColor: inkColor)
            drawFootprint(
                ctx: cgCtx,
                center: CGPoint(x: canvasSize.width / 2, y: canvasSize.height - 240),
                height: 24,
                color: inkColor.withAlphaComponent(0.15)
            )
            drawTagline(ctx: cgCtx, centerX: canvasSize.width / 2, y: canvasSize.height - 210, inkColor: inkColor)
            drawProvenance(ctx: cgCtx, inkColor: inkColor)
        }
    }

    // MARK: - Seal Selection

    private static func selectSeals(
        from walks: [WalkInterface],
        allWalks: [WalkInterface]
    ) -> [WalkInterface] {
        var result: [WalkInterface] = []
        var includedUUIDs: Set<UUID> = []

        let sortedByDate = walks.sorted { $0.startDate < $1.startDate }

        for (index, walk) in sortedByDate.enumerated() {
            guard result.count < maxSeals else { break }
            let milestones = GoshuinMilestones.detect(
                walkCount: allWalks.count,
                walkIndex: allWalks.firstIndex(where: { $0.uuid == walk.uuid })
                    .map { $0 } ?? index,
                walk: walk,
                allWalks: allWalks
            )
            guard !milestones.isEmpty, let uuid = walk.uuid else { continue }
            if includedUUIDs.insert(uuid).inserted {
                result.append(walk)
            }
        }

        let recentFirst = walks.sorted { $0.startDate > $1.startDate }
        for walk in recentFirst {
            guard result.count < maxSeals else { break }
            guard let uuid = walk.uuid else { continue }
            if includedUUIDs.insert(uuid).inserted {
                result.append(walk)
            }
        }

        return result
    }

    private static func buildMilestoneMap(
        selected: [WalkInterface],
        allWalks: [WalkInterface]
    ) -> [UUID: String] {
        var map: [UUID: String] = [:]
        for walk in selected {
            guard let uuid = walk.uuid else { continue }
            let index = allWalks.firstIndex(where: { $0.uuid == uuid }) ?? 0
            let milestones = GoshuinMilestones.detect(
                walkCount: allWalks.count,
                walkIndex: index,
                walk: walk,
                allWalks: allWalks
            )
            if let first = milestones.first {
                map[uuid] = GoshuinMilestones.label(for: first)
            }
        }
        return map
    }

    // MARK: - Stats

    private struct Stats {
        let walkCount: Int
        let distanceLabel: String
        let seasonLabel: String
    }

    private static func computeStats(walks: [WalkInterface]) -> Stats {
        let totalDistance = walks.reduce(0.0) { $0 + $1.distance }
        let isImperial = UserPreferences.distanceMeasurementType.safeValue == .miles

        let distanceValue: Double
        let unit: String
        if isImperial {
            distanceValue = totalDistance / 1000.0 * 0.621371
            unit = "mi"
        } else {
            distanceValue = totalDistance / 1000.0
            unit = "km"
        }

        let formatted: String
        if distanceValue >= 100 {
            formatted = String(format: "%.0f", distanceValue)
        } else {
            formatted = String(format: "%.1f", distanceValue)
        }

        let seasonLabel = deriveSeasonLabel(from: walks)

        return Stats(
            walkCount: walks.count,
            distanceLabel: "\(walks.count) walks \u{00B7} \(formatted) \(unit)",
            seasonLabel: seasonLabel
        )
    }

    private static func deriveSeasonLabel(from walks: [WalkInterface]) -> String {
        guard let latest = walks.max(by: { $0.startDate < $1.startDate }) else {
            return ""
        }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: latest.startDate)
        let latitude = latest.routeData.first?.latitude ?? 0
        let season = SealTimeHelpers.season(for: latest.startDate, latitude: latitude)
        return "\(season) \(year)"
    }

    // MARK: - Background

    private static func drawBackground(ctx: CGContext, paperColor: UIColor, walkCount: Int) {
        paperColor.setFill()
        ctx.fill(CGRect(origin: .zero, size: canvasSize))

        let patinaOpacity: CGFloat
        switch walkCount {
        case 0...10:  patinaOpacity = 0
        case 11...30: patinaOpacity = 0.03
        case 31...70: patinaOpacity = 0.07
        default:      patinaOpacity = 0.12
        }

        if patinaOpacity > 0, let dawn = UIColor(named: "dawn") {
            dawn.withAlphaComponent(patinaOpacity).setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))
        }
    }

    // MARK: - Paper Grain

    private static func drawPaperGrain(ctx: CGContext, inkColor: UIColor) {
        ctx.saveGState()
        var rng = SeededRNG(seed: 12345)
        ctx.setFillColor(inkColor.withAlphaComponent(0.025).cgColor)
        for _ in 0..<3000 {
            let x = CGFloat.random(in: 0...canvasSize.width, using: &rng)
            let y = CGFloat.random(in: 0...canvasSize.height, using: &rng)
            let r = CGFloat.random(in: 0.5...1.5, using: &rng)
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        ctx.restoreGState()
    }

    // MARK: - Inner Border

    private static func drawInnerBorder(ctx: CGContext, inkColor: UIColor) {
        ctx.saveGState()
        ctx.setStrokeColor(inkColor.withAlphaComponent(0.08).cgColor)
        ctx.setLineWidth(0.5)
        ctx.stroke(CGRect(
            x: borderInset,
            y: borderInset,
            width: canvasSize.width - borderInset * 2,
            height: canvasSize.height - borderInset * 2
        ))
        ctx.restoreGState()
    }

    // MARK: - Header

    private static func drawHeader(stats: Stats, inkColor: UIColor) {
        let titleFont = UIFont(name: "CormorantGaramond-Light", size: 48)
            ?? UIFont(name: "Georgia", size: 48)
            ?? UIFont.systemFont(ofSize: 48, weight: .ultraLight)
        let subtitleFont = UIFont(name: "Lato-Regular", size: 16)
            ?? UIFont(name: "Helvetica", size: 16)
            ?? UIFont.systemFont(ofSize: 16)
        let seasonFont = UIFont(name: "Lato-Regular", size: 14)
            ?? UIFont(name: "Helvetica", size: 14)
            ?? UIFont.systemFont(ofSize: 14)

        let fogColor = UIColor(named: "fog") ?? inkColor.withAlphaComponent(0.5)
        let paragraphCenter = NSMutableParagraphStyle()
        paragraphCenter.alignment = .center

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: inkColor.withAlphaComponent(0.85),
            .paragraphStyle: paragraphCenter
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: fogColor.withAlphaComponent(0.7),
            .paragraphStyle: paragraphCenter
        ]
        let seasonAttrs: [NSAttributedString.Key: Any] = [
            .font: seasonFont,
            .foregroundColor: fogColor.withAlphaComponent(0.5),
            .paragraphStyle: paragraphCenter
        ]

        let textWidth = canvasSize.width - borderInset * 2
        let titleRect = CGRect(x: borderInset, y: 100, width: textWidth, height: 60)
        ("My Goshuin" as NSString).draw(in: titleRect, withAttributes: titleAttrs)

        let subtitleRect = CGRect(x: borderInset, y: 165, width: textWidth, height: 30)
        (stats.distanceLabel as NSString).draw(in: subtitleRect, withAttributes: subtitleAttrs)

        let seasonRect = CGRect(x: borderInset, y: 200, width: textWidth, height: 25)
        (stats.seasonLabel as NSString).draw(in: seasonRect, withAttributes: seasonAttrs)
    }

    // MARK: - Seals

    private static func tintColor(for walk: WalkInterface) -> UIColor {
        let favicon = walk.favicon.flatMap { WalkFavicon(rawValue: $0) }
        switch favicon {
        case .flame: return UIColor(hex: "#A0634B")
        case .leaf:  return UIColor(hex: "#7A8B6F")
        case .star:  return UIColor(hex: "#4B5A78")
        case nil:    return UIColor(hex: "#8B7355")
        }
    }

    private static func drawSeals(
        ctx: CGContext,
        selected: [WalkInterface],
        milestoneMap: [UUID: String],
        inkColor: UIColor
    ) {
        guard !selected.isEmpty else { return }

        let cellWidth = sealSize + 30
        let cellHeight = sealSize + 40
        let gridWidth = CGFloat(columns) * cellWidth
        let gridOriginX = (canvasSize.width - gridWidth) / 2
        let gridOriginY: CGFloat = 275

        var rng = SeededRNG(seed: UInt64(selected.count))

        let dawnColor = UIColor(named: "dawn") ?? UIColor.orange
        let fogColor = UIColor(named: "fog") ?? inkColor.withAlphaComponent(0.5)
        let captionFont = UIFont(name: "Lato-Regular", size: 12)
            ?? UIFont(name: "Helvetica", size: 12)
            ?? UIFont.systemFont(ofSize: 12)

        for (index, walk) in selected.enumerated() {
            let col = index % columns
            let row = index / columns

            let baseX = gridOriginX + CGFloat(col) * cellWidth + (cellWidth - sealSize) / 2
            let baseY = gridOriginY + CGFloat(row) * cellHeight

            let offsetX = CGFloat.random(in: -8...8, using: &rng)
            let offsetY = CGFloat.random(in: -8...8, using: &rng)
            let rotation = CGFloat.random(in: -3...3, using: &rng) * .pi / 180

            let centerX = baseX + sealSize / 2 + offsetX
            let centerY = baseY + sealSize / 2 + offsetY

            let uuid = walk.uuid
            let isMilestone = uuid.flatMap { milestoneMap[$0] } != nil

            ctx.saveGState()
            ctx.translateBy(x: centerX, y: centerY)
            ctx.rotate(by: rotation)

            let tint = tintColor(for: walk)
            let tintCircleRect = CGRect(
                x: -sealSize / 2 - 4,
                y: -sealSize / 2 - 4,
                width: sealSize + 8,
                height: sealSize + 8
            )
            ctx.setFillColor(tint.withAlphaComponent(0.08).cgColor)
            ctx.fillEllipse(in: tintCircleRect)

            if isMilestone {
                let ringRect = CGRect(
                    x: -sealSize / 2 - 4,
                    y: -sealSize / 2 - 4,
                    width: sealSize + 8,
                    height: sealSize + 8
                )
                ctx.setStrokeColor(dawnColor.withAlphaComponent(0.4).cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: ringRect)
            }

            let sealRect = CGRect(
                x: -sealSize / 2,
                y: -sealSize / 2,
                width: sealSize,
                height: sealSize
            )

            let sealImage = loadSealImage(for: walk)
            sealImage.draw(in: sealRect)
            sealImage.draw(in: sealRect, blendMode: .normal, alpha: 0.3)

            ctx.restoreGState()

            if let label = uuid.flatMap({ milestoneMap[$0] }) {
                let captionAttrs: [NSAttributedString.Key: Any] = [
                    .font: captionFont,
                    .foregroundColor: fogColor.withAlphaComponent(0.6)
                ]
                let captionSize = (label as NSString).size(withAttributes: captionAttrs)
                let captionX = centerX - captionSize.width / 2
                let captionY = centerY + sealSize / 2 + 6
                (label as NSString).draw(
                    at: CGPoint(x: captionX, y: captionY),
                    withAttributes: captionAttrs
                )
            }
        }
    }

    private static func loadSealImage(for walk: WalkInterface) -> UIImage {
        if let uuid = walk.uuid?.uuidString,
           let cached = SealCache.shared.seal(for: uuid) {
            return cached
        }
        return SealGenerator.generate(for: walk, size: sealSize)
    }

    // MARK: - Colophon

    private static func drawFootprint(ctx: CGContext, center: CGPoint, height: CGFloat, color: UIColor) {
        ctx.saveGState()
        let scale = height / 32
        let shapeWidth: CGFloat = 16
        ctx.translateBy(x: center.x - (shapeWidth * scale) / 2, y: center.y - height / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: 1, y: 12, width: 14, height: 20))
        ctx.fillEllipse(in: CGRect(x: 1.5, y: 2, width: 3.5, height: 4.5))
        ctx.fillEllipse(in: CGRect(x: 5.5, y: 0, width: 3.2, height: 4))
        ctx.fillEllipse(in: CGRect(x: 9, y: 0.5, width: 3.2, height: 4))
        ctx.fillEllipse(in: CGRect(x: 12, y: 2.5, width: 3, height: 3.5))
        ctx.restoreGState()
    }

    private static func drawTagline(ctx: CGContext, centerX: CGFloat, y: CGFloat, inkColor: UIColor) {
        let font = UIFont(name: "CormorantGaramond-LightItalic", size: 24)
            ?? UIFont(name: "CormorantGaramond-Italic", size: 24)
            ?? UIFont(name: "Georgia-Italic", size: 24)
            ?? UIFont.italicSystemFont(ofSize: 24)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: inkColor.withAlphaComponent(0.25)
        ]
        let text = "Every walk is a small pilgrimage." as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: centerX - size.width / 2, y: y), withAttributes: attrs)
    }

    // MARK: - Provenance

    private static func drawProvenance(ctx: CGContext, inkColor: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Lato-Regular", size: 14)
                ?? UIFont(name: "Helvetica", size: 14)
                ?? UIFont.systemFont(ofSize: 14),
            .foregroundColor: inkColor.withAlphaComponent(0.4)
        ]

        let text = "pilgrimapp.org" as NSString
        let size = text.size(withAttributes: attrs)
        let origin = CGPoint(
            x: canvasSize.width - size.width - 60,
            y: canvasSize.height - size.height - 60
        )
        text.draw(at: origin, withAttributes: attrs)
    }
}
