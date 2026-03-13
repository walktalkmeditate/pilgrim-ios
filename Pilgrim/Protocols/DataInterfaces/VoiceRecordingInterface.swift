import Foundation

public protocol VoiceRecordingInterface: DataInterface {

    var startDate: Date { get }
    var endDate: Date { get }
    var duration: Double { get }
    var fileRelativePath: String { get }
    var transcription: String? { get }
    var wordsPerMinute: Double? { get }

}

public extension VoiceRecordingInterface {

    var startDate: Date { throwOnAccess() }
    var endDate: Date { throwOnAccess() }
    var duration: Double { throwOnAccess() }
    var fileRelativePath: String { throwOnAccess() }
    var transcription: String? { throwOnAccess() }
    var wordsPerMinute: Double? { throwOnAccess() }

}
