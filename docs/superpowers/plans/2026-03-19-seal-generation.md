# Seal Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate deterministic visual seals on-device from walk data, matching the existing web seal algorithm, with mark-influenced colors, ghost route, elevation ring, and weather texture.

**Architecture:** Port the TypeScript `generatePassportStamp()` from `pilgrim-worker` to Swift using Core Graphics. The seal is a 512×512 image rendered from a SHA-256 hash of walk data. Each hash byte deterministically controls geometry (rings, lines, arcs, dots) and appearance (color, rotation, texture). The walk's mark (favicon) selects from a 15-color palette. Rendered seals are cached on disk keyed by walk UUID.

**Tech Stack:** Swift, CryptoKit (SHA-256), Core Graphics (`UIGraphicsImageRenderer`, `CGContext`, `CTLine`), Cache (CocoaPod), XCTest

**Spec:** `docs/superpowers/specs/2026-03-19-seal-etegami-goshuin-design.md`

---

## File Structure

### New Files (iOS)
| File | Responsibility |
|------|---------------|
| `Pilgrim/Models/Seal/SealHashComputer.swift` | SHA-256 hash from walk data (must match worker) |
| `Pilgrim/Models/Seal/SealColorPalette.swift` | 15-color mark-influenced palette |
| `Pilgrim/Models/Seal/SealGeometry.swift` | Deterministic geometry structs from hash bytes |
| `Pilgrim/Models/Seal/SealRenderer.swift` | Core Graphics rendering to UIImage |
| `Pilgrim/Models/Seal/SealCache.swift` | File-backed image cache using Cache pod |
| `Pilgrim/Models/Seal/SealGenerator.swift` | Public API: walk → seal image (orchestrates above) |
| `UnitTests/SealHashComputerTests.swift` | Hash computation parity tests |
| `UnitTests/SealColorPaletteTests.swift` | Color selection tests |
| `UnitTests/SealGeometryTests.swift` | Geometry computation tests |

### Modified Files (iOS)
| File | Change |
|------|--------|
| `Pilgrim/Models/Share/SharePayload.swift` | Add `mark` field |
| `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift` | Send mark in payload, always send full stats for hashing |

### Modified Files (Worker — separate repo at `../pilgrim-worker`)
| File | Change |
|------|--------|
| `src/types.ts` | Add `mark` to SharePayload |
| `src/generators/passport-stamp.ts` | 15-color palette, elevation ring, weather texture, hash fix |
| `src/generators/html-template.ts` | New CSS variables for 15 colors |

**Note:** The worker is a separate git repository at `/Users/rubberduck/GitHub/momentmaker/pilgrim-worker/`. Task 7 operates in that repo and commits there.

---

## Task 1: Seal Hash Computer

**Files:**
- Create: `Pilgrim/Models/Seal/SealHashComputer.swift`
- Create: `UnitTests/SealHashComputerTests.swift`

The hash must be byte-identical to the worker's `computeWalkHash()`. This is the foundation — if the hash doesn't match, seals diverge.

- [ ] **Step 1: Write the failing test**

Create `UnitTests/SealHashComputerTests.swift`:

```swift
import XCTest
import CryptoKit
@testable import Pilgrim

final class SealHashComputerTests: XCTestCase {

    func testEmptyRoute_producesConsistentHash() {
        let hash = SealHashComputer.computeHash(
            routePoints: [],
            distance: 0,
            activeDuration: 0,
            meditateDuration: 0,
            talkDuration: 0,
            startDate: "2026-03-19T10:00:00Z"
        )
        XCTAssertEqual(hash.count, 64)
        // Run same input twice → same output
        let hash2 = SealHashComputer.computeHash(
            routePoints: [],
            distance: 0,
            activeDuration: 0,
            meditateDuration: 0,
            talkDuration: 0,
            startDate: "2026-03-19T10:00:00Z"
        )
        XCTAssertEqual(hash, hash2)
    }

    func testKnownInput_matchesWorkerOutput() {
        // Pre-computed from the TypeScript worker:
        // parts = ["35.68100,139.76700", "5000", "3600", "600", "300", "2026-03-19T10:00:00Z"]
        // SHA-256 of "35.68100,139.76700|5000|3600|600|300|2026-03-19T10:00:00Z"
        let hash = SealHashComputer.computeHash(
            routePoints: [(lat: 35.681, lon: 139.767)],
            distance: 5000,
            activeDuration: 3600,
            meditateDuration: 600,
            talkDuration: 300,
            startDate: "2026-03-19T10:00:00Z"
        )
        // This value must be verified by running the TypeScript worker with the same input
        // For now, assert it's a valid hex string
        XCTAssertTrue(hash.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertEqual(hash.count, 64)
    }

    func testHexToBytes_roundtrip() {
        let hex = "ab01ff"
        let bytes = SealHashComputer.hexToBytes(hex)
        XCTAssertEqual(bytes, [0xAB, 0x01, 0xFF])
    }

    func testRouteFormatting_fiveDecimalPlaces() {
        // 35.681 should format as "35.68100" and 139.767 as "139.76700"
        let hash1 = SealHashComputer.computeHash(
            routePoints: [(lat: 35.681, lon: 139.767)],
            distance: 0, activeDuration: 0, meditateDuration: 0, talkDuration: 0,
            startDate: "2026-01-01T00:00:00Z"
        )
        let hash2 = SealHashComputer.computeHash(
            routePoints: [(lat: 35.68100, lon: 139.76700)],
            distance: 0, activeDuration: 0, meditateDuration: 0, talkDuration: 0,
            startDate: "2026-01-01T00:00:00Z"
        )
        XCTAssertEqual(hash1, hash2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/SealHashComputerTests 2>&1 | tail -20`
