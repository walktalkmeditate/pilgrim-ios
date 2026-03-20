# Etegami Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate beautiful walking postcards (etegami) on-device — sumi-e narrative route, time-of-day paper, moon phase, haiku text, seal at destination.

**Architecture:** Core Graphics renderer producing a 1080×1920 Stories image. The etegami composes: a tinted parchment background (time-of-day), a sumi-e route stroke with activity markers, a moon phase illustration, haiku-style text, the walk's seal at the route endpoint, and a provenance mark. All data comes from `WalkInterface` + `LunarPhase` + `SealGenerator`.

**Tech Stack:** Swift, Core Graphics (`UIGraphicsImageRenderer`), CoreText, CryptoKit (via SealGenerator)

**Spec:** `docs/superpowers/specs/2026-03-19-seal-etegami-goshuin-design.md` (Section 2: Etegami Generation)

**Depends on:** Seal Generation plan (complete)

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Pilgrim/Models/Etegami/EtegamiRenderer.swift` | Core Graphics composition of all etegami layers |
| `Pilgrim/Models/Etegami/EtegamiRouteStroke.swift` | Sumi-e narrative route with elevation, taper, activity markers |
| `Pilgrim/Models/Etegami/EtegamiTextGenerator.swift` | Haiku-style text from walk data |
| `Pilgrim/Models/Etegami/EtegamiMoonPhase.swift` | Moon phase illustration rendering |
| `Pilgrim/Models/Etegami/EtegamiGenerator.swift` | Public API: walk → etegami image (orchestrates above) |
| `UnitTests/EtegamiTextGeneratorTests.swift` | Haiku generation tests |
| `UnitTests/EtegamiRouteStrokeTests.swift` | Route stroke geometry tests |

---

## Task 1: Etegami Route Stroke

**Files:**
- Create: `Pilgrim/Models/Etegami/EtegamiRouteStroke.swift`
- Create: `UnitTests/EtegamiRouteStrokeTests.swift`

The sumi-e narrative stroke is the hero visual. It encodes the walk's story: elevation as ink density, taper at endpoints, meditation ripples, voice marks.

- [ ] **Step 1: Write tests**

Create `UnitTests/EtegamiRouteStrokeTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class EtegamiRouteStrokeTests: XCTestCase {

    func testProjection_fitsWithinBounds() {
        let points: [(lat: Double, lon: Double)] = [
            (35.68, 139.76), (35.69, 139.77), (35.70, 139.78)
        ]
        let bounds = CGRect(x: 100, y: 200, width: 880, height: 1000)
        let projected = EtegamiRouteStroke.projectRoute(points, into: bounds)
        for p in projected {
            XCTAssertTrue(bounds.contains(p), "Point \(p) outside bounds \(bounds)")
        }
    }

    func testProjection_emptyRoute_returnsEmpty() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let projected = EtegamiRouteStroke.projectRoute([], into: bounds)
        XCTAssertTrue(projected.isEmpty)
    }

    func testStrokeWidth_uphillIsThicker() {
        let altitudes = [100.0, 150.0, 200.0]
        let widths = EtegamiRouteStroke.computeStrokeWidths(
            altitudes: altitudes, baseWidth: 4, count: 3
        )
        // Uphill segments should be thicker than flat
        XCTAssertGreaterThan(widths[1], widths[0])
    }

    func testTaper_endsAreThin() {
        let tapers = EtegamiRouteStroke.computeTaperMultipliers(count: 100)
        XCTAssertLessThan(tapers[0], 0.5)
        XCTAssertLessThan(tapers[99], 0.5)
        XCTAssertGreaterThan(tapers[50], 0.9)
    }
}
```

- [ ] **Step 2: Run tests, verify fail**

- [ ] **Step 3: Write implementation**

Create `Pilgrim/Models/Etegami/EtegamiRouteStroke.swift`:

```swift
import UIKit

enum EtegamiRouteStroke {

    struct ActivityMarker {
        enum MarkerType { case meditation, voice }
        let type: MarkerType
        let position: CGPoint
    }

