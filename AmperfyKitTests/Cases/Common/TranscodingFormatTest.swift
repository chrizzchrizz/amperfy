//
//  TranscodingFormatTest.swift
//  AmperfyKitTests
//
//  Created by Maximilian Bauer on 19.10.26.
//  Copyright (c) 2026 Maximilian Bauer. All rights reserved.
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

class TranscodingFormatTest: XCTestCase {
  func testStreamingAutoPlayableFormat() {
    for contentType in ["audio/mpeg", "audio/flac", "audio/x-flac", "audio/mp4", "audio/m4a"] {
      XCTAssertEqual(
        StreamingFormatPreference.auto.resolved(
          contentType: contentType,
          bitrate: 900_000,
          maxBitrate: .noLimit
        ),
        .raw,
        contentType
      )
    }
  }

  func testStreamingAutoUnsupportedFormat() {
    for contentType in [nil, "audio/x-ms-wma", "audio/ogg", "application/octet-stream"] {
      XCTAssertEqual(
        StreamingFormatPreference.auto.resolved(
          contentType: contentType,
          bitrate: 128_000,
          maxBitrate: .noLimit
        ),
        .mp3
      )
    }
  }

  func testStreamingAutoBitrateLimit() {
    XCTAssertEqual(
      StreamingFormatPreference.auto.resolved(
        contentType: "audio/mpeg",
        bitrate: 128_000,
        maxBitrate: .limit192
      ),
      .raw
    )
    XCTAssertEqual(
      StreamingFormatPreference.auto.resolved(
        contentType: "audio/flac",
        bitrate: 900_000,
        maxBitrate: .limit192
      ),
      .mp3
    )
    XCTAssertEqual(
      StreamingFormatPreference.auto.resolved(
        contentType: "audio/mpeg",
        bitrate: 0,
        maxBitrate: .limit192
      ),
      .mp3
    )
  }

  func testStreamingExplicitFormatUnchanged() {
    for format in [StreamingFormatPreference.mp3, .raw, .serverConfig] {
      XCTAssertEqual(
        format.resolved(contentType: "audio/x-ms-wma", bitrate: 0, maxBitrate: .limit64),
        format
      )
    }
  }

  func testCacheAuto() {
    XCTAssertEqual(CacheTranscodingFormatPreference.auto.resolved(contentType: "audio/flac"), .raw)
    XCTAssertEqual(
      CacheTranscodingFormatPreference.auto.resolved(contentType: "audio/x-ms-wma"),
      .mp3
    )
    XCTAssertEqual(CacheTranscodingFormatPreference.mp3.resolved(contentType: "audio/flac"), .mp3)
    XCTAssertEqual(
      CacheTranscodingFormatPreference.serverConfig.resolved(contentType: "audio/flac"),
      .serverConfig
    )
  }
}