Expected: FAIL — `SealHashComputer` not defined

- [ ] **Step 3: Write implementation**

Create `Pilgrim/Models/Seal/SealHashComputer.swift`:

```swift
import CryptoKit
import Foundation

enum SealHashComputer {

    typealias RoutePoint = (lat: Double, lon: Double)

    static func computeHash(
        routePoints: [RoutePoint],
        distance: Double,
        activeDuration: Double,
        meditateDuration: Double,
        talkDuration: Double,
        startDate: String
    ) -> String {
        var parts: [String] = []

        for p in routePoints {
            parts.append(String(format: "%.5f,%.5f", p.lat, p.lon))
        }

        parts.append(Self.formatNumber(distance))
        parts.append(Self.formatNumber(activeDuration))
        parts.append(Self.formatNumber(meditateDuration))
        parts.append(Self.formatNumber(talkDuration))
        parts.append(startDate)

        let joined = parts.joined(separator: "|")
        let data = Data(joined.utf8)
        let digest = SHA256.hash(data: data)

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Formats a Double to match JavaScript's String(number) output.
    /// JS: String(5000) → "5000", String(3600.5) → "3600.5"
    /// Swift: String(5000.0) → "5000.0" (wrong!)
    /// This strips trailing ".0" for integer values to match JS behavior.
    static func formatNumber(_ value: Double) -> String {
        if value == value.rounded(.towardZero) && !value.isNaN && !value.isInfinite {
            return String(Int(value))
        }
        return String(value)
    }

    static func hexToBytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                bytes.append(byte)
            }
            index = nextIndex
        }
        return bytes
    }

    static func computeHashFromWalk(_ walk: WalkInterface) -> String {
        let routePoints: [RoutePoint] = walk.routeData.map {
            (lat: $0.latitude, lon: $0.longitude)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startDate = formatter.string(from: walk.startDate)

        return computeHash(
            routePoints: routePoints,
            distance: walk.distance,
            activeDuration: walk.activeDuration,
            meditateDuration: walk.meditateDuration,
            talkDuration: walk.talkDuration,
            startDate: startDate
        )
    }
}
```

**CRITICAL**: The `String(distance)` formatting must match JavaScript's `String(5000)` → `"5000"`. For doubles, JavaScript's `String(3600.0)` → `"3600"` but Swift's `String(3600.0)` → `"3600.0"`. Verify parity by running both and comparing. If they diverge, use a custom formatter that matches JS output (strip trailing `.0`).

- [ ] **Step 4: Verify JS/Swift String parity for numeric values**

Run a quick Node.js check and compare with Swift:
```bash
node -e "console.log(String(5000), String(3600.0), String(0))"
```
If JS outputs `"5000" "3600" "0"` but Swift would output `"5000.0" "3600.0" "0.0"`, fix the formatter to strip trailing `.0` from integers.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/SealHashComputerTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 6: Cross-verify hash with TypeScript worker**

