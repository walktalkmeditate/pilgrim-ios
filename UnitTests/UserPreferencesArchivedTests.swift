//
//  UserPreferencesArchivedTests.swift
//
//  Pilgrim
//  Copyright (C) 2025-2026 Walk Talk Meditate contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import XCTest
@testable import Pilgrim

final class UserPreferencesArchivedTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserPreferences.archivedWalkRegistry.value = [:]
    }

    func testIsArchivedWalk_returnsFalseForUnknownUUID() {
        let uuid = UUID()
        XCTAssertFalse(UserPreferences.isArchivedWalk(uuid: uuid))
    }

    func testMarkWalkArchived_persistsUUIDAndTimestamp() throws {
        let uuid = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        UserPreferences.markWalkArchived(uuid: uuid, archivedAt: date)
        XCTAssertTrue(UserPreferences.isArchivedWalk(uuid: uuid))
        let epoch = try XCTUnwrap(UserPreferences.archivedAt(uuid: uuid)).timeIntervalSince1970
        XCTAssertEqual(epoch, 1_700_000_000, accuracy: 0.001)
    }

    func testUnmarkWalkArchived_removesFromRegistry() {
        let uuid = UUID()
        UserPreferences.markWalkArchived(uuid: uuid, archivedAt: Date())
        UserPreferences.unmarkWalkArchived(uuid: uuid)
        XCTAssertFalse(UserPreferences.isArchivedWalk(uuid: uuid))
        XCTAssertNil(UserPreferences.archivedAt(uuid: uuid))
    }

    func testMarkWalkArchived_idempotentUpdatesTimestamp() throws {
        let uuid = UUID()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = Date(timeIntervalSince1970: 1_700_000_500)
        UserPreferences.markWalkArchived(uuid: uuid, archivedAt: first)
        UserPreferences.markWalkArchived(uuid: uuid, archivedAt: second)
        let epoch = try XCTUnwrap(UserPreferences.archivedAt(uuid: uuid)).timeIntervalSince1970
        XCTAssertEqual(epoch, 1_700_000_500, accuracy: 0.001)
        XCTAssertEqual(UserPreferences.archivedWalkRegistry.value.count, 1)
    }

    /// Validates that 10 concurrent `markWalkArchived` calls all land
    /// without a lost-update race. Concurrent reads via
    /// `isArchivedWalk` are not explicitly tested here — they go
    /// through `UserDefaults.dictionary(forKey:)` which is per-key
    /// atomic at the UserDefaults layer (an in-flight write doesn't
    /// tear the read; the reader either sees the pre-write or
    /// post-write dictionary, never a half-written one).
    func testConcurrentMarks_raceFree() {
        let uuids = (0..<10).map { _ in UUID() }
        let date = Date()

        DispatchQueue.concurrentPerform(iterations: 10) { i in
            UserPreferences.markWalkArchived(uuid: uuids[i], archivedAt: date)
        }

        XCTAssertEqual(UserPreferences.archivedWalkRegistry.value.count, 10)
        for uuid in uuids {
            XCTAssertTrue(UserPreferences.isArchivedWalk(uuid: uuid))
        }
    }

    func testEmptyRegistry_isDefaultValue() {
        XCTAssertEqual(UserPreferences.archivedWalkRegistry.value, [:])
    }
}
