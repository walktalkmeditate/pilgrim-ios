import XCTest
@testable import Pilgrim

final class SeekSummaryTests: XCTestCase {

    private let home = SeekPoint(latitude: 48.8566, longitude: 2.3522)
    private let walkStart = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func point(bearing: Double, meters: Double, from origin: SeekPoint? = nil) -> SeekPoint {
        SeekChainGenerator.destination(
            from: origin ?? home,
            bearingDegrees: bearing,
            distanceMeters: meters
        )
    }

    private func arrival(ordinal: Int, center: SeekPoint, minutesIn: Int) -> SeekSummaryModel.Arrival {
        SeekSummaryModel.Arrival(
            label: SeekPersistence.arrivalWaypointLabel(clearingOrdinal: ordinal),
            center: center,
            arrivedAt: walkStart.addingTimeInterval(Double(minutesIn) * 60)
        )
    }

    private func photoSign(id: String, at coordinate: SeekPoint?, minutesIn: Int) -> SeekSummaryModel.Sign {
        SeekSummaryModel.Sign(
            kind: .photo,
            id: id,
            coordinate: coordinate,
            timestamp: walkStart.addingTimeInterval(Double(minutesIn) * 60)
        )
    }

    private func voiceSign(id: String, at coordinate: SeekPoint?, minutesIn: Int) -> SeekSummaryModel.Sign {
        SeekSummaryModel.Sign(
            kind: .voiceRecording,
            id: id,
            coordinate: coordinate,
            timestamp: walkStart.addingTimeInterval(Double(minutesIn) * 60)
        )
    }

    // MARK: - Found under (the hour's light)

    func testFoundUnderDaypart_readsTheSkyAtThePlaceAndMoment() {
        let equator = SeekPoint(latitude: 0, longitude: 0)
        let noonUTC = DateFactory.makeDate(2024, 3, 20, 12, 0, 0)
        let midnightUTC = DateFactory.makeDate(2024, 3, 20, 0, 0, 0)
        XCTAssertEqual(SeekSummaryModel.foundUnderDaypart(center: equator, arrivedAt: noonUTC), .midday)
        XCTAssertEqual(SeekSummaryModel.foundUnderDaypart(center: equator, arrivedAt: midnightUTC), .night)
    }

