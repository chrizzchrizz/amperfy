//
//  PlayQueueSaveThrottleTest.swift
//  AmperfyKitTests
//
//  Created by Chrizz Gelbach on 28.10.26.
//  Copyright (c) 2026 Chrizz Gelbach. All rights reserved.
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

@testable import AmperfyKit
import XCTest

// MARK: - PlayQueueSaveThrottleTest

class PlayQueueSaveThrottleTest: XCTestCase {
  let start = Date(timeIntervalSince1970: 1_000_000)
  let snapshot = PlayQueueSnapshot(songIds: ["a", "b", "c"], currentIndex: 1, positionInMs: 10000)

  func testPeriodicSave() {
    var throttle = PlayQueueSaveThrottle()
    XCTAssertTrue(throttle.isPeriodicSaveDue(now: start))
    throttle.didSave(snapshot, now: start)
    XCTAssertFalse(throttle.isPeriodicSaveDue(now: start.addingTimeInterval(29)))
    XCTAssertTrue(throttle.isPeriodicSaveDue(now: start.addingTimeInterval(30)))
  }

  func testFailedSaveIsRetriedWithNextPeriodicSave() {
    var throttle = PlayQueueSaveThrottle()
    throttle.didFailToSave(now: start)
    XCTAssertFalse(throttle.isPeriodicSaveDue(now: start.addingTimeInterval(10)))
    XCTAssertTrue(throttle.isPeriodicSaveDue(now: start.addingTimeInterval(30)))
    XCTAssertTrue(throttle.isSaveNeeded(for: snapshot))
  }

  func testIsSaveNeeded() {
    var throttle = PlayQueueSaveThrottle()
    XCTAssertTrue(throttle.isSaveNeeded(for: snapshot))
    throttle.didSave(snapshot, now: start)
    XCTAssertFalse(throttle.isSaveNeeded(for: snapshot))

    var changed = snapshot
    changed.positionInMs += 4999
    XCTAssertFalse(throttle.isSaveNeeded(for: changed))
    changed.positionInMs = snapshot.positionInMs + 5000
    XCTAssertTrue(throttle.isSaveNeeded(for: changed))
    // jumped back in the song
    changed.positionInMs = snapshot.positionInMs - 5000
    XCTAssertTrue(throttle.isSaveNeeded(for: changed))

    changed = snapshot
    changed.currentIndex = 2
    XCTAssertTrue(throttle.isSaveNeeded(for: changed))

    changed = snapshot
    changed.songIds.append("d")
    XCTAssertTrue(throttle.isSaveNeeded(for: changed))
  }

  func testTakeoverCheckInterval() {
    var throttle = PlayQueueSaveThrottle()
    XCTAssertTrue(throttle.shouldCheckForTakeover(now: start))
    XCTAssertFalse(throttle.shouldCheckForTakeover(now: start.addingTimeInterval(60)))
    XCTAssertFalse(throttle.shouldCheckForTakeover(now: start.addingTimeInterval(119)))
    XCTAssertTrue(throttle.shouldCheckForTakeover(now: start.addingTimeInterval(120)))
  }

  func testLocalStartIgnoresOtherDevicesForGracePeriod() {
    var throttle = PlayQueueSaveThrottle()
    throttle.didSave(snapshot, now: start)
    throttle.didStartLocally(now: start)
    // the queue is saved again after a local start, even if it didn't change
    XCTAssertTrue(throttle.isSaveNeeded(for: snapshot))
    XCTAssertFalse(throttle.shouldCheckForTakeover(now: start.addingTimeInterval(179)))
    XCTAssertTrue(throttle.shouldCheckForTakeover(now: start.addingTimeInterval(180)))
  }

  func testIsSavedByOtherDevice() {
    let own = "Amperfy (iPad)"
    let byPhone = ServerPlayQueueInfo(
      currentId: "a",
      positionInMs: 0,
      changed: start,
      changedBy: "Amperfy (iPhone)"
    )
    XCTAssertTrue(PlayQueueSaveThrottle.isSavedByOtherDevice(byPhone, ownClientName: own))

    var bySelf = byPhone
    bySelf.changedBy = own
    XCTAssertFalse(PlayQueueSaveThrottle.isSavedByOtherDevice(bySelf, ownClientName: own))

    var byUnknown = byPhone
    byUnknown.changedBy = nil
    XCTAssertFalse(PlayQueueSaveThrottle.isSavedByOtherDevice(byUnknown, ownClientName: own))
    byUnknown.changedBy = ""
    XCTAssertFalse(PlayQueueSaveThrottle.isSavedByOtherDevice(byUnknown, ownClientName: own))
  }
}

// MARK: - PlayQueueSnapshotCreationTest

@MainActor
class PlayQueueSnapshotCreationTest: XCTestCase {
  var library: LibraryStorage!
  var account: Account!
  var otherAccount: Account!

  override func setUp() async throws {
    let cdHelper = CoreDataHelper()
    let context = cdHelper.createInMemoryManagedObjectContext()
    cdHelper.clearContext(context: context)
    library = LibraryStorage(context: context)
    account = library.getAccount(info: TestAccountInfo.create1())
    otherAccount = library.getAccount(info: TestAccountInfo.create2())
  }

  private func song(_ id: String, account: Account? = nil) -> Song {
    let song = library.createSong(account: account ?? self.account)
    song.id = id
    return song
  }

  func testPlaybackOrder() {
    let snapshot = PlayQueueSyncer.createSnapshot(
      account: account,
      current: song("c"),
      prev: [song("p1"), song("p2")],
      user: [song("u1")],
      next: [song("n1"), song("n2")],
      elapsedTime: 83.456
    )
    XCTAssertEqual(snapshot?.songIds, ["p1", "p2", "c", "u1", "n1", "n2"])
    XCTAssertEqual(snapshot?.currentIndex, 2)
    XCTAssertEqual(snapshot?.currentId, "c")
    XCTAssertEqual(snapshot?.positionInMs, 83456)
  }

  func testOtherAccountsAndRadiosAreLeftOut() {
    let radio = library.createRadio(account: account)
    radio.id = "radio"
    let snapshot = PlayQueueSyncer.createSnapshot(
      account: account,
      current: song("c"),
      prev: [song("p1"), song("x1", account: otherAccount), radio],
      user: [],
      next: [song("x2", account: otherAccount), song("n1")],
      elapsedTime: 0
    )
    XCTAssertEqual(snapshot?.songIds, ["p1", "c", "n1"])
    XCTAssertEqual(snapshot?.currentIndex, 1)
  }

  func testNothingToSave() {
    XCTAssertNil(PlayQueueSyncer.createSnapshot(
      account: account, current: nil, prev: [song("p1")], user: [], next: [], elapsedTime: 0
    ))
    // the current song belongs to the other account's syncer
    XCTAssertNil(PlayQueueSyncer.createSnapshot(
      account: account, current: song("x", account: otherAccount), prev: [song("p1")], user: [],
      next: [], elapsedTime: 0
    ))
    let radio = library.createRadio(account: account)
    XCTAssertNil(PlayQueueSyncer.createSnapshot(
      account: account, current: radio, prev: [song("p1")], user: [], next: [], elapsedTime: 0
    ))
  }
}
