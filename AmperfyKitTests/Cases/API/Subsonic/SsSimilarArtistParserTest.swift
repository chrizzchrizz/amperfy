//
//  SsSimilarArtistParserTest.swift
//  AmperfyKitTests
//
//  Created by Chrizz Gelbach on 15.10.26.
//  Copyright (c) 2025 Chrizz Gelbach. All rights reserved.
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

@testable import AmperfyKit
import XCTest

class SsSimilarArtistParserTest: XCTestCase {
  func testParsingSkipsArtistsNotInLibrary() {
    let parserDelegate = SsSimilarArtistParserDelegate(
      performanceMonitor: MOCK_PerformanceMonitor()
    )
    let parser = XMLParser(data: getTestFileData(name: "artistInfo2_example_1"))
    parser.delegate = parserDelegate
    parser.parse()

    XCTAssertNil(parserDelegate.error)
    XCTAssertEqual(
      parserDelegate.artistIDs,
      ["2wBfZhWsUl8yOsRrxxiMEU", "32vINxMkCa26bYO0OQnueB", "77sZUX04Hl1n2D5XV4xb63"]
    )
  }

  func testParsingErrorResponse() {
    let data = Data("""
    <subsonic-response status="failed" version="1.16.1">
      <error code="70" message="Artist not found"/>
    </subsonic-response>
    """.utf8)
    let parserDelegate = SsSimilarArtistParserDelegate(
      performanceMonitor: MOCK_PerformanceMonitor()
    )
    let parser = XMLParser(data: data)
    parser.delegate = parserDelegate
    parser.parse()

    XCTAssertNotNil(parserDelegate.error)
    XCTAssertTrue(parserDelegate.artistIDs.isEmpty)
  }
}
