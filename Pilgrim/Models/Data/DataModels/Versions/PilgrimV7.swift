import CoreStore

public enum PilgrimV7: DataModelProtocol {

    static let identifier = "PilgrimV7"
    static let schema = CoreStoreSchema(
        modelVersion: PilgrimV7.identifier,
        entities: [
            Entity<PilgrimV7.Walk>(PilgrimV7.Walk.identifier),
            Entity<PilgrimV7.WalkPause>(PilgrimV7.WalkPause.identifier),
            Entity<PilgrimV7.WalkEvent>(PilgrimV7.WalkEvent.identifier),
            Entity<PilgrimV7.RouteDataSample>(PilgrimV7.RouteDataSample.identifier),
            Entity<PilgrimV7.HeartRateDataSample>(PilgrimV7.HeartRateDataSample.identifier),
            Entity<PilgrimV7.Event>(PilgrimV7.Event.identifier),
            Entity<PilgrimV7.VoiceRecording>(PilgrimV7.VoiceRecording.identifier),
            Entity<PilgrimV7.ActivityInterval>(PilgrimV7.ActivityInterval.identifier),
            Entity<PilgrimV7.Waypoint>(PilgrimV7.Waypoint.identifier),
            Entity<PilgrimV7.WalkPhoto>(PilgrimV7.WalkPhoto.identifier)
        ]
    )

    static let mappingProvider: CustomSchemaMappingProvider? = CustomSchemaMappingProvider(
        from: PilgrimV6.identifier,
        to: PilgrimV7.identifier,
        entityMappings: [
            .transformEntity(
                sourceEntity: PilgrimV6.Workout.identifier,
                destinationEntity: PilgrimV7.Walk.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV6.WorkoutPause.identifier,
                destinationEntity: PilgrimV7.WalkPause.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV6.WorkoutEvent.identifier,
                destinationEntity: PilgrimV7.WalkEvent.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV6.WorkoutRouteDataSample.identifier,
                destinationEntity: PilgrimV7.RouteDataSample.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV6.WorkoutHeartRateDataSample.identifier,
                destinationEntity: PilgrimV7.HeartRateDataSample.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV6.Event.identifier,
                destinationEntity: PilgrimV7.Event.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV6.VoiceRecording.identifier,
                destinationEntity: PilgrimV7.VoiceRecording.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV6.ActivityInterval.identifier,
                destinationEntity: PilgrimV7.ActivityInterval.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV6.Waypoint.identifier,
                destinationEntity: PilgrimV7.Waypoint.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .insertEntity(destinationEntity: PilgrimV7.WalkPhoto.identifier)
        ]
    )

    static let migrationChain: [DataModelProtocol.Type] = [
        OutRunV1.self, OutRunV2.self, OutRunV3.self, OutRunV3to4.self, OutRunV4.self, PilgrimV1.self, PilgrimV2.self, PilgrimV3.self, PilgrimV4.self, PilgrimV5.self, PilgrimV6.self, PilgrimV7.self
    ]

    // MARK: Walk
    public final class Walk: CoreStoreObject, DataTypeProtocol {

        static let identifier = "Workout"

        let _uuid = Value.Optional<UUID>("id")
        let _workoutType = Value.Required<PilgrimV2.Workout.WalkType>("workoutType", initial: .unknown)
        let _distance = Value.Required<Double>("distance", initial: -1)
        let _steps = Value.Optional<Int>("steps")
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))
        let _burnedEnergy = Value.Optional<Double>("burnedEnergy")
        let _isRace = Value.Required<Bool>("isRace", initial: false)
        let _comment = Value.Optional<String>("comment")
        let _isUserModified = Value.Required<Bool>("isUserModified", initial: false)
        let _healthKitUUID = Value.Optional<UUID>("healthKitID")
        let _finishedRecording = Value.Required<Bool>("finishedRecording", initial: true)

        let _ascend = Value.Required<Double>("ascendingAltitude", initial: 0)
        let _descend = Value.Required<Double>("descendingAltitude", initial: 0)
        let _activeDuration = Value.Required<Double>("activeDuration", initial: 0)
        let _pauseDuration = Value.Required<Double>("pauseDuration", initial: 0)
        let _dayIdentifier = Value.Required<String>("dayIdentifier", initial: "")

        let _talkDuration = Value.Required<Double>("talkDuration", initial: 0)
        let _meditateDuration = Value.Required<Double>("meditateDuration", initial: 0)

        let _weatherTemperature = Value.Optional<Double>("weatherTemperature")
        let _weatherCondition = Value.Optional<String>("weatherCondition")
        let _weatherHumidity = Value.Optional<Double>("weatherHumidity")
        let _weatherWindSpeed = Value.Optional<Double>("weatherWindSpeed")

        let _favicon = Value.Optional<String>("favicon")

