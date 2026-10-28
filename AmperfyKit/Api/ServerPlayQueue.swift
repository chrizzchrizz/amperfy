//
//  ServerPlayQueue.swift
//  AmperfyKit
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

import Foundation

// MARK: - PlayQueueSnapshot

/// Play queue as it is saved to the server: songs in playback order, the current song and its position.
public struct PlayQueueSnapshot: Equatable, Sendable {
  public var songIds: [String]
  public var currentIndex: Int?
  public var positionInMs: Int

  public init(songIds: [String], currentIndex: Int?, positionInMs: Int) {
    self.songIds = songIds
    self.currentIndex = currentIndex
    self.positionInMs = positionInMs
  }

  public var currentId: String? {
    guard let currentIndex, songIds.indices.contains(currentIndex) else { return nil }
    return songIds[currentIndex]
  }

  /// Keeps at most `maxCount` songs around the current one, more of them after it than before.
  public func limited(to maxCount: Int) -> PlayQueueSnapshot {
    guard songIds.count > maxCount, maxCount > 0 else { return self }
    let current = currentIndex ?? 0
    let before = min(current, maxCount / 4)
    let start = min(current - before, songIds.count - maxCount)
    let ids = Array(songIds[start ..< start + maxCount])
    return PlayQueueSnapshot(
      songIds: ids,
      currentIndex: currentIndex.map { $0 - start },
      positionInMs: positionInMs
    )
  }

  public static func milliseconds(fromSeconds seconds: Double) -> Int {
    guard seconds.isFinite, seconds > 0 else { return 0 }
    return Int((seconds * 1000).rounded())
  }

  public static func seconds(fromMilliseconds milliseconds: Int) -> Double {
    Double(max(0, milliseconds)) / 1000
  }
}

// MARK: - ServerPlayQueueInfo

/// The attributes of the play queue saved on the server, without its songs.
public struct ServerPlayQueueInfo: Equatable, Sendable {
  public var currentId: String?
  public var positionInMs: Int
  public var changed: Date?
  /// Client name of the device that saved the queue.
  public var changedBy: String?

  public init(currentId: String?, positionInMs: Int, changed: Date?, changedBy: String?) {
    self.currentId = currentId
    self.positionInMs = positionInMs
    self.changed = changed
    self.changedBy = changedBy
  }

  init(attributes: [String: String]) {
    self.currentId = attributes["current"].flatMap { $0.isEmpty ? nil : $0 }
    // the position is a long, some servers send it with decimals
    self.positionInMs = attributes["position"].flatMap { Double($0) }.map { Int($0) } ?? 0
    self.changed = attributes["changed"].flatMap { Self.parseDate($0) }
    self.changedBy = attributes["changedBy"]
  }

  public var positionInSeconds: Double {
    PlayQueueSnapshot.seconds(fromMilliseconds: positionInMs)
  }

  private static func parseDate(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
  }
}

// MARK: - ServerPlayQueue

/// The play queue saved on the server with its songs. Songs the server no longer has are missing.
@MainActor
public struct ServerPlayQueue {
  public let info: ServerPlayQueueInfo
  public let songs: [Song]

  public init(info: ServerPlayQueueInfo, songs: [Song]) {
    self.info = info
    self.songs = songs
  }

  /// Index to start playback at: the current song, or the first song if the server no longer has it.
  /// With the current song more than once in the queue, its first occurrence is used, the queue only
  /// stores ids.
  public var startIndex: Int {
    Self.startIndex(songIds: songs.map { $0.id }, currentId: info.currentId)
  }

  /// The saved position only applies if the current song is still there.
  public var startPositionInSeconds: Double {
    Self.isCurrentAvailable(songIds: songs.map { $0.id }, currentId: info.currentId) ? info
      .positionInSeconds : 0
  }

  nonisolated static func startIndex(songIds: [String], currentId: String?) -> Int {
    guard let currentId, let index = songIds.firstIndex(of: currentId) else { return 0 }
    return index
  }

  nonisolated static func isCurrentAvailable(songIds: [String], currentId: String?) -> Bool {
    guard let currentId else { return false }
    return songIds.contains(currentId)
  }
}
