import XCTest
@testable import Pilgrim

final class HonorOverviewModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserPreferences.distanceMeasurementType.value = .kilometers
    }

    override func tearDown() {
        UserPreferences.distanceMeasurementType.delete()
        super.tearDown()
    }

    private func way(voices: Int, photos: Int, weather: WayWeather?) -> Way {
        var moments: [WayMoment] = []
        for n in 0..<voices {
            moments.append(WayMoment(id: "voice-\(n + 1)", frac: 0.1, at: nil,
                                     kind: .voice(endFrac: 0.2, duration: 5, kind: .spoken, media: .file("a"))))
        }
        for n in 0..<photos {
            moments.append(WayMoment(id: "photo-\(n + 1)", frac: 0.3, at: nil, kind: .photo(media: .file("p"))))
        }
        return Way(id: "w", source: .ownWalk(UUID()), title: "t", departedAt: Date(), tzIdentifier: nil, expires: nil,
                   route: [], totalDistanceMeters: 0, theirActiveSeconds: 0, moments: moments, weather: weather)
    }

    func testCountsLine() {
        XCTAssertEqual(HonorOverviewModel.countsLine(way: way(voices: 9, photos: 4, weather: nil)), "9 voices · 4 photos")
        XCTAssertEqual(HonorOverviewModel.countsLine(way: way(voices: 1, photos: 0, weather: nil)), "1 voice")
        XCTAssertEqual(HonorOverviewModel.countsLine(way: way(voices: 0, photos: 0, weather: nil)), "a quiet way")
    }

    func testStatusLine() {
        XCTAssertEqual(HonorOverviewModel.statusLine(distanceToStartMeters: 40), "you're on the way")
        XCTAssertEqual(HonorOverviewModel.statusLine(distanceToStartMeters: 2300), "2.3 km from the start")
        XCTAssertEqual(HonorOverviewModel.statusLine(distanceToStartMeters: 650), "650 m from the start")
        XCTAssertNil(HonorOverviewModel.statusLine(distanceToStartMeters: nil))
    }

    func testWeatherLine() {
        let theirs = WayWeather(condition: "rain", temperatureC: 9)
        XCTAssertEqual(HonorOverviewModel.weatherLine(theirs: theirs, today: "clear"),
                       "they walked this in rain at 9°. Today is clear.")
        XCTAssertEqual(HonorOverviewModel.weatherLine(theirs: theirs, today: nil), "they walked this in rain at 9°.")
        XCTAssertNil(HonorOverviewModel.weatherLine(theirs: nil, today: "clear"))
    }
}
