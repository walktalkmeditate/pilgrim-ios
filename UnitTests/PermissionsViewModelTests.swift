import XCTest
@testable import Pilgrim

final class PermissionsViewModelTests: XCTestCase {

    func testInitialState_noPermissionsGranted() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        XCTAssertFalse(vm.locationGranted)
        XCTAssertFalse(vm.microphoneGranted)
        XCTAssertFalse(vm.motionGranted)
    }

    func testCanTransition_requiresLocationOnly() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        XCTAssertFalse(vm.canTransition)

        vm.locationGranted = true
        XCTAssertTrue(vm.canTransition)
    }

    func testCanTransition_doesNotRequireMicOrMotion() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        vm.locationGranted = true
        XCTAssertTrue(vm.canTransition)

        XCTAssertFalse(vm.microphoneGranted)
        XCTAssertFalse(vm.motionGranted)
    }

    func testProceed_callsOnComplete() {
        var called = false
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: { called = true })
        vm.proceed()
        XCTAssertTrue(called)
    }

    func testProceed_setsDecidedFlags() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        XCTAssertFalse(vm.microphoneDecided)
        XCTAssertFalse(vm.motionDecided)
        vm.proceed()
        XCTAssertTrue(vm.microphoneDecided)
        XCTAssertTrue(vm.motionDecided)
    }

    func testLocationDenied_setsFlag() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        vm.handleLocationDenied()
        XCTAssertTrue(vm.locationDenied)
    }
}
