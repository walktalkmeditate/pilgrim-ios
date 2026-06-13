import XCTest
@testable import Pilgrim

final class PermissionRitualTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearRitualState()
    }

    override func tearDown() {
        clearRitualState()
        super.tearDown()
    }

    private func clearRitualState() {
        for permission in PermissionRitual.Permission.allCases {
            UserDefaults.standard.removeObject(forKey: "permissionBellPlayed.\(permission.rawValue)")
        }
        UserPreferences.soundsEnabled.value = true
    }

    // MARK: - Pure decision

    func test_shouldPlayBell_grantedAndEnabledAndNotPlayed_isTrue() {
        XCTAssertTrue(PermissionRitual.shouldPlayBell(
            granted: true, soundsEnabled: true, alreadyPlayed: false
        ))
    }

    func test_shouldPlayBell_notGranted_isFalse() {
        XCTAssertFalse(PermissionRitual.shouldPlayBell(
            granted: false, soundsEnabled: true, alreadyPlayed: false
        ))
    }

    func test_shouldPlayBell_soundsDisabled_isFalse() {
        XCTAssertFalse(PermissionRitual.shouldPlayBell(
            granted: true, soundsEnabled: false, alreadyPlayed: false
        ))
    }

    func test_shouldPlayBell_alreadyPlayed_isFalse() {
        XCTAssertFalse(PermissionRitual.shouldPlayBell(
            granted: true, soundsEnabled: true, alreadyPlayed: true
        ))
    }

    // MARK: - Persistence (once-per-grant)

    func test_consumeBellGrant_firstGrant_returnsTrueAndPersists() {
        let first = PermissionRitual.consumeBellGrant(
            for: .location, granted: true, soundsEnabled: true
        )
        XCTAssertTrue(first, "first grant should fire the bell")
        XCTAssertTrue(PermissionRitual.hasPlayedBell(for: .location),
                      "firing should persist so it can't replay")
    }

    func test_consumeBellGrant_secondGrantSamePermission_returnsFalse() {
        _ = PermissionRitual.consumeBellGrant(
            for: .location, granted: true, soundsEnabled: true
        )
        let second = PermissionRitual.consumeBellGrant(
            for: .location, granted: true, soundsEnabled: true
        )
        XCTAssertFalse(second, "a second grant event for the same permission must stay silent")
    }

    func test_consumeBellGrant_isPerPermission() {
        _ = PermissionRitual.consumeBellGrant(
            for: .location, granted: true, soundsEnabled: true
        )
        let mic = PermissionRitual.consumeBellGrant(
            for: .microphone, granted: true, soundsEnabled: true
        )
        XCTAssertTrue(mic, "a different permission still rings its own first grant")
    }

    func test_consumeBellGrant_soundsDisabled_doesNotConsume() {
        let result = PermissionRitual.consumeBellGrant(
            for: .motion, granted: true, soundsEnabled: false
        )
        XCTAssertFalse(result, "no bell when sounds are off")
        XCTAssertFalse(PermissionRitual.hasPlayedBell(for: .motion),
                       "a silenced grant must not consume the once-per-grant flag")

        UserPreferences.soundsEnabled.value = true
        let later = PermissionRitual.consumeBellGrant(
            for: .motion, granted: true, soundsEnabled: true
        )
        XCTAssertTrue(later, "re-enabling sounds lets the still-unplayed bell ring")
    }

    // MARK: - View model orchestration

    func test_celebrateGrant_firesBellOnce() {
        var bellCount = 0
        let vm = PermissionsViewModel(
            permissionManager: nil,
            onComplete: {},
            playBell: { bellCount += 1 }
        )

        vm.celebrateGrant(.location)
        vm.celebrateGrant(.location)

        XCTAssertEqual(bellCount, 1, "bell fires exactly once per granted permission")
    }

    func test_celebrateGrant_soundsDisabled_pulsesButNoBell() {
        UserPreferences.soundsEnabled.value = false
        var bellCount = 0
        let vm = PermissionsViewModel(
            permissionManager: nil,
            onComplete: {},
            playBell: { bellCount += 1 }
        )

        vm.celebrateGrant(.microphone)

        XCTAssertEqual(bellCount, 0, "no bell when sounds are disabled")
        if UIAccessibility.isReduceMotionEnabled {
            XCTAssertFalse(vm.microphonePulse, "pulse is skipped under Reduce Motion")
        } else {
            XCTAssertTrue(vm.microphonePulse, "pulse still plays even with sounds off")
        }
    }

    func test_celebrateGrant_pulsesGrantedRowOnly() {
        let vm = PermissionsViewModel(
            permissionManager: nil,
            onComplete: {},
            playBell: {}
        )

        vm.celebrateGrant(.motion)

        if !UIAccessibility.isReduceMotionEnabled {
            XCTAssertTrue(vm.motionPulse)
            XCTAssertFalse(vm.locationPulse)
            XCTAssertFalse(vm.microphonePulse)
        }
    }

    // MARK: - AE3: denial fires nothing

    func test_denial_firesNoBellAndNoPulse() {
        var bellCount = 0
        let vm = PermissionsViewModel(
            permissionManager: nil,
            onComplete: {},
            playBell: { bellCount += 1 }
        )

        // A denied grant never reaches celebrateGrant — model state updates
        // only. The decision proves denial is silent regardless of route.
        XCTAssertFalse(PermissionRitual.shouldPlayBell(
            granted: false, soundsEnabled: true, alreadyPlayed: false
        ))
        XCTAssertEqual(bellCount, 0)
        XCTAssertFalse(vm.locationPulse)
        XCTAssertFalse(vm.microphonePulse)
        XCTAssertFalse(vm.motionPulse)
    }
}
