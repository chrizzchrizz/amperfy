//
//  PlayQueueSyncer.swift
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

import CoreMedia
import Foundation
import os.log
import UIKit

// MARK: - PlayQueueSaveThrottle

/// Decides when the play queue is saved and when the server is asked whether another device took over.
struct PlayQueueSaveThrottle {
  /// While playing, the position is saved at most this often.
  static let periodicSaveInterval: TimeInterval = 30
  /// A smaller change of the position alone is not saved.
  static let positionToleranceInMs = 5000
  /// How often the server is asked whether another device saved its queue.
  static let takeoverCheckInterval: TimeInterval = 120
  /// After playback was started on this device, a queue saved by another device is ignored for this
  /// long, so the other device detects the takeover first and stops saving, instead of both stopping.
  static let takeoverGracePeriod: TimeInterval = 180

  private(set) var lastSaved: PlayQueueSnapshot?
  private(set) var lastSaveDate: Date?
  private var lastTakeoverCheckDate: Date?
  private var ignoreOtherDevicesUntil: Date?

  func isPeriodicSaveDue(now: Date) -> Bool {
    guard let lastSaveDate else { return true }
    return now.timeIntervalSince(lastSaveDate) >= Self.periodicSaveInterval
  }

  func isSaveNeeded(for snapshot: PlayQueueSnapshot) -> Bool {
    guard let lastSaved else { return true }
    return snapshot.songIds != lastSaved.songIds ||
      snapshot.currentIndex != lastSaved.currentIndex ||
      abs(snapshot.positionInMs - lastSaved.positionInMs) >= Self.positionToleranceInMs
  }

  mutating func didSave(_ snapshot: PlayQueueSnapshot, now: Date) {
    lastSaved = snapshot
    lastSaveDate = now
  }

  /// A failed save is retried with the next periodic save, not on every elapsed time change.
  mutating func didFailToSave(now: Date) {
    lastSaveDate = now
  }

  /// True if the server should be asked now; marks the check as done.
  mutating func shouldCheckForTakeover(now: Date) -> Bool {
    if let ignoreOtherDevicesUntil, now < ignoreOtherDevicesUntil { return false }
    if let lastTakeoverCheckDate,
       now.timeIntervalSince(lastTakeoverCheckDate) < Self.takeoverCheckInterval {
      return false
    }
    lastTakeoverCheckDate = now
    return true
  }

  /// Playback was started on this device by the user.
  mutating func didStartLocally(now: Date) {
    ignoreOtherDevicesUntil = now.addingTimeInterval(Self.takeoverGracePeriod)
    lastSaved = nil
  }

  /// The queue on the server was saved by another device if its client name differs.
  /// Two devices of the same type share their client name and can't be told apart.
  static func isSavedByOtherDevice(_ info: ServerPlayQueueInfo, ownClientName: String) -> Bool {
    guard let changedBy = info.changedBy, !changedBy.isEmpty else { return false }
    return changedBy != ownClientName
  }
}

// MARK: - PlayQueueSyncer

/// Saves the music play queue of the account to the server, so another device can continue
/// playback, and continues playback of the queue another device saved.
///
/// Conflicts: the last save wins. Once another device saved its queue, this device stops saving
/// until playback is started here again, so a device that keeps playing after the takeover doesn't
/// overwrite the queue of the device that took over.
@MainActor
public class PlayQueueSyncer {
  private static let songChangeSaveDelay: Duration = .seconds(2)
  private static let queueChangeSaveDelay: Duration = .seconds(5)

  public static var clientName: String {
    #if targetEnvironment(macCatalyst)
      return "Amperfy (Mac)"
    #else
      return "Amperfy (\(UIDevice.current.model))"
    #endif
  }

  private let log = OSLog(subsystem: "Amperfy", category: "PlayQueueSyncer")
  private let player: PlayerFacade
  private let networkMonitor: NetworkMonitorFacade
  private let account: Account
  private let storage: PersistentStorage
  private let librarySyncer: LibrarySyncer
  private let eventLogger: EventLogger

  private var throttle = PlayQueueSaveThrottle()
  private var isSupported: Bool?
  /// Another device saved its queue after this one, saving is stopped until playback starts here.
  private var isTakenOverByOtherDevice = false
  private var isPlaybackInterrupted = true
  private var scheduledSave: Task<(), Never>?
  private var isSaving = false
  private var isAnotherSaveRequested = false

  init(
    player: PlayerFacade,
    networkMonitor: NetworkMonitorFacade,
    account: Account,
    storage: PersistentStorage,
    librarySyncer: LibrarySyncer,
    eventLogger: EventLogger
  ) {
    self.player = player
    self.networkMonitor = networkMonitor
    self.account = account
    self.storage = storage
    self.librarySyncer = librarySyncer
    self.eventLogger = eventLogger
  }

  private var isSyncActive: Bool {
    storage.settings.user.isPlayQueueSyncEnabled && storage.settings.user.isOnlineMode &&
      networkMonitor.isConnectedToNetwork
  }

  public func isContinuePlaybackAvailable() async -> Bool {
    guard storage.settings.user.isPlayQueueSyncEnabled else { return false }
    return await isServerSupportingSync()
  }

  private func isServerSupportingSync() async -> Bool {
    if let isSupported { return isSupported }
    let supported = await librarySyncer.isPlayQueueSyncSupported()
    isSupported = supported
    return supported
  }

  // MARK: Save

  /// Saves the queue right away, e.g. before the app moves to the background.
  public func saveNow() async {
    scheduledSave?.cancel()
    scheduledSave = nil
    await save()
  }

