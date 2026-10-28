//
//  PlayQueueSnapshotTest.swift
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

class PlayQueueSnapshotTest: XCTestCase {
  private func ids(_ range: Range<Int>) -> [String] {
    range.map { "id\($0)" }
  }

  func testMillisecondsFromSeconds() {
    XCTAssertEqual(PlayQueueSnapshot.milliseconds(fromSeconds: 83.456), 83456)
    XCTAssertEqual(PlayQueueSnapshot.milliseconds(fromSeconds: 0.0004), 0)
    XCTAssertEqual(PlayQueueSnapshot.milliseconds(fromSeconds: 0.0006), 1)
    XCTAssertEqual(PlayQueueSnapshot.milliseconds(fromSeconds: 0), 0)
    XCTAssertEqual(PlayQueueSnapshot.milliseconds(fromSeconds: -3), 0)
    XCTAssertEqual(PlayQueueSnapshot.milliseconds(fromSeconds: .nan), 0)
    XCTAssertEqual(PlayQueueSnapshot.milliseconds(fromSeconds: .infinity), 0)
  }

  func testSecondsFromMilliseconds() {
    XCTAssertEqual(PlayQueueSnapshot.seconds(fromMilliseconds: 83456), 83.456, accuracy: 0.0001)
    XCTAssertEqual(PlayQueueSnapshot.seconds(fromMilliseconds: 0), 0)
    XCTAssertEqual(PlayQueueSnapshot.seconds(fromMilliseconds: -10), 0)
  }

  func testCurrentId() {
    XCTAssertEqual(
      PlayQueueSnapshot(songIds: ids(0 ..< 3), currentIndex: 2, positionInMs: 0).currentId,
      "id2"
    )
    XCTAssertNil(
      PlayQueueSnapshot(songIds: ids(0 ..< 3), currentIndex: nil, positionInMs: 0)
        .currentId
    )
    XCTAssertNil(
      PlayQueueSnapshot(songIds: ids(0 ..< 3), currentIndex: 3, positionInMs: 0)
        .currentId
    )
    XCTAssertNil(PlayQueueSnapshot(songIds: [], currentIndex: 0, positionInMs: 0).currentId)
  }

  func testLimitedKeepsShortQueue() {
    let snapshot = PlayQueueSnapshot(songIds: ids(0 ..< 10), currentIndex: 4, positionInMs: 7)
    XCTAssertEqual(snapshot.limited(to: 10), snapshot)
    XCTAssertEqual(snapshot.limited(to: 200), snapshot)
  }

  func testLimitedNearStart() {
    let snapshot = PlayQueueSnapshot(songIds: ids(0 ..< 500), currentIndex: 10, positionInMs: 7)
    let limited = snapshot.limited(to: 200)
    XCTAssertEqual(limited.songIds, ids(0 ..< 200))
    XCTAssertEqual(limited.currentId, "id10")
    XCTAssertEqual(limited.positionInMs, 7)
  }

  func testLimitedInTheMiddle() {
    let snapshot = PlayQueueSnapshot(songIds: ids(0 ..< 500), currentIndex: 250, positionInMs: 0)
    let limited = snapshot.limited(to: 200)
    // a quarter of the songs before the current one, the rest after it
    XCTAssertEqual(limited.songIds, ids(200 ..< 400))
    XCTAssertEqual(limited.currentIndex, 50)
    XCTAssertEqual(limited.currentId, "id250")
  }

  func testLimitedNearEnd() {
    let snapshot = PlayQueueSnapshot(songIds: ids(0 ..< 500), currentIndex: 490, positionInMs: 0)
    let limited = snapshot.limited(to: 200)
    XCTAssertEqual(limited.songIds, ids(300 ..< 500))
    XCTAssertEqual(limited.currentId, "id490")
  }

  func testLimitedWithoutCurrent() {
    let snapshot = PlayQueueSnapshot(songIds: ids(0 ..< 500), currentIndex: nil, positionInMs: 0)
    let limited = snapshot.limited(to: 200)
    XCTAssertEqual(limited.songIds, ids(0 ..< 200))
    XCTAssertNil(limited.currentIndex)
  }

  func testStartIndex() {
    let songIds = ["a", "b", "c", "b"]
    XCTAssertEqual(ServerPlayQueue.startIndex(songIds: songIds, currentId: "c"), 2)
    // a song queued twice starts at its first occurrence
    XCTAssertEqual(ServerPlayQueue.startIndex(songIds: songIds, currentId: "b"), 1)
    // the server no longer has the current song
    XCTAssertEqual(ServerPlayQueue.startIndex(songIds: songIds, currentId: "x"), 0)
    XCTAssertEqual(ServerPlayQueue.startIndex(songIds: songIds, currentId: nil), 0)
    XCTAssertEqual(ServerPlayQueue.startIndex(songIds: [], currentId: "a"), 0)
  }

  func testIsCurrentAvailable() {
    XCTAssertTrue(ServerPlayQueue.isCurrentAvailable(songIds: ["a", "b"], currentId: "b"))
    XCTAssertFalse(ServerPlayQueue.isCurrentAvailable(songIds: ["a", "b"], currentId: "x"))
    XCTAssertFalse(ServerPlayQueue.isCurrentAvailable(songIds: ["a", "b"], currentId: nil))
  }
}
