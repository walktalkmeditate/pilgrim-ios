import Foundation

/// The walker's own voice answering a Way: starting the recording, filing it
/// under the moment it answers, and finding it again. Split out of
/// `ActiveWalkViewModel+Honor.swift`, which carries the engine's lifecycle and
/// the cards, so neither file grows past what one screen of context can hold.
extension ActiveWalkViewModel {

    /// A discarded walk files no reply, so the origin goes before the recorder
    /// does: stopping the recorder lets the microphone go (the session itself
    /// is released when the component does), and a late commit must not be
    /// read as an answer to a Way.
    func discardPendingReply() {
        pendingReplyOrigin = nil
        voiceRecordingManagement.stopRecording()
    }

    /// Starts a recording answering `voice`. When that recording completes,
    /// `bindCompletedRecordings` has it, and `recordReplyIfPending` writes
    /// the mapping.
    func replyHere(to voice: WayMoment) {
        pendingReplyOrigin = voice
        if !isRecordingVoice { toggleVoiceRecording() }
        // `isRecordingVoice` only mirrors `voiceRecordingManagement.isRecording`
        // through an async main-queue sink, so it can't be trusted here yet —
        // reading the component directly gives the synchronous answer.
        // Denied permission, an inactive walk, or a recorder that failed to
        // open all leave it false; with nothing now in flight, no completed
        // recording will ever arrive to consume this origin.
        if !voiceRecordingManagement.isRecording {
            pendingReplyOrigin = nil
        }
    }

    /// The reply is filed under the origin voice's own index — the `n` in
    /// the `voice-n` ids `OwnWalkWayBuilder` writes — never its position in
    /// `moments`, which mixes every kind of moment together.
    func recordReplyIfPending(latestRecording: TempVoiceRecording) {
        guard let way, let origin = pendingReplyOrigin, let n = Self.originIndex(of: origin) else { return }
        pendingReplyOrigin = nil
        try? honorSenses.store().setReply(wayId: way.id, originN: n, relativePath: latestRecording.fileRelativePath)
    }

    /// The walker's earlier reply to `voice`, from a previous honoring of the
    /// same Way. A mapping whose recording is gone reads as no reply at all —
    /// `mediaURL(for:)` returns nil for a file that isn't there.
    func existingReplyURL(for voice: WayMoment) -> URL? {
        guard let way, let n = Self.originIndex(of: voice),
              let relative = honorSenses.store().replies(for: way.id)[n] else { return nil }
        return mediaURL(for: .recording(relativePath: relative))
    }

    /// Starts a reply to the stage's closing line, at the stage's end place.
    func replyToStageReflection() {
        guard let stage = way?.stage else { return }
        replyHere(to: HonorPersistence.stageReflectionMoment(for: stage))
    }

    /// The walker's reply to this stage's reflection, from this walk or an
    /// earlier one. Nil when the recording is gone.
    func stageReflectionReplyURL() -> URL? {
        guard let stage = way?.stage else { return nil }
        return existingReplyURL(for: HonorPersistence.stageReflectionMoment(for: stage))
    }

    /// The card's "your reply" button comes through here rather than touching
    /// the player directly: one voice plays at a time, so a Way voice must be
    /// given up rather than silently replaced under a chip that still claims
    /// it is playing. The engine gets its turn back when the reply ends,
    /// through the player's `onFinished`.
    func playReply(url: URL) {
        wayVoicePlayer?.stop()
        activeVoice = nil
        isVoicePaused = false
        wayVoicePlayer?.play(url: url, volume: Float(UserPreferences.voiceGuideVolume.value))
    }

    // MARK: - Origins

    private static let voiceIDPrefix = "voice-"

    /// The `n` in the `voice-n` ids `OwnWalkWayBuilder` writes — the index a
    /// reply is filed under — or the reserved index the stage's arrival
    /// reflection uses. Nil for any other moment id.
    static func originIndex(of moment: WayMoment) -> Int? {
        if moment.id == HonorPersistence.stageReflectionMomentID { return HonorPersistence.stageReflectionOrigin }
        guard moment.id.hasPrefix(voiceIDPrefix) else { return nil }
        return Int(moment.id.dropFirst(voiceIDPrefix.count))
    }
}
