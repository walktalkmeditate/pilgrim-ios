import XCTest
@testable import Pilgrim

final class PermissionStatusViewModelTests: XCTestCase {

    func testNeedsAttention_allGranted_returnsFalse() {
        let vm = PermissionStatusViewModel()
        vm.locationState = .granted
        vm.microphoneState = .granted
        vm.motionState = .notDetermined
        XCTAssertFalse(vm.needsAttention)
    }

    func testNeedsAttention_locationDenied_returnsTrue() {
        let vm = PermissionStatusViewModel()
        vm.locationState = .denied
        vm.microphoneState = .granted
        XCTAssertTrue(vm.needsAttention)
    }

    func testNeedsAttention_microphoneNotDetermined_returnsTrue() {
        let vm = PermissionStatusViewModel()
        vm.locationState = .granted
        vm.microphoneState = .notDetermined
        XCTAssertTrue(vm.needsAttention)
    }

    func testNeedsAttention_locationRestricted_returnsFalse() {
        let vm = PermissionStatusViewModel()
        vm.locationState = .restricted
        vm.microphoneState = .granted
        XCTAssertFalse(vm.needsAttention)
    }

    func testNeedsAttention_motionDenied_doesNotAffect() {
        let vm = PermissionStatusViewModel()
        vm.locationState = .granted
        vm.microphoneState = .granted
        vm.motionState = .denied
        XCTAssertFalse(vm.needsAttention)
    }

    func testReadMicrophoneState_returnsValidState() {
        let state = PermissionStatusViewModel.readMicrophoneState()
        XCTAssertTrue([.granted, .notDetermined, .denied].contains(state))
    }

    func testReadMotionState_returnsValidState() {
        let state = PermissionStatusViewModel.readMotionState()
        XCTAssertTrue([.granted, .notDetermined, .denied, .restricted].contains(state))
    }

    func testReadLocationState_returnsValidState() {
        let state = PermissionStatusViewModel.readLocationState()
        XCTAssertTrue([.granted, .notDetermined, .denied, .restricted].contains(state))
    }
}
