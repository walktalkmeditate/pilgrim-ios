import XCTest
@testable import Pilgrim

final class PermissionsViewModelTests: XCTestCase {

    func testInitialState_noPermissionsGranted() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        XCTAssertFalse(vm.locationGranted)
        XCTAssertFalse(vm.microphoneGranted)
        XCTAssertFalse(vm.motionGranted)
    }

    func testCanTransition_requiresLocationAndMicrophone() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        XCTAssertFalse(vm.canTransition)

        vm.locationGranted = true
        XCTAssertFalse(vm.canTransition)

        vm.microphoneGranted = true
        XCTAssertTrue(vm.canTransition)
    }

    func testCanTransition_doesNotRequireMotion() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        vm.locationGranted = true
        vm.microphoneGranted = true
        XCTAssertTrue(vm.canTransition)
    }

    func testProceed_callsOnComplete() {
        var called = false
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: { called = true })
        vm.proceed()
        XCTAssertTrue(called)
    }

    func testProceed_setsMotionDecided() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        XCTAssertFalse(vm.motionDecided)
        vm.proceed()
        XCTAssertTrue(vm.motionDecided)
    }

    func testLocationDenied_setsFlag() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        vm.handleLocationDenied()
        XCTAssertTrue(vm.locationDenied)
    }

    func testMicrophoneDenied_setsFlag() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        vm.handleMicrophoneDenied()
        XCTAssertTrue(vm.microphoneDenied)
    }
}
