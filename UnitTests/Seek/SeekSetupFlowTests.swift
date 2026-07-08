import XCTest
@testable import Pilgrim

final class SeekSetupFlowTests: XCTestCase {

    private final class FakeAccuracyProvider: SeekAccuracyProviding {

        var hasFullAccuracy: Bool
        var grantsOnRequest: Bool
        private(set) var requestCount = 0

        init(hasFullAccuracy: Bool = true, grantsOnRequest: Bool = false) {
            self.hasFullAccuracy = hasFullAccuracy
            self.grantsOnRequest = grantsOnRequest
        }

        func requestTemporaryFullAccuracy(completion: @escaping (Bool) -> Void) {
            requestCount += 1
            completion(grantsOnRequest)
        }
    }

    override func setUp() {
        super.setUp()
        UserPreferences.seekLastDurationMinutes.delete()
        UserPreferences.seekSafetyShown.delete()
        UserPreferences.beginWithIntention.delete()
    }

    override func tearDown() {
        UserPreferences.seekLastDurationMinutes.delete()
        UserPreferences.seekSafetyShown.delete()
        UserPreferences.beginWithIntention.delete()
        super.tearDown()
    }

    private func makeSeekVM(
        accuracy: FakeAccuracyProvider = FakeAccuracyProvider()
    ) -> ActiveWalkViewModel {
        ActiveWalkViewModel(mode: .seek, seekAccuracy: accuracy)
    }

    // MARK: - Wander unchanged

    func testWanderIsReadyImmediately() {
        XCTAssertEqual(ActiveWalkViewModel().seekSetupStage, .ready)
        XCTAssertEqual(ActiveWalkViewModel(mode: .wander).seekSetupStage, .ready)
    }

    func testWanderIsReadyRegardlessOfBeginWithIntention() {
        UserPreferences.beginWithIntention.value = true
        XCTAssertEqual(ActiveWalkViewModel(mode: .wander).seekSetupStage, .ready)
    }

    func testWanderSeekStagesNeverEngage() {
        let vm = ActiveWalkViewModel(mode: .wander)
        vm.beginSeekSetup()
        XCTAssertEqual(vm.seekSetupStage, .ready)
        vm.advanceSeekSetup(durationMinutes: 30)
        XCTAssertEqual(vm.seekSetupStage, .ready)
        XCTAssertNil(vm.seekDurationMinutes)
        vm.advanceSeekSetupIntentionSet()
        vm.advanceSeekSetupTransitionComplete()
        vm.cancelSeekSetup()
        XCTAssertEqual(vm.seekSetupStage, .ready)
    }

    func testWanderDurationAdvanceDoesNotTouchPreferences() {
        let vm = ActiveWalkViewModel(mode: .wander)
        vm.advanceSeekSetup(durationMinutes: 120)
        XCTAssertEqual(UserPreferences.seekLastDurationMinutes.value, 60)
        XCTAssertFalse(UserPreferences.seekSafetyShown.value)
    }

    // MARK: - Seek stage sequence

    func testSeekRequiresDurationThenIntention() {
        let vm = makeSeekVM()
        XCTAssertEqual(vm.seekSetupStage, .verifyingAccuracy)

        vm.beginSeekSetup()
        XCTAssertEqual(vm.seekSetupStage, .durationQuestion)

        vm.advanceSeekSetupIntentionSet()
        XCTAssertEqual(vm.seekSetupStage, .durationQuestion)
        vm.advanceSeekSetupTransitionComplete()
        XCTAssertEqual(vm.seekSetupStage, .durationQuestion)

        vm.advanceSeekSetup(durationMinutes: 30)
        XCTAssertEqual(vm.seekSetupStage, .intention)

        vm.advanceSeekSetupTransitionComplete()
        XCTAssertEqual(vm.seekSetupStage, .intention)

        vm.advanceSeekSetupIntentionSet()
        XCTAssertEqual(vm.seekSetupStage, .transition)

        vm.advanceSeekSetupTransitionComplete()
        XCTAssertEqual(vm.seekSetupStage, .ready)
    }

    func testSeekDurationCannotBeSetBeforeAccuracyResolves() {
        let vm = makeSeekVM()
        vm.advanceSeekSetup(durationMinutes: 60)
        XCTAssertEqual(vm.seekSetupStage, .verifyingAccuracy)
        XCTAssertNil(vm.seekDurationMinutes)
    }

    // MARK: - Duration persistence

    func testDurationSelectionPersistsToPreference() {
        let vm = makeSeekVM()
        vm.beginSeekSetup()
        vm.advanceSeekSetup(durationMinutes: 120)
        XCTAssertEqual(vm.seekDurationMinutes, 120)
        XCTAssertEqual(UserPreferences.seekLastDurationMinutes.value, 120)
    }

    func testPreselectionReadsLastUsedPreference() {
        XCTAssertEqual(SeekDurationView.preselectedMinutes(
            lastUsed: UserPreferences.seekLastDurationMinutes.value
        ), 60)

        UserPreferences.seekLastDurationMinutes.value = 180
        XCTAssertEqual(SeekDurationView.preselectedMinutes(
            lastUsed: UserPreferences.seekLastDurationMinutes.value
        ), 180)
    }