    func testClearingGroups_carryTheirFoundUnderLight() {
        let equator = SeekPoint(latitude: 0, longitude: 0)
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode, .seekArrival],
            arrivals: [SeekSummaryModel.Arrival(
                label: "First clearing",
                center: equator,
                arrivedAt: DateFactory.makeDate(2024, 3, 20, 12, 0, 0)
            )],
            signs: []
        )
        XCTAssertEqual(data?.groups.first?.foundUnder, .midday)
    }

    // MARK: - Seed keepsake

    func testSummaryData_carriesTheGatewayMomentAndIntentionPresence() {
        let seededAt = walkStart.addingTimeInterval(-30)
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode, .seekArrival],
            arrivals: [arrival(ordinal: 1, center: home, minutesIn: 10)],
            signs: [],
            seededAt: seededAt,
            intentionWasVoiced: true
        )
        XCTAssertEqual(data?.seededAt, seededAt)
        XCTAssertEqual(data?.intentionWasVoiced, true)
    }

    func testSummaryData_defaultsLeaveTheKeepsakeSilent() {
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode],
            arrivals: [arrival(ordinal: 1, center: home, minutesIn: 10)],
            signs: []
        )
        XCTAssertNil(data?.seededAt, "no gateway moment, no keepsake line")
    }

    // MARK: - Seek Detection

    func testIsSeekWalk_seekModeEventPresent() {
        XCTAssertTrue(SeekSummaryModel.isSeekWalk(events: [.seekMode]))
        XCTAssertTrue(SeekSummaryModel.isSeekWalk(events: [.marker, .seekMode, .seekArrival]))
    }

    func testIsSeekWalk_noSeekModeEvent() {
        XCTAssertFalse(SeekSummaryModel.isSeekWalk(events: []))
        XCTAssertFalse(SeekSummaryModel.isSeekWalk(events: [.marker, .lap, .seekArrival]))
    }

    // MARK: - Nil Paths

    func testSummaryData_wanderWalk_isNil() {
        let data = SeekSummaryModel.summaryData(
            events: [],
            arrivals: [arrival(ordinal: 1, center: home, minutesIn: 10)],
            signs: []
        )
        XCTAssertNil(data)
    }

    func testSummaryData_zeroArrivals_isNil() {
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode],
            arrivals: [],
            signs: [photoSign(id: "p1", at: home, minutesIn: 5)]
        )
        XCTAssertNil(data)
    }

    // MARK: - Grouping

    func testSummaryData_twoClearings_groupsSignsAndAlongTheWay() {
        let clearing1 = point(bearing: 90, meters: 500)
        let clearing2 = point(bearing: 90, meters: 1500)
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode, .seekArrival, .seekArrival],
            arrivals: [
                arrival(ordinal: 1, center: clearing1, minutesIn: 15),
                arrival(ordinal: 2, center: clearing2, minutesIn: 35)
            ],
            signs: [
                photoSign(id: "at-first", at: clearing1, minutesIn: 16),
                photoSign(id: "at-second", at: point(bearing: 0, meters: 20, from: clearing2), minutesIn: 36),
                photoSign(id: "mid-route", at: point(bearing: 90, meters: 1000), minutesIn: 25)
            ]
        )

        XCTAssertEqual(data?.groups.count, 2)
        XCTAssertEqual(data?.groups[0].photoIDs, ["at-first"])
        XCTAssertEqual(data?.groups[1].photoIDs, ["at-second"])
        XCTAssertEqual(data?.alongTheWay.photoIDs, ["mid-route"])
    }

    func testBelongsToClearing_boundaryIsInclusive() {
        XCTAssertTrue(SeekSummaryModel.belongsToClearing(distanceMeters: SeekSummaryModel.groupingRadiusMeters))
        XCTAssertFalse(
            SeekSummaryModel.belongsToClearing(distanceMeters: SeekSummaryModel.groupingRadiusMeters.nextUp)
        )
    }

    func testSummaryData_signNearRadiusBoundary_grouped_beyondNot() {
        let clearing = point(bearing: 90, meters: 500)
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode],
            arrivals: [arrival(ordinal: 1, center: clearing, minutesIn: 15)],
            signs: [
                photoSign(id: "just-inside", at: point(bearing: 0, meters: 79.9, from: clearing), minutesIn: 16),
                photoSign(id: "just-outside", at: point(bearing: 0, meters: 85, from: clearing), minutesIn: 17)
            ]
        )

        XCTAssertEqual(data?.groups[0].photoIDs, ["just-inside"])
        XCTAssertEqual(data?.alongTheWay.photoIDs, ["just-outside"])
    }

    func testSummaryData_signGroupsToNearestClearing() {
        let clearing1 = point(bearing: 90, meters: 500)
        let clearing2 = point(bearing: 90, meters: 620)
        let nearSecond = point(bearing: 90, meters: 590)
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode],
            arrivals: [
                arrival(ordinal: 1, center: clearing1, minutesIn: 15),
                arrival(ordinal: 2, center: clearing2, minutesIn: 30)
            ],
            signs: [photoSign(id: "between", at: nearSecond, minutesIn: 31)]
        )

        XCTAssertEqual(data?.groups[0].photoIDs, [String]())
        XCTAssertEqual(data?.groups[1].photoIDs, ["between"])
    }

    // MARK: - Timestamp Fallback (coordinate-less signs)

    func testSummaryData_coordinatelessSign_withinWindow_groupsToPrecedingArrival() {
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode],
            arrivals: [arrival(ordinal: 1, center: point(bearing: 90, meters: 500), minutesIn: 15)],
            signs: [voiceSign(id: "v1", at: nil, minutesIn: 17)]
        )

        XCTAssertEqual(data?.groups[0].voiceRecordingIDs, ["v1"])
        XCTAssertTrue(data?.alongTheWay.isEmpty ?? false)
    }

    func testSummaryData_coordinatelessSign_outsideWindow_alongTheWay() {
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode],
            arrivals: [arrival(ordinal: 1, center: point(bearing: 90, meters: 500), minutesIn: 15)],
            signs: [voiceSign(id: "v-late", at: nil, minutesIn: 25)]
        )

        XCTAssertEqual(data?.groups[0].voiceRecordingIDs, [String]())
        XCTAssertEqual(data?.alongTheWay.voiceRecordingIDs, ["v-late"])
    }

    func testSummaryData_coordinatelessSign_beforeFirstArrival_alongTheWay() {
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode],
            arrivals: [arrival(ordinal: 1, center: point(bearing: 90, meters: 500), minutesIn: 15)],
            signs: [voiceSign(id: "v-early", at: nil, minutesIn: 5)]
        )

        XCTAssertEqual(data?.alongTheWay.voiceRecordingIDs, ["v-early"])
    }

    // MARK: - Ordering

    func testSummaryData_groupsSortedByArrivalTime() {
        let laterCenter = point(bearing: 90, meters: 1500)
        let earlierCenter = point(bearing: 90, meters: 500)
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode],
            arrivals: [
                arrival(ordinal: 2, center: laterCenter, minutesIn: 35),
                arrival(ordinal: 1, center: earlierCenter, minutesIn: 15)
            ],
            signs: []
        )

        XCTAssertEqual(data?.groups.map(\.ordinal), [1, 2])
        XCTAssertEqual(data?.groups.first?.center, earlierCenter)
        XCTAssertEqual(data?.groups.first?.label, "First clearing")
    }

    // MARK: - Unknowns Found Text (R19: never totals, never "X of Y")

    func testUnknownsFoundText_spelledCounts() {
        XCTAssertEqual(SeekSummaryModel.unknownsFoundText(arrivalCount: 1), "One unknown found")
        XCTAssertEqual(SeekSummaryModel.unknownsFoundText(arrivalCount: 2), "Two unknowns found")
        XCTAssertEqual(SeekSummaryModel.unknownsFoundText(arrivalCount: 3), "Three unknowns found")
    }

    func testUnknownsFoundText_neverPhrasesATotal() {
        for count in 1...4 {
            let text = SeekSummaryModel.unknownsFoundText(arrivalCount: count)
            XCTAssertFalse(text.contains("of "), "R19 forbids 'X of Y' phrasing, got: \(text)")
        }
    }

    func testSummaryData_textMatchesReachedCount_notChainSize() {
        let data = SeekSummaryModel.summaryData(
            events: [.seekMode, .seekArrival, .seekArrival],
            arrivals: [
                arrival(ordinal: 1, center: point(bearing: 90, meters: 500), minutesIn: 15),
                arrival(ordinal: 2, center: point(bearing: 90, meters: 1500), minutesIn: 35)
            ],
            signs: []
        )

        XCTAssertEqual(data?.unknownsFoundText, "Two unknowns found")
    }

    // MARK: - Walk Adapter

    private func seekEvents(arrivalAt arrivalDate: Date) -> [TempWalkEvent] {
        [
            WalkDataFactory.makeWorkoutEvent(eventType: .seekMode, timestamp: walkStart),
            WalkDataFactory.makeWorkoutEvent(eventType: .seekArrival, timestamp: arrivalDate)
        ]
    }

    private func arrivalWaypoint(at center: SeekPoint, timestamp: Date) -> TempWaypoint {
        TempWaypoint(
            uuid: nil,
            latitude: center.latitude,
            longitude: center.longitude,
            label: SeekPersistence.arrivalWaypointLabel(clearingOrdinal: 1),
            icon: SeekPersistence.arrivalWaypointIcon,
            timestamp: timestamp
        )
    }

    func testAdapter_wanderWalk_isNil() {
        let walk = WalkDataFactory.makeWalk()
        XCTAssertNil(SeekSummaryModel.summaryData(for: walk))
    }

    func testAdapter_seekWalkWithoutArrivals_isNil() {
        let walk = WalkDataFactory.makeWalk(
            workoutEvents: [WalkDataFactory.makeWorkoutEvent(eventType: .seekMode, timestamp: walkStart)]
        )
        XCTAssertNil(SeekSummaryModel.summaryData(for: walk))
    }

    func testAdapter_groupsPhotosRecordingsAndUserWaypoints() {
        let clearing = point(bearing: 90, meters: 500)
        let arrivalDate = walkStart.addingTimeInterval(15 * 60)
        let recordingUUID = UUID()
        let userWaypointUUID = UUID()
        let farAway = point(bearing: 270, meters: 400)

        let walk = WalkDataFactory.makeWalk(
            routeData: [
                WalkDataFactory.makeRouteDataSample(
                    timestamp: walkStart,
                    latitude: home.latitude,
                    longitude: home.longitude
                ),
                WalkDataFactory.makeRouteDataSample(
                    timestamp: arrivalDate.addingTimeInterval(60),
                    latitude: clearing.latitude,
                    longitude: clearing.longitude
                )
            ],
            workoutEvents: seekEvents(arrivalAt: arrivalDate),
            voiceRecordings: [WalkDataFactory.makeVoiceRecording(
                uuid: recordingUUID,
                startDate: arrivalDate.addingTimeInterval(60),
                endDate: arrivalDate.addingTimeInterval(120)
            )],
            waypoints: [
                arrivalWaypoint(at: clearing, timestamp: arrivalDate),
                TempWaypoint(
                    uuid: userWaypointUUID,
                    latitude: farAway.latitude,
                    longitude: farAway.longitude,
                    label: "Bench",
                    icon: "leaf",
                    timestamp: walkStart.addingTimeInterval(5 * 60)
                )
            ],
            walkPhotos: [TempWalkPhoto(
                uuid: nil,
                localIdentifier: "photo-1",
                capturedAt: arrivalDate.addingTimeInterval(90),
                capturedLat: clearing.latitude,
                capturedLng: clearing.longitude,
                keptAt: arrivalDate.addingTimeInterval(90)
            )]
        )

        let data = SeekSummaryModel.summaryData(for: walk)

        XCTAssertEqual(data?.groups.count, 1)
        XCTAssertEqual(data?.groups[0].label, "First clearing")
        XCTAssertEqual(data?.groups[0].photoIDs, ["photo-1"])
        XCTAssertEqual(data?.groups[0].voiceRecordingIDs, [recordingUUID.uuidString])
        XCTAssertEqual(data?.groups[0].waypointIDs, [String]())
        XCTAssertEqual(data?.alongTheWay.waypointIDs, [userWaypointUUID.uuidString])
    }

    func testAdapter_recordingWithoutRouteData_usesTimestampFallback() {
        let clearing = point(bearing: 90, meters: 500)
        let arrivalDate = walkStart.addingTimeInterval(15 * 60)

        let walk = WalkDataFactory.makeWalk(
            workoutEvents: seekEvents(arrivalAt: arrivalDate),
            voiceRecordings: [
                WalkDataFactory.makeVoiceRecording(
                    uuid: UUID(),
                    startDate: arrivalDate.addingTimeInterval(2 * 60),
                    endDate: arrivalDate.addingTimeInterval(3 * 60),
                    fileRelativePath: "recordings/in-window.m4a"
                ),
                WalkDataFactory.makeVoiceRecording(
                    uuid: UUID(),
                    startDate: arrivalDate.addingTimeInterval(20 * 60),
                    endDate: arrivalDate.addingTimeInterval(21 * 60),
                    fileRelativePath: "recordings/late.m4a"
                )
            ],
            waypoints: [arrivalWaypoint(at: clearing, timestamp: arrivalDate)]
        )

        let data = SeekSummaryModel.summaryData(for: walk)

        XCTAssertEqual(data?.groups[0].voiceRecordingIDs.count, 1)
        XCTAssertEqual(data?.alongTheWay.voiceRecordingIDs.count, 1)
    }
}
