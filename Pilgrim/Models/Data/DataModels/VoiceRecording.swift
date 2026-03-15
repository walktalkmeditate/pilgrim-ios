import Foundation
import CoreStore

public typealias VoiceRecording = PilgrimV4.VoiceRecording

extension VoiceRecording: VoiceRecordingInterface {

    public var uuid: UUID? { threadSafeSyncReturn { self._uuid.value } }
    public var startDate: Date { threadSafeSyncReturn { self._startDate.value } }
    public var endDate: Date { threadSafeSyncReturn { self._endDate.value } }
    public var duration: Double { threadSafeSyncReturn { self._duration.value } }
    public var fileRelativePath: String { threadSafeSyncReturn { self._fileRelativePath.value } }
    public var transcription: String? { threadSafeSyncReturn { self._transcription.value } }
    public var wordsPerMinute: Double? { threadSafeSyncReturn { self._wordsPerMinute.value } }
    public var workout: WalkInterface? { self._workout.value as? WalkInterface }

}

extension VoiceRecording: TempValueConvertible {

    public var asTemp: TempVoiceRecording {
        TempVoiceRecording(
            uuid: uuid,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            fileRelativePath: fileRelativePath,
            transcription: transcription,
            wordsPerMinute: wordsPerMinute
        )
    }

}