    func testPreselectionSnapsUnknownValueToClosestPreset() {
        XCTAssertEqual(SeekDurationView.preselectedMinutes(lastUsed: 50), 60)
        XCTAssertEqual(SeekDurationView.preselectedMinutes(lastUsed: 500), 180)
        XCTAssertEqual(SeekDurationView.preselectedMinutes(lastUsed: 0), 30)
    }

    // MARK: - Safety caption

    func testFirstSeekShowsSafetyCaptionSecondDoesNot() {
        let first = makeSeekVM()
        XCTAssertTrue(first.seekShowsSafetyCaption)

        first.beginSeekSetup()
        first.advanceSeekSetup(durationMinutes: 60)
        XCTAssertTrue(UserPreferences.seekSafetyShown.value)

        let second = makeSeekVM()
        XCTAssertFalse(second.seekShowsSafetyCaption)
    }

    func testWanderNeverShowsSafetyCaption() {
        XCTAssertFalse(ActiveWalkViewModel(mode: .wander).seekShowsSafetyCaption)
    }

    // MARK: - Accuracy gate

    func testFullAccuracySkipsTemporaryRequest() {
        let accuracy = FakeAccuracyProvider(hasFullAccuracy: true)
        let vm = makeSeekVM(accuracy: accuracy)
        vm.beginSeekSetup()
        XCTAssertEqual(vm.seekSetupStage, .durationQuestion)
        XCTAssertEqual(accuracy.requestCount, 0)
    }

    func testReducedAccuracyGrantedProceedsToDuration() {
        let accuracy = FakeAccuracyProvider(hasFullAccuracy: false, grantsOnRequest: true)
        let vm = makeSeekVM(accuracy: accuracy)
        vm.beginSeekSetup()
        XCTAssertEqual(vm.seekSetupStage, .durationQuestion)
        XCTAssertEqual(accuracy.requestCount, 1)
    }

    func testReducedAccuracyDeclinedCancels() {
        let accuracy = FakeAccuracyProvider(hasFullAccuracy: false, grantsOnRequest: false)
        let vm = makeSeekVM(accuracy: accuracy)
        vm.beginSeekSetup()
        XCTAssertEqual(vm.seekSetupStage, .cancelled(.accuracyDeclined))
        XCTAssertEqual(accuracy.requestCount, 1)
    }

    func testCancelledSeekDoesNotResumeOnRepeatBegin() {
        let accuracy = FakeAccuracyProvider(hasFullAccuracy: false, grantsOnRequest: false)
        let vm = makeSeekVM(accuracy: accuracy)
        vm.beginSeekSetup()
        vm.beginSeekSetup()
        XCTAssertEqual(vm.seekSetupStage, .cancelled(.accuracyDeclined))
        XCTAssertEqual(accuracy.requestCount, 1)
    }

    // MARK: - User cancel

    func testUserCancelFromDurationQuestion() {
        let vm = makeSeekVM()
        vm.beginSeekSetup()
        vm.cancelSeekSetup()
        XCTAssertEqual(vm.seekSetupStage, .cancelled(.userDismissed))

        vm.advanceSeekSetup(durationMinutes: 30)
        XCTAssertEqual(vm.seekSetupStage, .cancelled(.userDismissed))
    }

    func testUserCancelDoesNotOverwriteAccuracyDecline() {
        let accuracy = FakeAccuracyProvider(hasFullAccuracy: false, grantsOnRequest: false)
        let vm = makeSeekVM(accuracy: accuracy)
        vm.beginSeekSetup()
        vm.cancelSeekSetup()
        XCTAssertEqual(vm.seekSetupStage, .cancelled(.accuracyDeclined))
    }

    func testCancelAfterReadyIsIgnored() {
        let vm = makeSeekVM()
        vm.beginSeekSetup()
        vm.advanceSeekSetup(durationMinutes: 60)
        vm.advanceSeekSetupIntentionSet()
        vm.advanceSeekSetupTransitionComplete()
        vm.cancelSeekSetup()
        XCTAssertEqual(vm.seekSetupStage, .ready)
    }

    // MARK: - U7 scaffold

    func testGPSLockTimeoutHookExists() {
        XCTAssertGreaterThan(ActiveWalkViewModel.seekGPSLockTimeoutSeconds, 0)
    }

    // MARK: - Seek voice

    func testSeekVoice_coversEveryConditionInSeekLanguage() {
        let conditions: [WeatherCondition] = [
            .clear, .partlyCloudy, .overcast, .lightRain, .heavyRain,
            .thunderstorm, .snow, .fog, .wind, .haze
        ]
        for condition in conditions {
            let line = SeekVoice.greeting(for: condition)
            XCTAssertFalse(line.isEmpty, "\(condition) needs a seek greeting")
            XCTAssertFalse(
                line.localizedCaseInsensitiveContains("wander"),
                "\(condition): seek must not speak in wander's voice"
            )
        }
    }
}