    static func projectRoute(
        _ points: [(lat: Double, lon: Double)],
        into bounds: CGRect
    ) -> [CGPoint] {
        guard points.count > 1 else { return [] }
        let lats = points.map(\.lat)
        let lons = points.map(\.lon)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let latRange = max(maxLat - minLat, 0.00001)
        let lonRange = max(maxLon - minLon, 0.00001)

        let padding: CGFloat = 40
        let innerBounds = bounds.insetBy(dx: padding, dy: padding)
        let scale = min(innerBounds.width / CGFloat(lonRange), innerBounds.height / CGFloat(latRange))

        let midLat = (minLat + maxLat) / 2
        let midLon = (minLon + maxLon) / 2
        let cx = innerBounds.midX
        let cy = innerBounds.midY

        return points.map { p in
            CGPoint(
                x: cx + CGFloat(p.lon - midLon) * scale,
                y: cy - CGFloat(p.lat - midLat) * scale
            )
        }
    }

    static func computeStrokeWidths(
        altitudes: [Double], baseWidth: CGFloat, count: Int
    ) -> [CGFloat] {
        guard altitudes.count >= 2 else {
            return [CGFloat](repeating: baseWidth, count: count)
        }
        let minAlt = altitudes.min()!
        let maxAlt = altitudes.max()!
        let range = max(maxAlt - minAlt, 1.0)

        var widths: [CGFloat] = []
        for i in 0..<min(count, altitudes.count - 1) {
            let delta = altitudes[i + 1] - altitudes[i]
            let normalized = CGFloat(abs(delta) / range)
            let multiplier: CGFloat = delta > 0 ? 1.0 + normalized * 1.5 : 1.0 - normalized * 0.4
            widths.append(baseWidth * max(multiplier, 0.5))
        }
        while widths.count < count { widths.append(baseWidth) }
        return widths
    }

    static func computeTaperMultipliers(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let taperZone = max(Int(Double(count) * 0.1), 1)
        return (0..<count).map { i in
            if i < taperZone {
                return CGFloat(i) / CGFloat(taperZone)
            } else if i >= count - taperZone {
                return CGFloat(count - 1 - i) / CGFloat(taperZone)
            }
            return 1.0
        }
    }

    static func draw(
        ctx: CGContext,
        projectedPoints: [CGPoint],
        strokeWidths: [CGFloat],
        taperMultipliers: [CGFloat],
        color: UIColor,
        opacity: CGFloat,
        activityMarkers: [ActivityMarker]
    ) {
        guard projectedPoints.count > 1 else { return }

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for i in 0..<(projectedPoints.count - 1) {
            let width = strokeWidths[min(i, strokeWidths.count - 1)]
            let taper = taperMultipliers[min(i, taperMultipliers.count - 1)]
            let segmentWidth = width * taper
            let segmentOpacity = opacity * (0.6 + taper * 0.4)

            ctx.setStrokeColor(color.withAlphaComponent(segmentOpacity).cgColor)
            ctx.setLineWidth(segmentWidth)
            ctx.move(to: projectedPoints[i])
            ctx.addLine(to: projectedPoints[i + 1])
            ctx.strokePath()
        }

        ctx.restoreGState()

        for marker in activityMarkers {
            drawActivityMarker(ctx: ctx, marker: marker, color: color)
        }
    }