  private func scheduleSave(after delay: Duration) {
    guard isSyncActive, !isTakenOverByOtherDevice, isSupported != false else { return }
    scheduledSave?.cancel()
    scheduledSave = Task { @MainActor [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, let self else { return }
      scheduledSave = nil
      await save()
    }
  }

  private func save() async {
    guard isSyncActive, !isTakenOverByOtherDevice else { return }
    guard !isSaving else {
      isAnotherSaveRequested = true
      return
    }
    isSaving = true
    defer { isSaving = false }
    repeat {
      isAnotherSaveRequested = false
      await saveIfNeeded()
    } while isAnotherSaveRequested && !isTakenOverByOtherDevice
  }

  private func saveIfNeeded() async {
    guard await isServerSupportingSync(), let snapshot = createSnapshot(),
          throttle.isSaveNeeded(for: snapshot)
    else { return }
    do {
      if throttle.shouldCheckForTakeover(now: Date()),
         let info = try await librarySyncer.requestPlayQueueInfo(),
         PlayQueueSaveThrottle.isSavedByOtherDevice(info, ownClientName: Self.clientName) {
        os_log(
          "Play queue saved by %s, stop saving until playback starts here",
          log: log,
          type: .info,
          info.changedBy ?? "-"
        )
        isTakenOverByOtherDevice = true
        return
      }
      try await librarySyncer.savePlayQueue(snapshot: snapshot, clientName: Self.clientName)
      throttle.didSave(snapshot, now: Date())
    } catch {
      throttle.didFailToSave(now: Date())
      eventLogger.report(topic: "Play Queue Sync", error: error, displayPopup: false)
    }
  }

  private func createSnapshot() -> PlayQueueSnapshot? {
    guard player.playerMode == .music else { return nil }
    return Self.createSnapshot(
      account: account,
      current: player.currentMusicItem,
      prev: player.getAllPrevQueueItems(),
      user: player.getAllUserQueueItems(),
      next: player.getAllNextQueueItems(),
      elapsedTime: player.elapsedTime
    )
  }

  /// Songs of the account in playback order, radios and songs of other accounts are left out;
  /// nil if the current item isn't a song of the account.
  static func createSnapshot(
    account: Account,
    current: AbstractPlayable?,
    prev: [AbstractPlayable],
    user: [AbstractPlayable],
    next: [AbstractPlayable],
    elapsedTime: Double
  )
    -> PlayQueueSnapshot? {
    guard let currentSong = current?.asSong, currentSong.account == account else { return nil }
    let accountSongIds: ([AbstractPlayable]) -> [String] = { playables in
      playables.compactMap { $0.asSong }.filter { $0.account == account }.map { $0.id }
    }
    let prevIds = accountSongIds(prev)
    return PlayQueueSnapshot(
      songIds: prevIds + [currentSong.id] + accountSongIds(user) + accountSongIds(next),
      currentIndex: prevIds.count,
      positionInMs: PlayQueueSnapshot.milliseconds(fromSeconds: elapsedTime)
    )
  }

  /// The user started playback on this device, it is the active one again.
  private func didStartLocally() {
    isTakenOverByOtherDevice = false
    throttle.didStartLocally(now: Date())
  }

  // MARK: Continue Playback

  /// The queue another device saved; nil if the server has none.
  public func requestServerPlayQueue() async throws -> ServerPlayQueue? {
    try await librarySyncer.requestPlayQueue()
  }

  /// Replaces the player's queue with the saved one and plays it from the saved position.
  public func continuePlayback(of playQueue: ServerPlayQueue) {
    guard !playQueue.songs.isEmpty else { return }
    os_log(
      "Continue playback of the play queue of %s: %i songs",
      log: log,
      type: .info,
      playQueue.info.changedBy ?? "-",
      playQueue.songs.count
    )
    didStartLocally()
    player.play(
      context: PlayContext(
        name: "Continued Playback",
        index: playQueue.startIndex,
        playables: playQueue.songs
      ),
      startSecond: playQueue.startPositionInSeconds
    )
    // the pause before the context starts schedules a save, the position isn't applied by then;
    // the save after the song started has it
    scheduledSave?.cancel()
    scheduledSave = nil
  }
}

// MARK: MusicPlayable

extension PlayQueueSyncer: MusicPlayable {
  public func didStartPlayingFromBeginning() {
    scheduleSave(after: Self.songChangeSaveDelay)
  }

  public func didStartPlaying() {
    // also called for every song that follows, only a start after a pause or stop is the user's
    if isPlaybackInterrupted {
      isPlaybackInterrupted = false
      didStartLocally()
      scheduleSave(after: Self.songChangeSaveDelay)
    }
  }

  public func didPause() {
    isPlaybackInterrupted = true
    scheduleSave(after: .zero)
  }

  public func didStopPlaying() {
    isPlaybackInterrupted = true
    scheduleSave(after: .zero)
  }

  public func didElapsedTimeChange() {
    // called several times per second, cheap checks first
    guard player.isPlaying, scheduledSave == nil, !isSaving,
          throttle.isPeriodicSaveDue(now: Date()),
          player.currentMusicItem?.asSong?.account == account
    else { return }
    scheduleSave(after: .zero)
  }

  public func didPlaylistChange() {
    scheduleSave(after: Self.queueChangeSaveDelay)
  }

  public func didArtworkChange() {}
  public func didShuffleChange() {}
  public func didRepeatChange() {}
  public func didPlaybackRateChange() {}
}
