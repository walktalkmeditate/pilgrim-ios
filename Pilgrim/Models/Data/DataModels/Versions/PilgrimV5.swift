import CoreStore

public enum PilgrimV5: DataModelProtocol {

    static let identifier = "PilgrimV5"
    static let schema = CoreStoreSchema(
        modelVersion: PilgrimV5.identifier,
        entities: [
            Entity<PilgrimV5.Workout>(PilgrimV5.Workout.identifier),
            Entity<PilgrimV5.WorkoutPause>(PilgrimV5.WorkoutPause.identifier),
            Entity<PilgrimV5.WorkoutEvent>(PilgrimV5.WorkoutEvent.identifier),
            Entity<PilgrimV5.WorkoutRouteDataSample>(PilgrimV5.WorkoutRouteDataSample.identifier),
            Entity<PilgrimV5.WorkoutHeartRateDataSample>(PilgrimV5.WorkoutHeartRateDataSample.identifier),
            Entity<PilgrimV5.Event>(PilgrimV5.Event.identifier),
            Entity<PilgrimV5.VoiceRecording>(PilgrimV5.VoiceRecording.identifier),
            Entity<PilgrimV5.ActivityInterval>(PilgrimV5.ActivityInterval.identifier)
        ]
    )

    static let mappingProvider: CustomSchemaMappingProvider? = CustomSchemaMappingProvider(
        from: PilgrimV4.identifier,
        to: PilgrimV5.identifier,
        entityMappings: [
            .transformEntity(
                sourceEntity: PilgrimV4.Workout.identifier,
                destinationEntity: PilgrimV5.Workout.identifier,
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
                sourceEntity: PilgrimV4.WorkoutPause.identifier,
                destinationEntity: PilgrimV5.WorkoutPause.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV4.WorkoutEvent.identifier,
                destinationEntity: PilgrimV5.WorkoutEvent.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV4.WorkoutRouteDataSample.identifier,
                destinationEntity: PilgrimV5.WorkoutRouteDataSample.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV4.WorkoutHeartRateDataSample.identifier,
                destinationEntity: PilgrimV5.WorkoutHeartRateDataSample.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV4.Event.identifier,
                destinationEntity: PilgrimV5.Event.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV4.VoiceRecording.identifier,
                destinationEntity: PilgrimV5.VoiceRecording.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            ),
            .transformEntity(
                sourceEntity: PilgrimV4.ActivityInterval.identifier,
                destinationEntity: PilgrimV5.ActivityInterval.identifier,
                transformer: { (source: CustomSchemaMappingProvider.UnsafeSourceObject, create: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let dest = create()
                    dest.enumerateAttributes { (attr, srcAttr) in if let srcAttr { dest[attr] = source[srcAttr] } }
                }
            )
        ]
    )

    static let migrationChain: [DataModelProtocol.Type] = [
        OutRunV1.self, OutRunV2.self, OutRunV3.self, OutRunV3to4.self, OutRunV4.self, PilgrimV1.self, PilgrimV2.self, PilgrimV3.self, PilgrimV4.self, PilgrimV5.self
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

        let _heartRates = Relationship.ToManyOrdered<PilgrimV5.WorkoutHeartRateDataSample>("heartRates", inverse: { $0._workout })
        let _routeData = Relationship.ToManyOrdered<PilgrimV5.WorkoutRouteDataSample>("routeData", inverse: { $0._workout })
        let _pauses = Relationship.ToManyOrdered<PilgrimV5.WorkoutPause>("pauses", inverse: { $0._workout })
        let _workoutEvents = Relationship.ToManyOrdered<PilgrimV5.WorkoutEvent>("workoutEvents", inverse: { $0._workout })
        let _events = Relationship.ToManyUnordered<PilgrimV5.Event>("events", inverse: { $0._workouts })
        let _voiceRecordings = Relationship.ToManyOrdered<PilgrimV5.VoiceRecording>("voiceRecordings", inverse: { $0._workout })
        let _activityIntervals = Relationship.ToManyOrdered<PilgrimV5.ActivityInterval>("activityIntervals", inverse: { $0._workout })

    }

    // MARK: WorkoutPause
    public final class WorkoutPause: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutPause"

        let _uuid = Value.Optional<UUID>("id")
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))
        let _pauseType = Value.Required<PilgrimV2.WorkoutPause.PauseType>("pauseType", initial: .manual)

        let _workout = Relationship.ToOne<PilgrimV5.Workout>("workout")

    }

    // MARK: WorkoutEvent
    public final class WorkoutEvent: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutEvent"

        let _uuid = Value.Optional<UUID>("id")
        let _eventType = Value.Required<PilgrimV2.WorkoutEvent.EventType>("eventType", initial: .unknown)
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0), renamingIdentifier: "startDate")

        let _workout = Relationship.ToOne<PilgrimV5.Workout>("workout")

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

        let _workout = Relationship.ToOne<PilgrimV5.Workout>("workout")

    }

    // MARK: WorkoutHeartRateDataSample
    public final class WorkoutHeartRateDataSample: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutHeartRateSample"

        let _uuid = Value.Optional<UUID>("id")
        let _heartRate = Value.Required<Int>("heartRate", initial: 0)
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV5.Workout>("workout")

    }

    // MARK: Event
    public final class Event: CoreStoreObject, DataTypeProtocol {

        static let identifier = "Event"

        let _uuid = Value.Optional<UUID>("id")
        let _title = Value.Required<String>("eventTitle", initial: "")
        let _comment = Value.Optional<String>("comment")
        let _startDate = Value.Optional<Date>("startDate")
        let _endDate = Value.Optional<Date>("endDate")

        let _workouts = Relationship.ToManyOrdered<PilgrimV5.Workout>("workouts")

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

        let _workout = Relationship.ToOne<PilgrimV5.Workout>("workout")

    }

    // MARK: ActivityInterval
    public final class ActivityInterval: CoreStoreObject, DataTypeProtocol {

        static let identifier = "ActivityInterval"

        let _uuid = Value.Optional<UUID>("id")
        let _activityType = Value.Required<PilgrimV2.ActivityInterval.ActivityType>("activityType", initial: .unknown)
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV5.Workout>("workout")

    }

}
