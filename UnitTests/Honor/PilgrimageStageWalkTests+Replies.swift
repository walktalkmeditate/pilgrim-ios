import XCTest
@testable import Pilgrim

/// The stage's closing line and the walker's answer to it: where the reply is
/// filed, that it survives a walk ending mid-recording, and what the summary
/// then carries. Cases of `PilgrimageStageWalkTests` (its stage fixture and
/// its injected senses drive them); a file of their own only because that one
/// is at SwiftLint's length gate.
extension PilgrimageStageWalkTests {

    func testTheReflectionIsFiledUnderTheReservedOrigin() throws {
        let stage = try XCTUnwrap(stageWay().stage)
        let moment = HonorPersistence.stageReflectionMoment(for: stage)
        XCTAssertEqual(moment.id, HonorPersistence.stageReflectionMomentID)
        XCTAssertEqual(ActiveWalkViewModel.originIndex(of: moment), HonorPersistence.stageReflectionOrigin)
        XCTAssertEqual(HonorPersistence.stageReflectionOrigin, -1)
        XCTAssertEqual(moment.at, stage.end.at, "the reply is recorded at the stage's end place")

        var voice = WayMoment(id: "voice-3", frac: 0.5, at: nil,
                              kind: .voice(endFrac: 0.6, duration: 10, kind: .spoken, media: .file("audio/3.m4a")))
        voice.place = nil
        XCTAssertEqual(ActiveWalkViewModel.originIndex(of: voice), 3, "voice replies are unchanged")
        XCTAssertNil(ActiveWalkViewModel.originIndex(of:
            WayMoment(id: "wp-orisson", frac: 0.3, at: nil, kind: .waypoint(label: "x", icon: "mappin"))))
    }

    func testAReplyToTheReflectionRoundTrips() throws {
        let way = stageWay()
        try store.save(way)
        // A reply resolves against the real Documents directory, so the file
        // it needs cannot live in this test's temp dir. A unique name keeps
        // two tests from writing over each other's; teardown removes it.
        let relativePath = "Recordings/stage-reply-\(UUID().uuidString).m4a"
        let recording = try writeSilentRecording(relativePath: relativePath)

        let vm = honorWalk(way: way)
        XCTAssertNil(vm.stageReflectionReplyURL())
        try store.setReply(wayId: way.id, originN: HonorPersistence.stageReflectionOrigin,
                           relativePath: relativePath)
        XCTAssertEqual(vm.stageReflectionReplyURL(), recording)
    }

    /// The arrival card invites a reply at the exact moment the walker is
    /// about to press stop, so the recording is still open when the walk ends.
    /// Its completion only reaches the view model after `stop()` has torn the
    /// walk down — and the mapping must still be written.
    func testAReplyStillRecordingWhenTheWalkEndsIsStillFiledUnderTheReflection() throws {
        let way = stageWay()
        try store.save(way)
        let relativePath = "Recordings/stage-late-reply-\(UUID().uuidString).m4a"
        let recording = try writeSilentRecording(relativePath: relativePath)

        let vm = honorWalk(way: way)
        vm.builder.setStatus(.ready)
        vm.startRecording()
        settleCombineSchedulers()

        // Stands in for a real `AVAudioRecorder`, which the test host cannot
        // be relied on to open: `replyHere` keeps the origin only when the
        // recorder reports itself running.
        vm.voiceRecordingManagement._test_setActiveRecording(start: start, relativePath: relativePath)
        settleCombineSchedulers()

        vm.replyToStageReflection()
        XCTAssertEqual(vm.pendingReplyOrigin?.id, HonorPersistence.stageReflectionMomentID)

        vm.stop()
        settleCombineSchedulers()

        // What `VoiceRecordingManagement.flushCurrentRecording` publishes once
        // the pre-snapshot flush has finalized the file — after `stop()` has
        // already emptied `cancellables`.
        vm.builder.flushVoiceRecordings([
            TempVoiceRecording(uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(5),
                               duration: 5, fileRelativePath: relativePath, isEnhanced: false)
        ])
        settleCombineSchedulers()

        XCTAssertEqual(store.replies(for: way.id), [HonorPersistence.stageReflectionOrigin: relativePath])
        XCTAssertEqual(vm.stageReflectionReplyURL(), recording)
    }

    func testTheArrivalCardAppendsTheStagesClosingLine() {
        let card = HonorArrivalCard(wayTitle: "t", voicesHeard: 0, placesPassed: 2,
                                    theirSeconds: 0, yourSeconds: 0,
                                    stageName: "Saint-Jean-Pied-de-Port to Roncesvalles",
                                    distanceWalkedMeters: 24_200,
                                    closing: "You crossed a border on foot.")
        XCTAssertEqual(card.closing, "You crossed a border on foot.")
        XCTAssertEqual(HonorArrivalCardView.title(for: card), "you walked the stage")
    }

    func testTheSummaryCarriesTheClosingOnlyWhenArrivalFired() {
        let walk = WalkDataFactory.makeWalk(
            uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(3600),
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: start)])
        let noArrival = HonorSummaryModel.summaryData(for: walk, way: stageWay(), link: nil,
                                                      replies: [:], ledger: nil)
        XCTAssertNil(noArrival?.closing, "the way was left before its end")

        let arrived = WalkDataFactory.makeWalk(
            uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(3600),
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: start),
                            TempWalkEvent(uuid: nil, eventType: .honorArrival, timestamp: start)])
        let data = HonorSummaryModel.summaryData(
            for: arrived, way: stageWay(), link: nil,
            replies: [HonorPersistence.stageReflectionOrigin: "Recordings/stage-reply.m4a"], ledger: nil)
        XCTAssertEqual(data?.closing, "You crossed a border on foot.")
        XCTAssertEqual(data?.replyRelativePath, "Recordings/stage-reply.m4a")
        XCTAssertEqual(data?.repliesMade, 1)
    }
}
