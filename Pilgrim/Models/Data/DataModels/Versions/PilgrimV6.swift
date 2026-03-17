import CoreStore

public enum PilgrimV6: DataModelProtocol {

    static let identifier = "PilgrimV6"
    static let schema = CoreStoreSchema(
        modelVersion: PilgrimV6.identifier,
        entities: [
            Entity<PilgrimV6.Workout>(PilgrimV6.Workout.identifier),
            Entity<PilgrimV6.WorkoutPause>(PilgrimV6.WorkoutPause.identifier),
            Entity<PilgrimV6.WorkoutEvent>(PilgrimV6.WorkoutEvent.identifier),
            Entity<PilgrimV6.WorkoutRouteDataSample>(PilgrimV6.WorkoutRouteDataSample.identifier),
            Entity<PilgrimV6.WorkoutHeartRateDataSample>(PilgrimV6.WorkoutHeartRateDataSample.identifier),
            Entity<PilgrimV6.Event>(PilgrimV6.Event.identifier),
            Entity<PilgrimV6.VoiceRecording>(PilgrimV6.VoiceRecording.identifier),
            Entity<PilgrimV6.ActivityInterval>(PilgrimV6.ActivityInterval.identifier),
            Entity<PilgrimV6.Waypoint>(PilgrimV6.Waypoint.identifier)
        ]
    )

    static let mappingProvider: CustomSchemaMappingProvider? = CustomSchemaMappingProvider(
        from: PilgrimV5.identifier,
        to: PilgrimV6.identifier,
        entityMappings: [
            .transformEntity(
                sourceEntity: PilgrimV5.Workout.identifier,
                destinationEntity: PilgrimV6.Workout.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV5.WorkoutPause.identifier,
                destinationEntity: PilgrimV6.WorkoutPause.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV5.WorkoutEvent.identifier,
                destinationEntity: PilgrimV6.WorkoutEvent.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV5.WorkoutRouteDataSample.identifier,
                destinationEntity: PilgrimV6.WorkoutRouteDataSample.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV5.WorkoutHeartRateDataSample.identifier,
                destinationEntity: PilgrimV6.WorkoutHeartRateDataSample.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV5.Event.identifier,
                destinationEntity: PilgrimV6.Event.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV5.VoiceRecording.identifier,
                destinationEntity: PilgrimV6.VoiceRecording.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV5.ActivityInterval.identifier,
                destinationEntity: PilgrimV6.ActivityInterval.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .insertEntity(destinationEntity: PilgrimV6.Waypoint.identifier)
        ]
    )

    static let migrationChain: [DataModelProtocol.Type] = [
        OutRunV1.self, OutRunV2.self, OutRunV3.self, OutRunV3to4.self, OutRunV4.self, PilgrimV1.self, PilgrimV2.self, PilgrimV3.self, PilgrimV4.self, PilgrimV5.self, PilgrimV6.self
    ]

    // MARK: Workout
    public final class Workout: CoreStoreObject, DataTypeProtocol {

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

        let _heartRates = Relationship.ToManyOrdered<PilgrimV6.WorkoutHeartRateDataSample>("heartRates", inverse: { $0._workout })
        let _routeData = Relationship.ToManyOrdered<PilgrimV6.WorkoutRouteDataSample>("routeData", inverse: { $0._workout })
        let _pauses = Relationship.ToManyOrdered<PilgrimV6.WorkoutPause>("pauses", inverse: { $0._workout })
        let _workoutEvents = Relationship.ToManyOrdered<PilgrimV6.WorkoutEvent>("workoutEvents", inverse: { $0._workout })
        let _events = Relationship.ToManyUnordered<PilgrimV6.Event>("events", inverse: { $0._workouts })
        let _voiceRecordings = Relationship.ToManyOrdered<PilgrimV6.VoiceRecording>("voiceRecordings", inverse: { $0._workout })
        let _activityIntervals = Relationship.ToManyOrdered<PilgrimV6.ActivityInterval>("activityIntervals", inverse: { $0._workout })
        let _waypoints = Relationship.ToManyOrdered<PilgrimV6.Waypoint>("waypoints", inverse: { $0._workout })

    }

    // MARK: WorkoutPause
    public final class WorkoutPause: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutPause"

        let _uuid = Value.Optional<UUID>("id")
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))
        let _pauseType = Value.Required<PilgrimV2.WorkoutPause.PauseType>("pauseType", initial: .manual)

        let _workout = Relationship.ToOne<PilgrimV6.Workout>("workout")

    }

    // MARK: WorkoutEvent
    public final class WorkoutEvent: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutEvent"

        let _uuid = Value.Optional<UUID>("id")
        let _eventType = Value.Required<PilgrimV2.WorkoutEvent.EventType>("eventType", initial: .unknown)
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0), renamingIdentifier: "startDate")

        let _workout = Relationship.ToOne<PilgrimV6.Workout>("workout")

    }

    // MARK: WorkoutRouteDataSample
    public final class WorkoutRouteDataSample: CoreStoreObject, DataTypeProtocol {

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

        let _workout = Relationship.ToOne<PilgrimV6.Workout>("workout")

    }

    // MARK: WorkoutHeartRateDataSample
    public final class WorkoutHeartRateDataSample: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutHeartRateSample"

        let _uuid = Value.Optional<UUID>("id")
        let _heartRate = Value.Required<Int>("heartRate", initial: 0)
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV6.Workout>("workout")

    }

    // MARK: Event
    public final class Event: CoreStoreObject, DataTypeProtocol {

        static let identifier = "Event"

        let _uuid = Value.Optional<UUID>("id")
        let _title = Value.Required<String>("eventTitle", initial: "")
        let _comment = Value.Optional<String>("comment")
        let _startDate = Value.Optional<Date>("startDate")
        let _endDate = Value.Optional<Date>("endDate")

        let _workouts = Relationship.ToManyOrdered<PilgrimV6.Workout>("workouts")

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

        let _workout = Relationship.ToOne<PilgrimV6.Workout>("workout")

    }

    // MARK: ActivityInterval
    public final class ActivityInterval: CoreStoreObject, DataTypeProtocol {

        static let identifier = "ActivityInterval"

        let _uuid = Value.Optional<UUID>("id")
        let _activityType = Value.Required<PilgrimV2.ActivityInterval.ActivityType>("activityType", initial: .unknown)
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV6.Workout>("workout")

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

        let _workout = Relationship.ToOne<PilgrimV6.Workout>("workout")

    }

}
