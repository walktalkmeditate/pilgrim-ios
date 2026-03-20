//
//  SealGenerator.swift
//
//  Pilgrim
//  Copyright (C) 2025-2026 Walk Talk Meditate contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit

enum SealGenerator {

    static func generate(for walk: WalkInterface, size: CGFloat = 512) -> UIImage {
        guard let uuid = walk.uuid?.uuidString else {
            return renderFallback(size: size)
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

        let weatherSeed = UInt64(bytes[0])
            | (UInt64(bytes[1]) << 8)
            | (UInt64(bytes[2]) << 16)
            | (UInt64(bytes[3]) << 24)

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
            weatherCondition: walk.weatherCondition,
            weatherSeed: weatherSeed
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
        _ = generate(for: walk)
        return SealCache.shared.thumbnail(for: uuid)
    }

    private static func renderFallback(size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            UIColor.gray.withAlphaComponent(0.3).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8))
        }
    }
}

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
