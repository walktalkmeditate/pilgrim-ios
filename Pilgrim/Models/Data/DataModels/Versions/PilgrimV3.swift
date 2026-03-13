import CoreStore

public enum PilgrimV3: DataModelProtocol {

    static let identifier = "PilgrimV3"
    static let schema = CoreStoreSchema(
        modelVersion: PilgrimV3.identifier,
        entities: [
            Entity<PilgrimV3.Workout>(PilgrimV3.Workout.identifier),
            Entity<PilgrimV3.WorkoutPause>(PilgrimV3.WorkoutPause.identifier),
            Entity<PilgrimV3.WorkoutEvent>(PilgrimV3.WorkoutEvent.identifier),
            Entity<PilgrimV3.WorkoutRouteDataSample>(PilgrimV3.WorkoutRouteDataSample.identifier),
            Entity<PilgrimV3.WorkoutHeartRateDataSample>(PilgrimV3.WorkoutHeartRateDataSample.identifier),
            Entity<PilgrimV3.Event>(PilgrimV3.Event.identifier),
            Entity<PilgrimV3.VoiceRecording>(PilgrimV3.VoiceRecording.identifier),
            Entity<PilgrimV3.ActivityInterval>(PilgrimV3.ActivityInterval.identifier)
        ]
    )

    static let mappingProvider: CustomSchemaMappingProvider? = CustomSchemaMappingProvider(
        from: PilgrimV2.identifier,
        to: PilgrimV3.identifier,
        entityMappings: [
            .copyEntity(sourceEntity: PilgrimV2.Workout.identifier, destinationEntity: PilgrimV3.Workout.identifier),
            .copyEntity(sourceEntity: PilgrimV2.WorkoutPause.identifier, destinationEntity: PilgrimV3.WorkoutPause.identifier),
            .copyEntity(sourceEntity: PilgrimV2.WorkoutEvent.identifier, destinationEntity: PilgrimV3.WorkoutEvent.identifier),
            .copyEntity(sourceEntity: PilgrimV2.WorkoutRouteDataSample.identifier, destinationEntity: PilgrimV3.WorkoutRouteDataSample.identifier),
            .copyEntity(sourceEntity: PilgrimV2.WorkoutHeartRateDataSample.identifier, destinationEntity: PilgrimV3.WorkoutHeartRateDataSample.identifier),
            .copyEntity(sourceEntity: PilgrimV2.Event.identifier, destinationEntity: PilgrimV3.Event.identifier),
            .transformEntity(
                sourceEntity: PilgrimV2.VoiceRecording.identifier,
                destinationEntity: PilgrimV3.VoiceRecording.identifier,
                transformer: { (sourceObject: CustomSchemaMappingProvider.UnsafeSourceObject, createDestinationObject: () -> CustomSchemaMappingProvider.UnsafeDestinationObject) in
                    let destinationObject = createDestinationObject()
                    destinationObject.enumerateAttributes { (attribute, sourceAttribute) in
                        if let sourceAttribute = sourceAttribute {
                            destinationObject[attribute] = sourceObject[sourceAttribute]
                        }
                    }
                }
            ),
            .copyEntity(sourceEntity: PilgrimV2.ActivityInterval.identifier, destinationEntity: PilgrimV3.ActivityInterval.identifier)
        ]
    )

    static let migrationChain: [DataModelProtocol.Type] = [
        OutRunV1.self, OutRunV2.self, OutRunV3.self, OutRunV3to4.self, OutRunV4.self, PilgrimV1.self, PilgrimV2.self, PilgrimV3.self
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

        let _heartRates = Relationship.ToManyOrdered<PilgrimV3.WorkoutHeartRateDataSample>("heartRates", inverse: { $0._workout })
        let _routeData = Relationship.ToManyOrdered<PilgrimV3.WorkoutRouteDataSample>("routeData", inverse: { $0._workout })
        let _pauses = Relationship.ToManyOrdered<PilgrimV3.WorkoutPause>("pauses", inverse: { $0._workout })
        let _workoutEvents = Relationship.ToManyOrdered<PilgrimV3.WorkoutEvent>("workoutEvents", inverse: { $0._workout })
        let _events = Relationship.ToManyUnordered<PilgrimV3.Event>("events", inverse: { $0._workouts })
        let _voiceRecordings = Relationship.ToManyOrdered<PilgrimV3.VoiceRecording>("voiceRecordings", inverse: { $0._workout })
        let _activityIntervals = Relationship.ToManyOrdered<PilgrimV3.ActivityInterval>("activityIntervals", inverse: { $0._workout })

    }

    // MARK: WorkoutPause
    public final class WorkoutPause: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutPause"

        let _uuid = Value.Optional<UUID>("id")
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))
        let _pauseType = Value.Required<PilgrimV2.WorkoutPause.PauseType>("pauseType", initial: .manual)

        let _workout = Relationship.ToOne<PilgrimV3.Workout>("workout")

    }

    // MARK: WorkoutEvent
    public final class WorkoutEvent: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutEvent"

        let _uuid = Value.Optional<UUID>("id")
        let _eventType = Value.Required<PilgrimV2.WorkoutEvent.EventType>("eventType", initial: .unknown)
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0), renamingIdentifier: "startDate")

        let _workout = Relationship.ToOne<PilgrimV3.Workout>("workout")

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

        let _workout = Relationship.ToOne<PilgrimV3.Workout>("workout")

    }

    // MARK: WorkoutHeartRateDataSample
    public final class WorkoutHeartRateDataSample: CoreStoreObject, DataTypeProtocol {

        static let identifier = "WorkoutHeartRateSample"

        let _uuid = Value.Optional<UUID>("id")
        let _heartRate = Value.Required<Int>("heartRate", initial: 0)
        let _timestamp = Value.Required<Date>("timestamp", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV3.Workout>("workout")

    }

    // MARK: Event
    public final class Event: CoreStoreObject, DataTypeProtocol {

        static let identifier = "Event"

        let _uuid = Value.Optional<UUID>("id")
        let _title = Value.Required<String>("eventTitle", initial: "")
        let _comment = Value.Optional<String>("comment")
        let _startDate = Value.Optional<Date>("startDate")
        let _endDate = Value.Optional<Date>("endDate")

        let _workouts = Relationship.ToManyOrdered<PilgrimV3.Workout>("workouts")

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

        let _workout = Relationship.ToOne<PilgrimV3.Workout>("workout")

    }

    // MARK: ActivityInterval
    public final class ActivityInterval: CoreStoreObject, DataTypeProtocol {

        static let identifier = "ActivityInterval"

        let _uuid = Value.Optional<UUID>("id")
        let _activityType = Value.Required<PilgrimV2.ActivityInterval.ActivityType>("activityType", initial: .unknown)
        let _startDate = Value.Required<Date>("startDate", initial: .init(timeIntervalSince1970: 0))
        let _endDate = Value.Required<Date>("endDate", initial: .init(timeIntervalSince1970: 0))

        let _workout = Relationship.ToOne<PilgrimV3.Workout>("workout")

    }

}