        let _heartRates = Relationship.ToManyOrdered<PilgrimV7.HeartRateDataSample>("heartRates", inverse: { $0._workout })
        let _routeData = Relationship.ToManyOrdered<PilgrimV7.RouteDataSample>("routeData", inverse: { $0._workout })
        let _pauses = Relationship.ToManyOrdered<PilgrimV7.WalkPause>("pauses", inverse: { $0._workout })
        let _workoutEvents = Relationship.ToManyOrdered<PilgrimV7.WalkEvent>("workoutEvents", inverse: { $0._workout })
        let _events = Relationship.ToManyUnordered<PilgrimV7.Event>("events", inverse: { $0._workouts })
        let _voiceRecordings = Relationship.ToManyOrdered<PilgrimV7.VoiceRecording>("voiceRecordings", inverse: { $0._workout })
        let _activityIntervals = Relationship.ToManyOrdered<PilgrimV7.ActivityInterval>("activityIntervals", inverse: { $0._workout })
        let _waypoints = Relationship.ToManyOrdered<PilgrimV7.Waypoint>("waypoints", inverse: { $0._workout })
        let _walkPhotos = Relationship.ToManyOrdered<PilgrimV7.WalkPhoto>("walkPhotos", inverse: { $0._workout })

    }

    // MARK: WalkPause
    public final class WalkPause: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutPause"

        let _uuid = Value.Optional<UUID>("id")
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))
        let _pauseType = Value.Required<PilgrimV2.WorkoutPause.PauseType>("pauseType", initial: .manual)

        let _workout = Relationship.ToOne<PilgrimV7.Walk>("workout")

    }

    // MARK: WalkEvent
    public final class WalkEvent: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutEvent"

        let _uuid = Value.Optional<UUID>("id")
        let _eventType = Value.Required<PilgrimV2.WorkoutEvent.EventType>("eventType", initial: .unknown)
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0), renamingIdentifier: "startDate")

        let _workout = Relationship.ToOne<PilgrimV7.Walk>("workout")

    }

    // MARK: RouteDataSample
    public final class RouteDataSample: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutRouteDataSample"

        let _uuid = Value.Optional<UUID>("id")
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0))
        let _latitude = Value.Required<Double>("latitude", initial: -1)
        let _longitude = Value.Required<Double>("longitude", initial: -1)
        let _altitude = Value.Required<Double>("altitude", initial: -1)
        let _horizontalAccuracy = Value.Required<Double>("horizontalAccuracy", initial: 0)
        let _verticalAccuracy = Value.Required<Double>("verticalAccuracy", initial: 0)
        let _speed = Value.Required<Double>("speed", initial: -1)
        let _direction = Value.Required<Double>("direction", initial: -1)

        let _workout = Relationship.ToOne<PilgrimV7.Walk>("workout")

    }

    // MARK: HeartRateDataSample
    public final class HeartRateDataSample: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutHeartRateSample"

        let _uuid = Value.Optional<UUID>("id")
        let _heartRate = Value.Required<Int>("heartRate", initial: 0)
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV7.Walk>("workout")

    }

    // MARK: Event
    public final class Event: CoreStoreObject, DataTypeProtocol {

        static let identifier = "Event"

        let _uuid = Value.Optional<UUID>("id")
        let _title = Value.Required<String>("eventTitle", initial: "")
        let _comment = Value.Optional<String>("comment")
        let _startDate = Value.Optional<Date>("startDate")
        let _endDate = Value.Optional<Date>("endDate")

        let _workouts = Relationship.ToManyOrdered<PilgrimV7.Walk>("workouts")

    }

    // MARK: VoiceRecording
    public final class VoiceRecording: CoreStoreObject, DataTypeProtocol {

        static let identifier = "VoiceRecording"

        let _uuid = Value.Optional<UUID>("id")
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))
        let _duration = Value.Required<Double>("duration", initial: 0)
        let _fileRelativePath = Value.Required<String>("fileRelativePath", initial: "")
        let _transcription = Value.Optional<String>("transcription")
        let _wordsPerMinute = Value.Optional<Double>("wordsPerMinute")
        let _isEnhanced = Value.Required<Bool>("isEnhanced", initial: false)

        let _workout = Relationship.ToOne<PilgrimV7.Walk>("workout")

    }

    // MARK: ActivityInterval
    public final class ActivityInterval: CoreStoreObject, DataTypeProtocol {

        static let identifier = "ActivityInterval"

        let _uuid = Value.Optional<UUID>("id")
        let _activityType = Value.Required<PilgrimV2.ActivityInterval.ActivityType>("activityType", initial: .unknown)
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV7.Walk>("workout")

    }

    // MARK: Waypoint
    public final class Waypoint: CoreStoreObject, DataTypeProtocol {

        static let identifier = "Waypoint"

        let _uuid = Value.Optional<UUID>("id")
        let _latitude = Value.Required<Double>("latitude", initial: 0)
        let _longitude = Value.Required<Double>("longitude", initial: 0)
        let _label = Value.Required<String>("label", initial: "")
        let _icon = Value.Required<String>("icon", initial: "")
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV7.Walk>("workout")

    }

    // MARK: WalkPhoto
    public final class WalkPhoto: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WalkPhoto"

        let _uuid = Value.Optional<UUID>("id")
        let _localIdentifier = Value.Required<String>("localIdentifier", initial: "")
        let _capturedAt = Value.Required<Date>("capturedAt", initial: .init(timeIntervalSince1970: 0))
        let _capturedLat = Value.Required<Double>("capturedLat", initial: -1)
        let _capturedLng = Value.Required<Double>("capturedLng", initial: -1)
        let _keptAt = Value.Required<Date>("keptAt", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV7.Walk>("workout")

    }

}
