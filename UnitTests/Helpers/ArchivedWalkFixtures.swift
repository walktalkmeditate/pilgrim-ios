import Foundation
@testable import Pilgrim

enum ArchivedWalkFixtures {

    static func manifest(
        walks: [PilgrimWalk] = [],
        archived: [PilgrimArchivedWalk] = []
    ) -> PilgrimManifest {
        PilgrimManifest(
            schemaVersion: "v6",
            exportDate: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "1.6.0",
            walkCount: walks.count,
            preferences: PilgrimPreferences(
                distanceUnit: "km",
                altitudeUnit: "m",
                speedUnit: "min/km",
                energyUnit: "kcal",
                celestialAwareness: true,
                zodiacSystem: "tropical",
                beginWithIntention: false
            ),
            customPromptStyles: [],
            intentions: [],
            events: [],
            archived: archived
        )
    }

    static func archivedWalk(
        id: UUID = UUID(),
        startDateEpoch: Double = 1_700_000_000,
        endDateEpoch: Double = 1_700_001_800,
        archivedAtEpoch: Double = 1_700_500_000,
        distance: Double = 3200,
        activeDuration: Double = 1800,
        talkDuration: Double = 0,
        meditateDuration: Double = 0,
        steps: Int? = nil
    ) -> PilgrimArchivedWalk {
        PilgrimArchivedWalk(
            id: id,
            startDate: startDateEpoch,
            endDate: endDateEpoch,
            archivedAt: archivedAtEpoch,
            stats: .init(
                distance: distance,
                activeDuration: activeDuration,
                talkDuration: talkDuration,
                meditateDuration: meditateDuration,
                steps: steps
            )
        )
    }

    static func encodeManifest(_ manifest: PilgrimManifest) throws -> Data {
        try PilgrimDateCoding.makeEncoder().encode(manifest)
    }
}