    private static func drawActivityMarker(
        ctx: CGContext, marker: ActivityMarker, color: UIColor
    ) {
        ctx.saveGState()
        switch marker.type {
        case .meditation:
            for ring in 1...3 {
                let r = CGFloat(ring) * 8
                let alpha = 0.15 / CGFloat(ring)
                ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(0.8)
                ctx.strokeEllipse(in: CGRect(
                    x: marker.position.x - r, y: marker.position.y - r,
                    width: r * 2, height: r * 2
                ))
            }
        case .voice:
            ctx.setStrokeColor(color.withAlphaComponent(0.2).cgColor)
            ctx.setLineWidth(0.6)
            let waveWidth: CGFloat = 12
            for i in 0..<5 {
                let x = marker.position.x - waveWidth / 2 + CGFloat(i) * 3
                let h: CGFloat = CGFloat([2, 5, 8, 5, 2][i])
                ctx.move(to: CGPoint(x: x, y: marker.position.y - h))
                ctx.addLine(to: CGPoint(x: x, y: marker.position.y + h))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
```

- [ ] **Step 4: Run tests, verify pass**
- [ ] **Step 5: Commit**

```
feat(etegami): add sumi-e narrative route stroke with elevation, taper, activity markers
```

---

## Task 2: Haiku Text Generator

**Files:**
- Create: `Pilgrim/Models/Etegami/EtegamiTextGenerator.swift`
- Create: `UnitTests/EtegamiTextGeneratorTests.swift`

Generates three-line haiku-style text from walk data. User intention/reflection takes priority.

- [ ] **Step 1: Write tests**

```swift
import XCTest
@testable import Pilgrim

final class EtegamiTextGeneratorTests: XCTestCase {

    func testUserIntention_takesPriority() {
        let text = EtegamiTextGenerator.generate(
            intention: "finding peace in motion",
            reflection: nil,
            season: "Spring", timeOfDay: "Morning",
            durationMinutes: 45, moonPhaseName: nil,
            weatherCondition: nil, primaryActivity: .walking
        )
        XCTAssertEqual(text, "finding peace in motion")
    }

    func testUserReflection_takesPriority() {
        let text = EtegamiTextGenerator.generate(
            intention: nil,
            reflection: "The trail was quiet today",
            season: "Autumn", timeOfDay: "Evening",
            durationMinutes: 30, moonPhaseName: nil,
            weatherCondition: nil, primaryActivity: .walking
        )
        XCTAssertEqual(text, "The trail was quiet today")
    }

    func testAutoGenerated_containsThreeLines() {
        let text = EtegamiTextGenerator.generate(
            intention: nil, reflection: nil,
            season: "Winter", timeOfDay: "Morning",
            durationMinutes: 45, moonPhaseName: "Waning Crescent",
            weatherCondition: "rain", primaryActivity: .meditation
        )
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
    }

    func testAutoGenerated_includesSeason() {
        let text = EtegamiTextGenerator.generate(
            intention: nil, reflection: nil,
            season: "Spring", timeOfDay: "Morning",
            durationMinutes: 30, moonPhaseName: nil,
            weatherCondition: nil, primaryActivity: .walking
        )
        XCTAssertTrue(text.lowercased().contains("spring"))
    }
}
```

- [ ] **Step 2: Write implementation**

```swift
import Foundation

enum EtegamiTextGenerator {

    enum PrimaryActivity { case walking, meditation, voice }

    static func generate(
        intention: String?,
        reflection: String?,
        season: String,
        timeOfDay: String,
        durationMinutes: Int,
        moonPhaseName: String?,
        weatherCondition: String?,
        primaryActivity: PrimaryActivity
    ) -> String {
        if let intention = intention, !intention.isEmpty { return intention }
        if let reflection = reflection, !reflection.isEmpty { return reflection }
        return generateHaiku(
            season: season, timeOfDay: timeOfDay,
            durationMinutes: durationMinutes,
            moonPhaseName: moonPhaseName,
            weatherCondition: weatherCondition,
            primaryActivity: primaryActivity
        )
    }

    private static func generateHaiku(
        season: String, timeOfDay: String,
        durationMinutes: Int, moonPhaseName: String?,
        weatherCondition: String?, primaryActivity: PrimaryActivity
    ) -> String {
        let line1 = "\(season.lowercased()) \(timeOfDay.lowercased()) walk"

        let durationText: String
        if durationMinutes < 60 {
            durationText = "\(durationMinutes) minutes"
        } else {
            let hours = durationMinutes / 60
            let mins = durationMinutes % 60
            durationText = mins > 0 ? "\(hours) hours \(mins) minutes" : "\(hours) hours"
        }

        let activityText: String
        switch primaryActivity {
        case .walking:   activityText = "in silence"
        case .meditation: activityText = "in stillness"
        case .voice:     activityText = "in reflection"
        }
        let line2 = "\(durationText) \(activityText)"

        let line3: String
        if let moon = moonPhaseName {
            line3 = "under \(moon.lowercased())"
        } else if let weather = weatherCondition?.lowercased(), weather != "clear" {
            line3 = "through the \(weather)"
        } else {
            line3 = "along the trail"
        }

        return "\(line1)\n\(line2)\n\(line3)"
    }
}
```

- [ ] **Step 3: Run tests, verify pass**
- [ ] **Step 4: Commit**

```
feat(etegami): add haiku-style text generator from walk data
```

---

## Task 3: Moon Phase Illustration

**Files:**
- Create: `Pilgrim/Models/Etegami/EtegamiMoonPhase.swift`

A small Core Graphics illustration of the lunar phase.

- [ ] **Step 1: Write implementation**

```swift
import UIKit

enum EtegamiMoonPhase {

    static func draw(
        ctx: CGContext,
        phase: LunarPhase,
        center: CGPoint,
        radius: CGFloat,
        color: UIColor
    ) {
        let illumination = phase.illumination
        let age = phase.age

        ctx.saveGState()

        // Outer circle (moon outline)
        ctx.setStrokeColor(color.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokeEllipse(in: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))

        // Illuminated portion
        let isWaxing = age < 14.765
        ctx.setFillColor(color.withAlphaComponent(0.12).cgColor)

        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: !isWaxing)

        let curveRadius = radius * CGFloat(abs(2 * illumination - 1))
        let controlSign: CGFloat = illumination > 0.5 ? 1 : -1
        let adjustedSign = isWaxing ? controlSign : -controlSign

        path.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: isWaxing)
        // Close with an elliptical curve to show the terminator
        ctx.addPath(path)
        ctx.fillPath()

        ctx.restoreGState()
    }
}
```

Note: The moon phase rendering doesn't need to be astronomically precise — it's a decorative illustration. The key visual elements are: circle outline (always), filled crescent/gibbous showing illumination. `LunarPhase` is already available via `LunarPhase.current(date:)`.

- [ ] **Step 2: Build to verify**
- [ ] **Step 3: Commit**

```
feat(etegami): add moon phase illustration renderer
```

---

## Task 4: Etegami Renderer

**Files:**
- Create: `Pilgrim/Models/Etegami/EtegamiRenderer.swift`

Composes all layers into a single 1080×1920 image.

- [ ] **Step 1: Write implementation**

```swift
import UIKit
import CoreText

enum EtegamiRenderer {

    struct Input {
        let routePoints: [(lat: Double, lon: Double)]
        let altitudes: [Double]
        let activityMarkers: [EtegamiRouteStroke.ActivityMarker]
        let sealImage: UIImage
        let sealPosition: CGPoint
        let haikuText: String
        let moonPhase: LunarPhase?
        let timeOfDay: String
        let inkColor: UIColor
        let paperColor: UIColor
    }

    static let width: CGFloat = 1080
    static let height: CGFloat = 1920

    static func render(input: Input) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // 1. Paper background
            input.paperColor.setFill()
            cgCtx.fill(CGRect(origin: .zero, size: size))

            // 2. Moon phase (upper right)
            if let moon = input.moonPhase {
                let moonCenter = CGPoint(x: width - 120, y: 200)
                EtegamiMoonPhase.draw(
                    ctx: cgCtx, phase: moon,
                    center: moonCenter, radius: 30,
                    color: input.inkColor
                )
            }

            // 3. Sumi-e route
            let routeBounds = CGRect(x: 80, y: 300, width: width - 160, height: 900)
            let projected = EtegamiRouteStroke.projectRoute(
                input.routePoints, into: routeBounds
            )
            if projected.count > 1 {
                let strokeWidths = EtegamiRouteStroke.computeStrokeWidths(
                    altitudes: input.altitudes, baseWidth: 4, count: projected.count - 1
                )
                let tapers = EtegamiRouteStroke.computeTaperMultipliers(count: projected.count - 1)

                EtegamiRouteStroke.draw(
                    ctx: cgCtx,
                    projectedPoints: projected,
                    strokeWidths: strokeWidths,
                    taperMultipliers: tapers,
                    color: input.inkColor,
                    opacity: 0.8,
                    activityMarkers: input.activityMarkers
                )
            }

            // 4. Seal at route endpoint
            let sealSize: CGFloat = 80
            let sealRect = CGRect(
                x: input.sealPosition.x - sealSize / 2,
                y: input.sealPosition.y - sealSize / 2,
                width: sealSize, height: sealSize
            )
            input.sealImage.draw(in: sealRect)

            // 5. Haiku text
            let textY: CGFloat = 1350
            drawHaikuText(
                ctx: cgCtx, text: input.haikuText,
                origin: CGPoint(x: 100, y: textY),
                maxWidth: width - 200,
                color: input.inkColor
            )

            // 6. Provenance
            drawProvenance(ctx: cgCtx, size: size, color: input.inkColor)
        }
    }

