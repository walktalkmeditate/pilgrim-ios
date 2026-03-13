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

    func testOnComplete_calledWhenCanTransitionBecomesTrue() {
        let expectation = expectation(description: "onComplete called")
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {
            expectation.fulfill()
        })
        vm.locationGranted = true
        vm.microphoneGranted = true
        waitForExpectations(timeout: 3)
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

    func testMotionDecided_setOnTransition() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        XCTAssertFalse(vm.motionDecided)
        vm.locationGranted = true
        vm.microphoneGranted = true
        let expectation = expectation(description: "motionDecided set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if vm.motionDecided { expectation.fulfill() }
        }
        waitForExpectations(timeout: 2)
    }
}
