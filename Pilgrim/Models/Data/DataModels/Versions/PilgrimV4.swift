import CoreStore

public enum PilgrimV4: DataModelProtocol {

    static let identifier = "PilgrimV4"
    static let schema = CoreStoreSchema(
        modelVersion: PilgrimV4.identifier,
        entities: [
            Entity<PilgrimV4.Workout>(PilgrimV4.Workout.identifier),
            Entity<PilgrimV4.WorkoutPause>(PilgrimV4.WorkoutPause.identifier),
            Entity<PilgrimV4.WorkoutEvent>(PilgrimV4.WorkoutEvent.identifier),
            Entity<PilgrimV4.WorkoutRouteDataSample>(PilgrimV4.WorkoutRouteDataSample.identifier),
            Entity<PilgrimV4.WorkoutHeartRateDataSample>(PilgrimV4.WorkoutHeartRateDataSample.identifier),
            Entity<PilgrimV4.Event>(PilgrimV4.Event.identifier),
            Entity<PilgrimV4.VoiceRecording>(PilgrimV4.VoiceRecording.identifier),
            Entity<PilgrimV4.ActivityInterval>(PilgrimV4.ActivityInterval.identifier)
        ]
    )

    static let mappingProvider: CustomSchemaMappingProvider? = CustomSchemaMappingProvider(
        from: PilgrimV3.identifier,
        to: PilgrimV4.identifier,
        entityMappings: [
            .transformEntity(
                sourceEntity: PilgrimV3.Workout.identifier,
                destinationEntity: PilgrimV4.Workout.identifier,
                transformer: { (sourceObject: CustomSchemaMappingProvider.UnsafeSourceObject, createDestinationObject: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let destinationObject = createDestinationObject()
                    destinationObject.enumerateAttributes { (attribute, sourceAttribute) in
                        if let sourceAttribute = sourceAttribute {
                            destinationObject[attribute] = sourceObject[sourceAttribute]
                        }
                    }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV3.WorkoutPause.identifier,
                destinationEntity: PilgrimV4.WorkoutPause.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV3.WorkoutEvent.identifier,
                destinationEntity: PilgrimV4.WorkoutEvent.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV3.WorkoutRouteDataSample.identifier,
                destinationEntity: PilgrimV4.WorkoutRouteDataSample.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV3.WorkoutHeartRateDataSample.identifier,
                destinationEntity: PilgrimV4.WorkoutHeartRateDataSample.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV3.Event.identifier,
                destinationEntity: PilgrimV4.Event.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV3.VoiceRecording.identifier,
                destinationEntity: PilgrimV4.VoiceRecording.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV3.ActivityInterval.identifier,
                destinationEntity: PilgrimV4.ActivityInterval.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            )
        ]
    )

    static let migrationChain: [DataModelProtocol.Type] = [
        OutRunV1.self, OutRunV2.self, OutRunV3.self, OutRunV3to4.self, OutRunV4.self, PilgrimV1.self, PilgrimV2.self, PilgrimV3.self, PilgrimV4.self
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

        let _heartRates = Relationship.ToManyOrdered<PilgrimV4.WorkoutHeartRateDataSample>("heartRates", inverse: { $0._workout })
        let _routeData = Relationship.ToManyOrdered<PilgrimV4.WorkoutRouteDataSample>("routeData", inverse: { $0._workout })
        let _pauses = Relationship.ToManyOrdered<PilgrimV4.WorkoutPause>("pauses", inverse: { $0._workout })
        let _workoutEvents = Relationship.ToManyOrdered<PilgrimV4.WorkoutEvent>("workoutEvents", inverse: { $0._workout })
        let _events = Relationship.ToManyUnordered<PilgrimV4.Event>("events", inverse: { $0._workouts })
        let _voiceRecordings = Relationship.ToManyOrdered<PilgrimV4.VoiceRecording>("voiceRecordings", inverse: { $0._workout })
        let _activityIntervals = Relationship.ToManyOrdered<PilgrimV4.ActivityInterval>("activityIntervals", inverse: { $0._workout })

    }

    // MARK: WorkoutPause
    public final class WorkoutPause: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutPause"

        let _uuid = Value.Optional<UUID>("id")
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))
        let _pauseType = Value.Required<PilgrimV2.WorkoutPause.PauseType>("pauseType", initial: .manual)

        let _workout = Relationship.ToOne<PilgrimV4.Workout>("workout")

    }

    // MARK: WorkoutEvent
    public final class WorkoutEvent: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutEvent"

        let _uuid = Value.Optional<UUID>("id")
        let _eventType = Value.Required<PilgrimV2.WorkoutEvent.EventType>("eventType", initial: .unknown)
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0), renamingIdentifier: "startDate")

        let _workout = Relationship.ToOne<PilgrimV4.Workout>("workout")

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

        let _workout = Relationship.ToOne<PilgrimV4.Workout>("workout")

    }

    // MARK: WorkoutHeartRateDataSample
    public final class WorkoutHeartRateDataSample: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutHeartRateSample"

        let _uuid = Value.Optional<UUID>("id")
        let _heartRate = Value.Required<Int>("heartRate", initial: 0)
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV4.Workout>("workout")

    }

    // MARK: Event
    public final class Event: CoreStoreObject, DataTypeProtocol {

        static let identifier = "Event"

        let _uuid = Value.Optional<UUID>("id")
        let _title = Value.Required<String>("eventTitle", initial: "")
        let _comment = Value.Optional<String>("comment")
        let _startDate = Value.Optional<Date>("startDate")
        let _endDate = Value.Optional<Date>("endDate")

        let _workouts = Relationship.ToManyOrdered<PilgrimV4.Workout>("workouts")

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

        let _workout = Relationship.ToOne<PilgrimV4.Workout>("workout")

    }

    // MARK: ActivityInterval
    public final class ActivityInterval: CoreStoreObject, DataTypeProtocol {

        static let identifier = "ActivityInterval"

        let _uuid = Value.Optional<UUID>("id")
        let _activityType = Value.Required<PilgrimV2.ActivityInterval.ActivityType>("activityType", initial: .unknown)
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV4.Workout>("workout")

    }

}