    private static func drawHaikuText(
        ctx: CGContext, text: String, origin: CGPoint,
        maxWidth: CGFloat, color: UIColor
    ) {
        let font = UIFont(name: "CormorantGaramond-Light", size: 36) ?? UIFont.systemFont(ofSize: 36, weight: .light)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 12
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.withAlphaComponent(0.6),
            .paragraphStyle: style
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textRect = CGRect(x: origin.x, y: origin.y, width: maxWidth, height: 300)
        attrStr.draw(in: textRect)
    }

    private static func drawProvenance(
        ctx: CGContext, size: CGSize, color: UIColor
    ) {
        let font = UIFont(name: "Lato-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.withAlphaComponent(0.25),
            .kern: 2.0
        ]
        let text = NSAttributedString(string: "pilgrimapp.org", attributes: attrs)
        let textSize = text.size()
        text.draw(at: CGPoint(
            x: size.width - textSize.width - 60,
            y: size.height - textSize.height - 60
        ))
    }
}
```

- [ ] **Step 2: Add smoke test**

Add to `UnitTests/EtegamiRouteStrokeTests.swift`:

```swift
func testRenderer_producesCorrectSizeImage() {
    let input = EtegamiRenderer.Input(
        routePoints: [(35.68, 139.76), (35.69, 139.77), (35.70, 139.78)],
        altitudes: [100, 120, 140],
        activityMarkers: [],
        sealImage: UIImage(),
        sealPosition: CGPoint(x: 500, y: 800),
        haikuText: "spring morning walk\nforty minutes in silence\nalong the trail",
        moonPhase: nil,
        timeOfDay: "Morning",
        inkColor: .brown,
        paperColor: UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1)
    )
    let image = EtegamiRenderer.render(input: input)
    XCTAssertEqual(image.size.width, 1080)
    XCTAssertEqual(image.size.height, 1920)
}
```

- [ ] **Step 3: Run tests, verify pass**
- [ ] **Step 4: Commit**

```
feat(etegami): add EtegamiRenderer composing route, moon, haiku, seal, provenance
```

---

## Task 5: Etegami Generator (Public API)

**Files:**
- Create: `Pilgrim/Models/Etegami/EtegamiGenerator.swift`

Orchestrates: walk → data extraction → time-of-day paper → route projection → activity markers → haiku → moon → seal → render.

- [ ] **Step 1: Write implementation**

```swift
import UIKit