Create a temporary Node.js script that computes the hash for the same test input and compare output:
```bash
cd pilgrim-worker && node -e "
const crypto = require('crypto');
const parts = ['35.68100,139.76700', '5000', '3600', '600', '300', '2026-03-19T10:00:00Z'];
const data = Buffer.from(parts.join('|'), 'utf-8');
console.log(crypto.createHash('sha256').update(data).digest('hex'));
"
```
Update `testKnownInput_matchesWorkerOutput` with the exact expected hash value.

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/Seal/SealHashComputer.swift UnitTests/SealHashComputerTests.swift
git commit -m "feat(seal): add SealHashComputer with SHA-256 parity to worker"
```

---

## Task 2: Seal Color Palette

**Files:**
- Create: `Pilgrim/Models/Seal/SealColorPalette.swift`
- Create: `UnitTests/SealColorPaletteTests.swift`

- [ ] **Step 1: Write the failing test**

Create `UnitTests/SealColorPaletteTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class SealColorPaletteTests: XCTestCase {

    func testUnmarked_selectsFromThreeColors() {
        for byte in UInt8(0)...UInt8(2) {
            let color = SealColorPalette.color(for: nil, hashByte: byte)
            XCTAssertTrue(SealColorPalette.neutralColors.contains(color))
        }
    }

    func testUnmarked_wrapsAtThree() {
        let color0 = SealColorPalette.color(for: nil, hashByte: 0)
        let color3 = SealColorPalette.color(for: nil, hashByte: 3)
        XCTAssertEqual(color0, color3)
    }

    func testFlame_selectsFromWarmPalette() {
        for byte in UInt8(0)...UInt8(3) {
            let color = SealColorPalette.color(for: .flame, hashByte: byte)
            XCTAssertTrue(SealColorPalette.warmColors.contains(color))
        }
    }

    func testLeaf_selectsFromCoolPalette() {
        let color = SealColorPalette.color(for: .leaf, hashByte: 0)
        XCTAssertTrue(SealColorPalette.coolColors.contains(color))
    }

    func testStar_selectsFromAccentPalette() {
        let color = SealColorPalette.color(for: .star, hashByte: 0)
        XCTAssertTrue(SealColorPalette.accentColors.contains(color))
    }

    func testAllFifteenColors_areUnique() {
        let all = SealColorPalette.warmColors + SealColorPalette.coolColors +
                  SealColorPalette.accentColors + SealColorPalette.neutralColors
        XCTAssertEqual(all.count, 15)
        XCTAssertEqual(Set(all).count, 15)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/SealColorPaletteTests 2>&1 | tail -20`
Expected: FAIL

- [ ] **Step 3: Write implementation**

Create `Pilgrim/Models/Seal/SealColorPalette.swift`:

```swift
import UIKit

enum SealColorPalette {

    struct SealColor: Hashable {
        let light: UIColor
        let dark: UIColor
        let cssVar: String
    }

    // Warm (Transformative / flame)
    static let rust      = SealColor(light: UIColor(hex: "#A0634B"), dark: UIColor(hex: "#C47E63"), cssVar: "--seal-rust")
    static let ember     = SealColor(light: UIColor(hex: "#B5553A"), dark: UIColor(hex: "#D4735A"), cssVar: "--seal-ember")
    static let sienna    = SealColor(light: UIColor(hex: "#946B4E"), dark: UIColor(hex: "#B88A6A"), cssVar: "--seal-sienna")
    static let copper    = SealColor(light: UIColor(hex: "#B87333"), dark: UIColor(hex: "#D4955E"), cssVar: "--seal-copper")

    // Cool (Peaceful / leaf)
    static let moss      = SealColor(light: UIColor(hex: "#7A8B6F"), dark: UIColor(hex: "#95A895"), cssVar: "--seal-moss")
    static let sage      = SealColor(light: UIColor(hex: "#8A9A7B"), dark: UIColor(hex: "#A3B396"), cssVar: "--seal-sage")
    static let seaGlass  = SealColor(light: UIColor(hex: "#6B8E8E"), dark: UIColor(hex: "#89ABAB"), cssVar: "--seal-seaglass")
    static let mist      = SealColor(light: UIColor(hex: "#8FA3A3"), dark: UIColor(hex: "#A8B8B8"), cssVar: "--seal-mist")

    // Accent (Extraordinary / star)
    static let indigo    = SealColor(light: UIColor(hex: "#4B5A78"), dark: UIColor(hex: "#6E7F9E"), cssVar: "--seal-indigo")
    static let gold      = SealColor(light: UIColor(hex: "#B8973E"), dark: UIColor(hex: "#D4B35E"), cssVar: "--seal-gold")
    static let twilight  = SealColor(light: UIColor(hex: "#6B5B7B"), dark: UIColor(hex: "#8E7E9E"), cssVar: "--seal-twilight")
    static let amethyst  = SealColor(light: UIColor(hex: "#7B6B8B"), dark: UIColor(hex: "#9E8EAE"), cssVar: "--seal-amethyst")

    // Neutral (Unmarked)
    static let stone     = SealColor(light: UIColor(hex: "#8B7355"), dark: UIColor(hex: "#B8976E"), cssVar: "--stone")
    static let dawn      = SealColor(light: UIColor(hex: "#C4956A"), dark: UIColor(hex: "#D4A87A"), cssVar: "--dawn")
    static let fog       = SealColor(light: UIColor(hex: "#B8AFA2"), dark: UIColor(hex: "#6B6359"), cssVar: "--fog")

    static let warmColors   = [rust, ember, sienna, copper]
    static let coolColors   = [moss, sage, seaGlass, mist]
    static let accentColors = [indigo, gold, twilight, amethyst]
    static let neutralColors = [stone, dawn, fog]

    static func color(for favicon: WalkFavicon?, hashByte: UInt8) -> SealColor {
        switch favicon {
        case .flame:
            return warmColors[Int(hashByte) % warmColors.count]
        case .leaf:
            return coolColors[Int(hashByte) % coolColors.count]
        case .star:
            return accentColors[Int(hashByte) % accentColors.count]
        case nil:
            return neutralColors[Int(hashByte) % neutralColors.count]
        }
    }

    static func uiColor(for favicon: WalkFavicon?, hashByte: UInt8) -> UIColor {
        let sealColor = color(for: favicon, hashByte: hashByte)
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? sealColor.dark : sealColor.light
        }
    }
}
```

**IMPORTANT:** No `UIColor(hex:)` extension exists in this codebase. Add one to `Pilgrim/Extensions/UIColor+Hex.swift`:

```swift
import UIKit

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}
```

Add this file in the same commit as `SealColorPalette.swift`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/SealColorPaletteTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Seal/SealColorPalette.swift UnitTests/SealColorPaletteTests.swift
git commit -m "feat(seal): add 15-color mark-influenced palette"
```

---

## Task 3: Seal Geometry

**Files:**
- Create: `Pilgrim/Models/Seal/SealGeometry.swift`
- Create: `UnitTests/SealGeometryTests.swift`

This extracts the geometry computation from the hash bytes into pure data structs — no rendering. Makes the algorithm testable independent of Core Graphics.

- [ ] **Step 1: Write the failing test**

