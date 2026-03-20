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

        parts.append(formatNumber(distance))
        parts.append(formatNumber(activeDuration))
        parts.append(formatNumber(meditateDuration))
        parts.append(formatNumber(talkDuration))
        parts.append(startDate)

        let joined = parts.joined(separator: "|")
        let data = Data(joined.utf8)
        let digest = SHA256.hash(data: data)

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func formatNumber(_ value: Double) -> String {
        if value == value.rounded(.towardZero) && !value.isNaN && !value.isInfinite {
            return String(Int(value))
        }
        return String(value)
    }

    static func hexToBytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        guard hex.count % 2 == 0 else { return bytes }
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

    static func computeHashFromInput(_ input: SealInput) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startDate = formatter.string(from: input.startDate)

        return computeHash(
            routePoints: input.routePoints,
            distance: input.distance,
            activeDuration: input.activeDuration,
            meditateDuration: input.meditateDuration,
            talkDuration: input.talkDuration,
            startDate: startDate
        )
    }

    static func computeHashFromWalk(_ walk: WalkInterface) -> String {
        computeHashFromInput(SealInput(walk: walk))
    }
}
