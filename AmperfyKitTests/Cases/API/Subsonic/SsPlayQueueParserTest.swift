//
//  SsPlayQueueParserTest.swift
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

class SsPlayQueueParserTest: AbstractSsParserTest {
  override func setUp() async throws {
    try await super.setUp()
    xmlData = getTestFileData(name: "playQueue_example_1")
  }

  override func createParserDelegate() {
    let prefetch = library.getElements(
      account: account,
      prefetchIDs: ssIdParserDelegate.prefetchIDs
    )
    ssParserDelegate = SsPlayQueueParserDelegate(
      performanceMonitor: MOCK_PerformanceMonitor(), prefetch: prefetch, account: account,
      library: library
    )
  }

  override func checkCorrectParsing() {
    guard let parserDelegate = ssParserDelegate as? SsPlayQueueParserDelegate else {
      XCTFail(); return
    }
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    XCTAssertEqual(
      parserDelegate.playQueueInfo,
      ServerPlayQueueInfo(
        currentId: "2wBfZhWsUl8yOsRrxxiMEU",
        positionInMs: 83456,
        changed: dateFormatter.date(from: "2026-10-28T09:14:02.123Z"),
        changedBy: "Amperfy (iPhone)"
      )
    )

    // queue order is kept, a song queued twice is the same song
    XCTAssertEqual(
      parserDelegate.parsedSongs.map { $0.id },
      [
        "7xLtzsvcRhn0Fv7DVHCmZY",
        "2wBfZhWsUl8yOsRrxxiMEU",
        "32vINxMkCa26bYO0OQnueB",
        "7xLtzsvcRhn0Fv7DVHCmZY",
      ]
    )
    XCTAssertEqual(library.getSongs(for: account).count, 3)
    XCTAssertEqual(parserDelegate.parsedSongs[1].title, "Second Song")
    XCTAssertEqual(parserDelegate.parsedSongs[1].duration, 248)
    XCTAssertEqual(parserDelegate.parsedSongs[2].artist?.name, "Other Artist")

    let playQueue = ServerPlayQueue(
      info: parserDelegate.playQueueInfo!,
      songs: parserDelegate.parsedSongs
    )
    XCTAssertEqual(playQueue.startIndex, 1)
    XCTAssertEqual(playQueue.startPositionInSeconds, 83.456, accuracy: 0.0001)
  }

  func testInfoParsingLeavesLibraryUntouched() {
    let parserDelegate =
      SsPlayQueueInfoParserDelegate(performanceMonitor: MOCK_PerformanceMonitor())
    let parser = XMLParser(data: xmlData!)
    parser.delegate = parserDelegate
    parser.parse()

    XCTAssertNil(parserDelegate.error)
    XCTAssertEqual(parserDelegate.playQueueInfo?.currentId, "2wBfZhWsUl8yOsRrxxiMEU")
    XCTAssertEqual(parserDelegate.playQueueInfo?.positionInMs, 83456)
    XCTAssertEqual(parserDelegate.playQueueInfo?.changedBy, "Amperfy (iPhone)")
    XCTAssertTrue(library.getSongs(for: account).isEmpty)
  }

  func testParsingWithoutSavedQueue() {
    let data = Data("""
    <subsonic-response xmlns="http://subsonic.org/restapi" status="ok" version="1.16.1"/>
    """.utf8)
    let parserDelegate =
      SsPlayQueueInfoParserDelegate(performanceMonitor: MOCK_PerformanceMonitor())
    let parser = XMLParser(data: data)
    parser.delegate = parserDelegate
    parser.parse()

    XCTAssertNil(parserDelegate.error)
    XCTAssertNil(parserDelegate.playQueueInfo)
  }

  func testParsingNotFoundError() {
    let data = Data("""
    <subsonic-response status="failed" version="1.16.1">
      <error code="70" message="No play queue saved"/>
    </subsonic-response>
    """.utf8)
    let parserDelegate =
      SsPlayQueueInfoParserDelegate(performanceMonitor: MOCK_PerformanceMonitor())
    let parser = XMLParser(data: data)
    parser.delegate = parserDelegate
    parser.parse()

    XCTAssertEqual(parserDelegate.error?.subsonicError, .requestedDataNotFound)
    XCTAssertNil(parserDelegate.playQueueInfo)
  }

  func testInfoWithoutCurrentSong() {
    let info = ServerPlayQueueInfo(attributes: ["current": "", "position": "1500.0"])
    XCTAssertNil(info.currentId)
    XCTAssertEqual(info.positionInMs, 1500)
    XCTAssertNil(info.changed)
    XCTAssertNil(info.changedBy)
  }

  func testInfoChangedWithoutFractionalSeconds() {
    let info = ServerPlayQueueInfo(attributes: ["changed": "2015-02-18T20:24:25Z"])
    XCTAssertEqual(info.changed, ISO8601DateFormatter().date(from: "2015-02-18T20:24:25Z"))
  }
}