Create `UnitTests/SealGeometryTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class SealGeometryTests: XCTestCase {

    func testRingCount_baseThreeToFive() {
        // bytes[1] % 3 gives 0, 1, or 2 → base count 3, 4, or 5
        let bytes = [UInt8](repeating: 0, count: 32)
        let geo = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        XCTAssertGreaterThanOrEqual(geo.rings.count, 3)
        XCTAssertLessThanOrEqual(geo.rings.count, 8)
    }

    func testHighMeditationRatio_addsExtraRings() {
        var bytes = [UInt8](repeating: 128, count: 32)
        bytes[1] = 0  // base count = 3
        let geoLow = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        let geoHigh = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0.8, talkRatio: 0)
        XCTAssertGreaterThan(geoHigh.rings.count, geoLow.rings.count)
    }

    func testHighTalkRatio_addsExtraLines() {
        var bytes = [UInt8](repeating: 128, count: 32)
        bytes[8] = 0  // base count = 4
        let geoLow = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        let geoHigh = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0.5)
        XCTAssertGreaterThan(geoHigh.radialLines.count, geoLow.radialLines.count)
    }

    func testRotation_derivedFromByte0() {
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[0] = 128
        let geo = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        let expected = (128.0 / 255.0) * 360.0
        XCTAssertEqual(geo.rotation, expected, accuracy: 0.1)
    }

    func testArcCount_twoToFour() {
        let bytes = [UInt8](repeating: 0, count: 32)
        let geo = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        XCTAssertGreaterThanOrEqual(geo.arcSegments.count, 2)
        XCTAssertLessThanOrEqual(geo.arcSegments.count, 4)
    }

    func testDotCount_threeToSeven() {
        let bytes = [UInt8](repeating: 0, count: 32)
        let geo = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        XCTAssertGreaterThanOrEqual(geo.dots.count, 3)
        XCTAssertLessThanOrEqual(geo.dots.count, 7)
    }

    func testDeterministic_sameBytesProduceSameGeometry() {
        let bytes: [UInt8] = (0..<32).map { UInt8($0 * 8) }
        let geo1 = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0.3, talkRatio: 0.1)
        let geo2 = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0.3, talkRatio: 0.1)
        XCTAssertEqual(geo1.rings.count, geo2.rings.count)
        XCTAssertEqual(geo1.radialLines.count, geo2.radialLines.count)
        XCTAssertEqual(geo1.rotation, geo2.rotation)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `SealGeometry` not defined

- [ ] **Step 3: Write implementation**

Create `Pilgrim/Models/Seal/SealGeometry.swift`:

```swift
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

        // Rings
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

        // Radial lines
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

        // Arc segments
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

        // Dots
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
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Seal/SealGeometry.swift UnitTests/SealGeometryTests.swift
git commit -m "feat(seal): add SealGeometry — deterministic geometry from hash bytes"
```

---

## Task 4: Seal Renderer (Core Graphics)

**Files:**
- Create: `Pilgrim/Models/Seal/SealRenderer.swift`

This renders `SealGeometry` + color + text into a `UIImage` using Core Graphics. Includes ghost route watermark, elevation ring, and weather-influenced edge texture.

- [ ] **Step 1: Write SealRenderer**

Create `Pilgrim/Models/Seal/SealRenderer.swift`:

```swift
import UIKit
import CoreText

enum SealRenderer {

    struct Input {
        let geometry: SealGeometry
        let color: UIColor
        let season: String
        let year: Int
        let timeOfDay: String
        let displayDistance: String
        let unitLabel: String
        let routePoints: [(lat: Double, lon: Double)]?
        let altitudes: [Double]?
        let weatherCondition: String?
    }