enum EtegamiGenerator {

    static func generate(for walk: WalkInterface) -> UIImage {
        let date = walk.startDate
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let latitude = walk.routeData.first?.latitude ?? 0

        let timeOfDay = SealTimeHelpers.timeOfDay(for: hour)
        let season = SealTimeHelpers.season(for: date, latitude: latitude)

        let paperColor = paperColor(for: hour)
        let inkColor = inkColor(for: hour)

        let routePoints: [(lat: Double, lon: Double)] = walk.routeData.map {
            (lat: $0.latitude, lon: $0.longitude)
        }
        let altitudes = walk.routeData.map(\.altitude)

        let activityMarkers = buildActivityMarkers(walk: walk, routePoints: routePoints)

        let sealImage = SealGenerator.generate(for: walk, size: 160)

        let sealPosition: CGPoint
        if let lastRoute = routePoints.last {
            let projected = EtegamiRouteStroke.projectRoute(
                routePoints, into: CGRect(x: 80, y: 300, width: 920, height: 900)
            )
            sealPosition = projected.last ?? CGPoint(x: 900, y: 1100)
        } else {
            sealPosition = CGPoint(x: 900, y: 1100)
        }

        let primaryActivity: EtegamiTextGenerator.PrimaryActivity
        if walk.meditateDuration > walk.talkDuration && walk.meditateDuration > walk.activeDuration * 0.3 {
            primaryActivity = .meditation
        } else if walk.talkDuration > walk.meditateDuration && walk.talkDuration > walk.activeDuration * 0.3 {
            primaryActivity = .voice
        } else {
            primaryActivity = .walking
        }

        let moonPhase: LunarPhase? = UserPreferences.celestialAwarenessEnabled.value
            ? LunarPhase.current(date: date) : nil

        let haikuText = EtegamiTextGenerator.generate(
            intention: walk.intention,
            reflection: walk.comments,
            season: season,
            timeOfDay: timeOfDay,
            durationMinutes: Int(walk.activeDuration / 60),
            moonPhaseName: moonPhase?.name,
            weatherCondition: walk.weatherCondition,
            primaryActivity: primaryActivity
        )

        let input = EtegamiRenderer.Input(
            routePoints: routePoints,
            altitudes: altitudes,
            activityMarkers: activityMarkers,
            sealImage: sealImage,
            sealPosition: sealPosition,
            haikuText: haikuText,
            moonPhase: moonPhase,
            timeOfDay: timeOfDay,
            inkColor: inkColor,
            paperColor: paperColor
        )

        return EtegamiRenderer.render(input: input)
    }