    static func render(input: Input, size: CGFloat = 512) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))

        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            let geo = input.geometry

            cgCtx.saveGState()
            cgCtx.translateBy(x: geo.center.x, y: geo.center.y)
            cgCtx.rotate(by: geo.rotation * .pi / 180)
            cgCtx.translateBy(x: -geo.center.x, y: -geo.center.y)

            // Weather-influenced edge texture
            applyWeatherTexture(ctx: cgCtx, condition: input.weatherCondition, center: geo.center, radius: geo.outerRadius, size: size)

            // Ghost route watermark (5% opacity, behind everything)
            if let routePoints = input.routePoints, routePoints.count > 1 {
                drawGhostRoute(ctx: cgCtx, routePoints: routePoints, center: geo.center, radius: geo.outerRadius * 0.7, color: input.color)
            }

            // Elevation ring (replaces ring at index 2 if altitude data available)
            if let altitudes = input.altitudes, altitudes.count > 10, geo.rings.count > 2 {
                drawElevationRing(ctx: cgCtx, altitudes: altitudes, center: geo.center, baseRadius: geo.rings[2].radius, color: input.color, size: size)
            }

            // Rings
            for (i, ring) in geo.rings.enumerated() {
                // Skip ring 2 if we drew an elevation ring
                if i == 2, input.altitudes != nil, (input.altitudes?.count ?? 0) > 10 { continue }
                drawRing(ctx: cgCtx, ring: ring, center: geo.center, color: input.color)
            }

            // Radial lines
            for line in geo.radialLines {
                drawRadialLine(ctx: cgCtx, line: line, color: input.color)
            }

            // Arc segments
            for arc in geo.arcSegments {
                drawArcSegment(ctx: cgCtx, arc: arc, color: input.color)
            }

            // Dots
            for dot in geo.dots {
                drawDot(ctx: cgCtx, dot: dot, color: input.color)
            }

            cgCtx.restoreGState()

            // Curved text (applied after rotation to stay readable)
            cgCtx.saveGState()
            cgCtx.translateBy(x: geo.center.x, y: geo.center.y)
            cgCtx.rotate(by: geo.rotation * .pi / 180)
            cgCtx.translateBy(x: -geo.center.x, y: -geo.center.y)

            let arcR = geo.outerRadius - size * 0.08
            drawCurvedText(
                ctx: cgCtx,
                text: "PILGRIM · \(input.season.uppercased()) \(input.year)",
                center: geo.center,
                radius: arcR,
                fontSize: size * 0.048,
                color: input.color.withAlphaComponent(0.7),
                isTop: true
            )
            drawCurvedText(
                ctx: cgCtx,
                text: "\(input.timeOfDay.uppercased()) WALK",
                center: geo.center,
                radius: arcR,
                fontSize: size * 0.048,
                color: input.color.withAlphaComponent(0.7),
                isTop: false
            )
            cgCtx.restoreGState()

            // Center distance text
            drawCenterText(
                ctx: cgCtx,
                distance: input.displayDistance,
                unitLabel: input.unitLabel,
                center: geo.center,
                size: size,
                color: input.color
            )
        }
    }

    // MARK: - Weather Texture

    private static func applyWeatherTexture(ctx: CGContext, condition: String?, center: CGPoint, radius: CGFloat, size: CGFloat) {
        // Clip to seal circle, then apply edge noise based on weather
        // Clear: no additional texture (crisp edges, default)
        // Rain: add soft noise at the edge (dissolved look)
        // Wind: add directional distortion lines
        // Snow: add small crystalline dots at the edge
        guard let condition = condition?.lowercased(), condition != "clear" else { return }

        ctx.saveGState()
        let edgeBand: CGFloat = size * 0.02

        switch condition {
        case "rain", "drizzle", "thunderstorm":
            // Soft dissolve: random semi-transparent circles along the outer edge
            for i in 0..<60 {
                let angle = CGFloat(i) * (.pi * 2 / 60) + CGFloat.random(in: -0.1...0.1)
                let dist = radius + CGFloat.random(in: -edgeBand...edgeBand)
                let x = center.x + cos(angle) * dist
                let y = center.y + sin(angle) * dist
                let r = CGFloat.random(in: 0.5...2.0)
                ctx.setFillColor(UIColor.black.withAlphaComponent(0.03).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        case "snow":
            // Crystalline fragments: small angular marks
            for i in 0..<40 {
                let angle = CGFloat(i) * (.pi * 2 / 40)
                let dist = radius + CGFloat.random(in: 0...edgeBand)
                let x = center.x + cos(angle) * dist
                let y = center.y + sin(angle) * dist
                ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.05).cgColor)
                ctx.setLineWidth(0.3)
                ctx.move(to: CGPoint(x: x - 1, y: y))
                ctx.addLine(to: CGPoint(x: x + 1, y: y))
                ctx.strokePath()
            }
        case "wind":
            // Directional distortion: short horizontal streaks
            for i in 0..<30 {
                let angle = CGFloat(i) * (.pi * 2 / 30)
                let dist = radius - CGFloat.random(in: 0...edgeBand * 2)
                let x = center.x + cos(angle) * dist
                let y = center.y + sin(angle) * dist
                ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.04).cgColor)
                ctx.setLineWidth(0.4)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: 1...3), y: y))
                ctx.strokePath()
            }
        default:
            break
        }
        ctx.restoreGState()
    }

    // MARK: - Drawing Helpers

    private static func drawRing(ctx: CGContext, ring: SealGeometry.Ring, center: CGPoint, color: UIColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(ring.opacity).cgColor)
        ctx.setLineWidth(ring.strokeWidth)
        if let dash = ring.dashLength, let gap = ring.gapLength {
            ctx.setLineDash(phase: 0, lengths: [dash, gap])
        }
        ctx.strokeEllipse(in: CGRect(
            x: center.x - ring.radius, y: center.y - ring.radius,
            width: ring.radius * 2, height: ring.radius * 2
        ))
        ctx.restoreGState()
    }

    private static func drawRadialLine(ctx: CGContext, line: SealGeometry.RadialLine, color: UIColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(line.opacity).cgColor)
        ctx.setLineWidth(line.strokeWidth)
        ctx.setLineCap(.round)
        ctx.move(to: line.innerPoint)
        ctx.addLine(to: line.outerPoint)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawArcSegment(ctx: CGContext, arc: SealGeometry.ArcSegment, color: UIColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(0.8)
        ctx.setLineCap(.round)
        ctx.move(to: arc.startPoint)
        ctx.addArc(center: CGPoint(x: ctx.boundingBoxOfClipPath.midX, y: ctx.boundingBoxOfClipPath.midY),
                   radius: arc.radius,
                   startAngle: atan2(arc.startPoint.y - ctx.boundingBoxOfClipPath.midY, arc.startPoint.x - ctx.boundingBoxOfClipPath.midX),
                   endAngle: atan2(arc.endPoint.y - ctx.boundingBoxOfClipPath.midY, arc.endPoint.x - ctx.boundingBoxOfClipPath.midX),
                   clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawDot(ctx: CGContext, dot: SealGeometry.Dot, color: UIColor) {
        ctx.saveGState()
        ctx.setFillColor(color.withAlphaComponent(0.35).cgColor)
        ctx.fillEllipse(in: CGRect(
            x: dot.center.x - dot.radius, y: dot.center.y - dot.radius,
            width: dot.radius * 2, height: dot.radius * 2
        ))
        ctx.restoreGState()
    }

    private static func drawGhostRoute(ctx: CGContext, routePoints: [(lat: Double, lon: Double)], center: CGPoint, radius: CGFloat, color: UIColor) {
        guard routePoints.count > 1 else { return }
        let lats = routePoints.map(\.lat)
        let lons = routePoints.map(\.lon)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let latRange = max(maxLat - minLat, 0.0001)
        let lonRange = max(maxLon - minLon, 0.0001)
        let scale = min(radius * 2 / CGFloat(latRange), radius * 2 / CGFloat(lonRange))

        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(0.06).cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let midLat = (minLat + maxLat) / 2
        let midLon = (minLon + maxLon) / 2

        for (i, p) in routePoints.enumerated() {
            let x = center.x + CGFloat(p.lon - midLon) * scale
            let y = center.y - CGFloat(p.lat - midLat) * scale
            if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) }
            else { ctx.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawElevationRing(ctx: CGContext, altitudes: [Double], center: CGPoint, baseRadius: CGFloat, color: UIColor, size: CGFloat) {
        guard altitudes.count > 1 else { return }
        let minAlt = altitudes.min()!
        let maxAlt = altitudes.max()!
        let altRange = max(maxAlt - minAlt, 1.0)
        let maxOffset = size * 0.03

        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(0.8)

        let step = (2 * CGFloat.pi) / CGFloat(altitudes.count)
        for (i, alt) in altitudes.enumerated() {
            let normalized = CGFloat((alt - minAlt) / altRange)
            let r = baseRadius + (normalized - 0.5) * maxOffset * 2
            let angle = step * CGFloat(i) - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if i == 0 { ctx.move(to: point) }
            else { ctx.addLine(to: point) }
        }
        ctx.closePath()
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawCurvedText(ctx: CGContext, text: String, center: CGPoint, radius: CGFloat, fontSize: CGFloat, color: UIColor, isTop: Bool) {
        let font = CTFontCreateWithName("Lato-Regular" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.cgColor,
            .kern: 3.0
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let glyphRuns = CTLineGetGlyphRuns(line) as! [CTRun]

        let totalWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let circumference = 2 * .pi * radius
        let totalAngle = totalWidth / circumference * (2 * .pi)
        let startAngle: CGFloat = isTop ? (.pi + totalAngle / 2) : (-totalAngle / 2)
        let direction: CGFloat = isTop ? -1 : 1

        ctx.saveGState()
        ctx.textMatrix = .identity

        var currentAngle = startAngle
        for run in glyphRuns {
            let glyphCount = CTRunGetGlyphCount(run)
            for j in 0..<glyphCount {
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: j, length: 1), &position)

                var glyph = CGGlyph()
                CTRunGetGlyphs(run, CFRange(location: j, length: 1), &glyph)

                let glyphWidth = CTRunGetTypographicBounds(run, CFRange(location: j, length: 1), nil, nil, nil)
                let glyphAngle = CGFloat(glyphWidth) / circumference * (2 * .pi)

                let midAngle = currentAngle + direction * glyphAngle / 2
                let x = center.x + cos(midAngle) * radius
                let y = center.y + sin(midAngle) * radius

                ctx.saveGState()
                ctx.translateBy(x: x, y: y)
                ctx.rotate(by: midAngle + (isTop ? .pi / 2 : -.pi / 2))
                ctx.translateBy(x: -CGFloat(glyphWidth) / 2, y: 0)

                let runFont = CTRunGetAttributes(run) as! [String: Any]
                let ctFont = runFont[kCTFontAttributeName as String] as! CTFont
                CTFontDrawGlyphs(ctFont, &glyph, &position, 1, ctx)
                ctx.restoreGState()

                currentAngle += direction * glyphAngle
            }
        }
        ctx.restoreGState()
    }

    private static func drawCenterText(ctx: CGContext, distance: String, unitLabel: String, center: CGPoint, size: CGFloat, color: UIColor) {
        let distFont = UIFont(name: "CormorantGaramond-Light", size: size * 0.17) ?? UIFont.systemFont(ofSize: size * 0.17, weight: .light)
        let distAttrs: [NSAttributedString.Key: Any] = [
            .font: distFont,
            .foregroundColor: color.withAlphaComponent(0.7)
        ]
        let distStr = NSAttributedString(string: distance, attributes: distAttrs)
        let distSize = distStr.size()
        distStr.draw(at: CGPoint(x: center.x - distSize.width / 2, y: center.y - size * 0.02 - distSize.height / 2))

        let unitFont = UIFont(name: "Lato-Regular", size: size * 0.05) ?? UIFont.systemFont(ofSize: size * 0.05)
        let fogColor = UIColor(named: "fog") ?? UIColor.gray
        let unitAttrs: [NSAttributedString.Key: Any] = [
            .font: unitFont,
            .foregroundColor: fogColor,
            .kern: 2.0
        ]
        let unitStr = NSAttributedString(string: unitLabel, attributes: unitAttrs)
        let unitSize = unitStr.size()
        unitStr.draw(at: CGPoint(x: center.x - unitSize.width / 2, y: center.y + size * 0.1 - unitSize.height / 2))
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Write a visual smoke test**

Add to `UnitTests/SealGeometryTests.swift`:

```swift
func testRenderer_producesNonEmptyImage() {
    let bytes: [UInt8] = (0..<32).map { UInt8($0 * 8) }
    let geo = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0.3, talkRatio: 0.1)
    let input = SealRenderer.Input(
        geometry: geo,
        color: .brown,
        season: "Spring",
        year: 2026,
        timeOfDay: "Morning",
        displayDistance: "5.2",
        unitLabel: "KM",
        routePoints: [(35.68, 139.76), (35.69, 139.77)],
        altitudes: [100, 110, 120, 115, 105, 100, 95, 90, 100, 110, 120],
        weatherCondition: nil
    )
    let image = SealRenderer.render(input: input)
    XCTAssertEqual(image.size.width, 512)
    XCTAssertEqual(image.size.height, 512)
    // Verify image is not blank by checking a pixel near the center
    guard let cgImage = image.cgImage,
          let data = cgImage.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data) else {
        XCTFail("Could not access image data")
        return
    }
    let centerOffset = (256 * cgImage.bytesPerRow) + (256 * 4)
    let alpha = bytes[centerOffset + 3]
    XCTAssertGreaterThan(alpha, 0, "Center pixel should not be fully transparent")
}
```

- [ ] **Step 4: Run tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Seal/SealRenderer.swift
git commit -m "feat(seal): add Core Graphics seal renderer with ghost route, elevation ring"
```

---

## Task 5: Seal Cache

**Files:**
- Create: `Pilgrim/Models/Seal/SealCache.swift`

- [ ] **Step 1: Write implementation**

Create `Pilgrim/Models/Seal/SealCache.swift`, following `CustomImageCache` pattern:

```swift
import UIKit
import Cache

final class SealCache {

    static let shared = SealCache()

    private let storage: Storage<String, UIImage>?

    private init() {
        let disk = DiskConfig(name: "SealCache", expiry: .never, maxSize: 10_000_000)
        let memory = MemoryConfig(expiry: .seconds(900), countLimit: 50)
        self.storage = try? Storage<String, UIImage>(
            diskConfig: disk,
            memoryConfig: memory,
            transformer: TransformerFactory.forImage()
        )
    }

    func seal(for walkUUID: String) -> UIImage? {
        try? storage?.object(forKey: sealKey(walkUUID))
    }

    func thumbnail(for walkUUID: String) -> UIImage? {
        try? storage?.object(forKey: thumbnailKey(walkUUID))
    }

    func store(seal: UIImage, for walkUUID: String) {
        try? storage?.setObject(seal, forKey: sealKey(walkUUID))
        let thumb = seal.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? seal
        try? storage?.setObject(thumb, forKey: thumbnailKey(walkUUID))
    }

    func clear() {
        try? storage?.removeAll()
    }

    private func sealKey(_ uuid: String) -> String { "seal-\(uuid)" }
    private func thumbnailKey(_ uuid: String) -> String { "seal-thumb-\(uuid)" }
}
```

- [ ] **Step 2: Build to verify compilation**

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Models/Seal/SealCache.swift
git commit -m "feat(seal): add SealCache with disk + memory caching"
```

---

## Task 6: Seal Generator (Public API)

**Files:**
- Create: `Pilgrim/Models/Seal/SealGenerator.swift`

Orchestrates hash → geometry → render → cache. Single public entry point.

- [ ] **Step 1: Write implementation**

Create `Pilgrim/Models/Seal/SealGenerator.swift`:

```swift
import UIKit

enum SealGenerator {

    static func generate(for walk: WalkInterface, size: CGFloat = 512) -> UIImage {
        guard let uuid = walk.uuid?.uuidString else {
            return render(fallbackSeal: size)
        }

        if let cached = SealCache.shared.seal(for: uuid) {
            return cached
        }

        let hash = SealHashComputer.computeHashFromWalk(walk)
        let bytes = SealHashComputer.hexToBytes(hash)

        let activeDuration = walk.activeDuration
        let meditateRatio = activeDuration > 0 ? walk.meditateDuration / activeDuration : 0
        let talkRatio = activeDuration > 0 ? walk.talkDuration / activeDuration : 0

        let geo = SealGeometry(bytes: bytes, size: size, meditateRatio: meditateRatio, talkRatio: talkRatio)

        let favicon = walk.favicon.flatMap { WalkFavicon(rawValue: $0) }
        let color = SealColorPalette.uiColor(for: favicon, hashByte: bytes[30])

        let date = walk.startDate
        let calendar = Calendar.current
        let latitude = walk.routeData.first?.latitude ?? 0

        let season = SealTimeHelpers.season(for: date, latitude: latitude)
        let year = calendar.component(.year, from: date)
        let timeOfDay = SealTimeHelpers.timeOfDay(for: calendar.component(.hour, from: date))

        let distanceKm = walk.distance / 1000
        let isImperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        let displayDist = isImperial
            ? String(format: "%.1f", distanceKm * 0.621371)
            : String(format: "%.1f", distanceKm)
        let unitLabel = isImperial ? "MILES" : "KM"

        let routePoints: [(lat: Double, lon: Double)] = walk.routeData.map {
            (lat: $0.latitude, lon: $0.longitude)
        }
        let altitudes = walk.routeData.map(\.altitude)

        let input = SealRenderer.Input(
            geometry: geo,
            color: color,
            season: season,
            year: year,
            timeOfDay: timeOfDay,
            displayDistance: displayDist,
            unitLabel: unitLabel,
            routePoints: routePoints.count > 1 ? routePoints : nil,
            altitudes: altitudes.count > 10 ? altitudes : nil,
            weatherCondition: walk.weatherCondition
        )

        let image = SealRenderer.render(input: input, size: size)
        SealCache.shared.store(seal: image, for: uuid)
        return image
    }

    static func thumbnail(for walk: WalkInterface) -> UIImage? {
        guard let uuid = walk.uuid?.uuidString else { return nil }
        if let cached = SealCache.shared.thumbnail(for: uuid) {
            return cached
        }
        let seal = generate(for: walk)
        return SealCache.shared.thumbnail(for: uuid)
    }
}
```

- [ ] **Step 2: Write SealTimeHelpers**

Add to `Pilgrim/Models/Seal/SealGenerator.swift` (or a separate file if preferred):

```swift
enum SealTimeHelpers {

    static func season(for date: Date, latitude: Double) -> String {
        let month = Calendar.current.component(.month, from: date)
        let isNorthern = latitude >= 0

        switch month {
        case 3, 4, 5:   return isNorthern ? "Spring" : "Autumn"
        case 6, 7, 8:   return isNorthern ? "Summer" : "Winter"
        case 9, 10, 11: return isNorthern ? "Autumn" : "Spring"
        default:        return isNorthern ? "Winter" : "Summer"
        }
    }

    static func timeOfDay(for hour: Int) -> String {
        switch hour {
        case 5...7:   return "Early Morning"
        case 8...10:  return "Morning"
        case 11...13: return "Midday"
        case 14...16: return "Afternoon"
        case 17...19: return "Evening"
        default:      return "Night"
        }
    }
}
```

Note: The worker uses 0-indexed months (JS `getUTCMonth()` returns 0-11) but the season function in `walk-character.ts` maps them to 2-4, 5-7, 8-10. Verify the Swift version uses 1-indexed months (which `Calendar.current.component(.month)` does). The ranges above are adjusted: worker months 2-4 = Swift months 3-5, etc.

- [ ] **Step 3: Build and run all tests**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED, all tests PASS

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Models/Seal/SealGenerator.swift
git commit -m "feat(seal): add SealGenerator — public API orchestrating hash, geometry, render, cache"
```

---

## Task 7: Worker Updates

**Files:**
- Modify: `pilgrim-worker/src/types.ts`
- Modify: `pilgrim-worker/src/generators/passport-stamp.ts`
- Modify: `pilgrim-worker/src/generators/html-template.ts`

- [ ] **Step 1: Add mark to SharePayload type**

In `pilgrim-worker/src/types.ts`, add to `SharePayload`:
```typescript
mark?: "transformative" | "peaceful" | "extraordinary" | null;
```

- [ ] **Step 2: Update passport-stamp.ts with 15-color palette**

Replace the `colorShift` / `sealColor` section with mark-influenced selection:

```typescript
const warmColors = ["var(--seal-rust)", "var(--seal-ember)", "var(--seal-sienna)", "var(--seal-copper)"];
const coolColors = ["var(--seal-moss)", "var(--seal-sage)", "var(--seal-seaglass)", "var(--seal-mist)"];
const accentColors = ["var(--seal-indigo)", "var(--seal-gold)", "var(--seal-twilight)", "var(--seal-amethyst)"];
const neutralColors = ["var(--stone)", "var(--dawn)", "var(--fog)"];

let sealColor: string;
const colorByte = bytes[30];
switch (payload.mark) {
  case "transformative":
    sealColor = warmColors[colorByte % warmColors.length]; break;
  case "peaceful":
    sealColor = coolColors[colorByte % coolColors.length]; break;
  case "extraordinary":
    sealColor = accentColors[colorByte % accentColors.length]; break;
  default:
    sealColor = neutralColors[colorByte % neutralColors.length];
}
```

- [ ] **Step 3: Add elevation ring to ring generation**

In `generateRings()`, for ring index 2, if route altitude data is available, vary the radius:

```typescript
// After computing base r for ring i=2, apply altitude offsets
if (i === 2 && payload.route.length > 10) {
  // Elevation ring rendered separately in a later step
}
```

Add a new function `generateElevationRing()` that wraps altitude data into a circular path and call it from `generatePassportStamp()`.

- [ ] **Step 4: Add weather texture to feTurbulence**

Map weather condition to filter params:

```typescript
const weatherParams = getWeatherTurbulence(payload.stats.weather_condition);
// In the filter SVG:
<feTurbulence type="turbulence" baseFrequency="${weatherParams.freq}" numOctaves="${weatherParams.octaves}" seed="${bytes[31]}"/>
<feDisplacementMap in="SourceGraphic" scale="${weatherParams.scale}"/>
```

```typescript
function getWeatherTurbulence(condition?: string): { freq: string; octaves: number; scale: number } {
  switch (condition) {
    case "rain": return { freq: "0.06", octaves: 4, scale: 2.0 };
    case "snow": return { freq: "0.08", octaves: 5, scale: 1.0 };
    case "wind": return { freq: "0.03", octaves: 2, scale: 2.5 };
    default:     return { freq: "0.04", octaves: 3, scale: 1.5 };
  }
}
```

- [ ] **Step 5: Add CSS variables to html-template.ts**

Add the 12 new seal color CSS variables (warm, cool, accent) to the `:root` and `@media (prefers-color-scheme: dark)` blocks in `generateWalkPage()`.

- [ ] **Step 6: Fix hash computation to always use full stats**

In `computeWalkHash()`, always use the real stat values. Update `handleShare()` to include full stats in a separate field if needed, or ensure the payload always contains the actual values for hashing.

- [ ] **Step 7: Build and test worker**

```bash
cd pilgrim-worker && npx wrangler deploy --dry-run
```
Expected: successful build

- [ ] **Step 8: Commit**

```bash
cd pilgrim-worker
git add src/types.ts src/generators/passport-stamp.ts src/generators/html-template.ts
git commit -m "feat(seal): 15-color mark palette, elevation ring, weather texture, hash fix"
```

---

## Task 8: iOS SharePayload Update

**Files:**
- Modify: `Pilgrim/Models/Share/SharePayload.swift`
- Modify: `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift`

- [ ] **Step 1: Add mark to SharePayload**

In `Pilgrim/Models/Share/SharePayload.swift`, add:
```swift
let mark: String?  // "transformative", "peaceful", "extraordinary", or nil
```

- [ ] **Step 2: Update WalkShareViewModel to send mark**

In `WalkShareViewModel.buildPayload()`, map the walk's favicon to the share mark string:

```swift
let markValue: String? = {
    guard let faviconStr = walk.favicon, let fav = WalkFavicon(rawValue: faviconStr) else { return nil }
    switch fav {
    case .flame: return "transformative"
    case .leaf:  return "peaceful"
    case .star:  return "extraordinary"
    }
}()
```

Include `mark: markValue` in the payload construction.

- [ ] **Step 3: Ensure full stats always sent for hashing**

Verify the payload always includes the real distance, activeDuration, meditateDuration, talkDuration values (not nil) for hash computation, regardless of toggle state. The worker uses these for hashing.

- [ ] **Step 4: Build and run tests**

Expected: BUILD SUCCEEDED, all tests PASS

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Share/SharePayload.swift Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift
git commit -m "feat(seal): add mark to SharePayload, ensure full stats for hash parity"
```

---

## Completion Checklist

- [ ] SealHashComputer produces byte-identical hashes to the TypeScript worker
- [ ] 15 unique seal colors, correctly selected by mark + hash byte
- [ ] Core Graphics renderer produces visually equivalent seals to web
- [ ] Ghost route watermark visible at 512×512, invisible at 128×128
- [ ] Elevation ring reflects real altitude data
- [ ] Weather condition affects edge texture
- [ ] Seals cached on disk, thumbnails at 128×128
- [ ] Worker updated with mark support, elevation ring, weather texture
- [ ] SharePayload includes mark field
- [ ] All unit tests pass
- [ ] Build succeeds on both iOS and worker