    // MARK: - Time-of-Day Paper Colors

    private static func paperColor(for hour: Int) -> UIColor {
        switch hour {
        case 5...7:   return UIColor(hex: "#F5E6C8")  // warm amber
        case 8...10:  return UIColor(hex: "#F5F0E8")  // light parchment
        case 11...13: return UIColor(hex: "#FAF8F3")  // sun-bleached
        case 14...16: return UIColor(hex: "#F0E4C8")  // golden
        case 17...19: return UIColor(hex: "#E8D0C0")  // deep rose
        default:      return UIColor(hex: "#1A1E2E")  // indigo night
        }
    }

    private static func inkColor(for hour: Int) -> UIColor {
        switch hour {
        case 20...23, 0...4: return UIColor(hex: "#D0C8B8")  // silver for night
        default:             return UIColor(hex: "#2C241E")  // ink for day
        }
    }

    private static func buildActivityMarkers(
        walk: WalkInterface,
        routePoints: [(lat: Double, lon: Double)]
    ) -> [EtegamiRouteStroke.ActivityMarker] {
        guard routePoints.count > 1 else { return [] }
        let projected = EtegamiRouteStroke.projectRoute(
            routePoints, into: CGRect(x: 80, y: 300, width: 920, height: 900)
        )

        var markers: [EtegamiRouteStroke.ActivityMarker] = []
        let walkStart = walk.startDate.timeIntervalSince1970
        let routeTimestamps = walk.routeData.map { $0.timestamp.timeIntervalSince1970 }

        for interval in walk.activityIntervals {
            let midTime = interval.startDate.timeIntervalSince1970 +
                          interval.duration / 2
            if let idx = closestRouteIndex(timestamp: midTime, routeTimestamps: routeTimestamps),
               idx < projected.count {
                markers.append(.init(type: .meditation, position: projected[idx]))
            }
        }

        for recording in walk.voiceRecordings {
            let midTime = recording.startDate.timeIntervalSince1970 +
                          recording.duration / 2
            if let idx = closestRouteIndex(timestamp: midTime, routeTimestamps: routeTimestamps),
               idx < projected.count {
                markers.append(.init(type: .voice, position: projected[idx]))
            }
        }

        return markers
    }

    private static func closestRouteIndex(
        timestamp: TimeInterval, routeTimestamps: [TimeInterval]
    ) -> Int? {
        guard !routeTimestamps.isEmpty else { return nil }
        var closest = 0
        var minDiff = abs(routeTimestamps[0] - timestamp)
        for (i, ts) in routeTimestamps.enumerated() {
            let diff = abs(ts - timestamp)
            if diff < minDiff {
                minDiff = diff
                closest = i
            }
        }
        return closest
    }
}
```

**IMPORTANT:** Before writing this file, read the actual `WalkInterface` to verify:
- `walk.intention` exists (may be named differently)
- `walk.comments` exists for reflection text
- `UserPreferences.celestialAwarenessEnabled` exists and how to access it
- `LunarPhase.current(date:)` is the correct API
- `RouteDataSampleInterface` has `.timestamp` as a `Date`

- [ ] **Step 2: Build and run all tests**
- [ ] **Step 3: Commit**

```
feat(etegami): add EtegamiGenerator public API with time-of-day paper and activity markers
```

---

## Completion Checklist

- [ ] Sumi-e route stroke with elevation-based thickness and taper
- [ ] Meditation ripple markers at GPS coordinates
- [ ] Voice waveform markers at GPS coordinates
- [ ] Time-of-day paper colors (6 palettes: dawn through night)
- [ ] Night walks render with silver ink on indigo paper
- [ ] Moon phase illustration when celestial awareness enabled
- [ ] Haiku-style text: user intention > reflection > auto-generated
- [ ] Auto-generated haiku includes season, duration, activity, moon/weather
- [ ] Seal placed at route endpoint
- [ ] Provenance mark "pilgrimapp.org" at bottom
- [ ] Output size: 1080×1920
- [ ] All unit tests pass
- [ ] Build succeeds
