//
//  PlayerDownloadPreparationHandler.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 25.11.21.
//  Copyright (c) 2021 Maximilian Bauer. All rights reserved.
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

// MARK: - PlayerDownloadPreparationHandler

/// Caches the current and upcoming items of the player.
/// Only one item is requested at a time so the downloads do not compete with each other
/// (and with a streamed item) for bandwidth on slow connections.
@MainActor
public class PlayerDownloadPreparationHandler: NSObject {
  static public let preDownloadCount = 3

  private var playerStatus: PlayerStatusPersistent
  private var queueHandler: PlayQueueHandler
  private var getPlayableDownloaderCB: GetPlayableDownloadManagerCallback
  /// Item whose download has been requested and has not finished yet
  private var requestedPlayable: AbstractPlayable?
  /// Items whose download finished (successfully or not) since the current item started.
  /// Not requested again meanwhile, also if the main context does not show them as cached yet.
  private var finishedPlayableIDs = Set<String>()
  /// Queue changes trigger downloads only after playback has been started
  private var isPlaybackStarted = false

  init(
    playerStatus: PlayerStatusPersistent,
    queueHandler: PlayQueueHandler,
    notificationHandler: EventNotificationHandler,
    getPlayableDownloaderCB: @escaping GetPlayableDownloadManagerCallback
  ) {
    self.playerStatus = playerStatus
    self.queueHandler = queueHandler
    self.getPlayableDownloaderCB = getPlayableDownloaderCB
    super.init()
    notificationHandler.register(
      self,
      selector: #selector(downloadFinished(notification:)),
      name: .downloadFinishedSuccess,
      object: nil
    )
    notificationHandler.register(
      self,
      selector: #selector(downloadFinished(notification:)),
      name: .downloadFinishedFailure,
      object: nil
    )
  }

  /// Items to cache in the order they are needed: the next item first for a gapless transition,
  /// then the current item (in case it is streamed), then the remaining upcoming items
  private var playablesToCache: [AbstractPlayable] {
    var upcoming = [AbstractPlayable]()
    let userQueueRangeEnd = min(queueHandler.userQueueCount, Self.preDownloadCount)
    for i in 0 ..< userQueueRangeEnd {
      if let playable = queueHandler.getUserQueueItem(at: i) {
        upcoming.append(playable)
      }
    }
    let nextQueueRangeEnd = min(
      queueHandler.nextQueueCount,
      Self.preDownloadCount - userQueueRangeEnd
    )
    for i in 0 ..< nextQueueRangeEnd {
      if let playable = queueHandler.getNextQueueItem(at: i) {
        upcoming.append(playable)
      }
    }

    var playables = Array(upcoming.prefix(1))
    if let currentlyPlaying = queueHandler.currentlyPlaying {
      playables.append(currentlyPlaying)
    }
    playables.append(contentsOf: upcoming.dropFirst())
    return playables
  }

  private func downloadNextItem() {
    guard playerStatus.isAutoCachePlayedItems else { return }
    if let requestedPlayable, !requestedPlayable.isCached { return }
    requestedPlayable = nil

    guard let playable = playablesToCache.first(where: {
      !$0.isCached && $0.isDownloadAvailable && !finishedPlayableIDs.contains($0.uniqueID)
    }),
      let accountInfo = playable.account?.info
    else { return }
    requestedPlayable = playable
    getPlayableDownloaderCB(accountInfo).download(object: playable)
  }

  @objc
  private func downloadFinished(notification: Notification) {
    guard let downloadNotification = DownloadNotification.fromNotification(notification),
          let requestedPlayable,
          requestedPlayable.uniqueID == downloadNotification.id
    else { return }
    finishedPlayableIDs.insert(requestedPlayable.uniqueID)
    self.requestedPlayable = nil
    downloadNextItem()
  }
}

// MARK: MusicPlayable

extension PlayerDownloadPreparationHandler: MusicPlayable {
  public func didStartPlayingFromBeginning() {
    isPlaybackStarted = true
    finishedPlayableIDs.removeAll()
    // a request that is no longer needed (e.g. skipped) must not block the queue
    if let requestedPlayable, !playablesToCache.contains(requestedPlayable) {
      self.requestedPlayable = nil
    }
    downloadNextItem()
  }

  public func didPlaylistChange() {
    guard isPlaybackStarted else { return }
    downloadNextItem()
  }

  public func didStartPlaying() {}
  public func didPause() {}
  public func didStopPlaying() {
    isPlaybackStarted = false
  }

  public func didElapsedTimeChange() {}
  public func didArtworkChange() {}
  public func didPlaybackRateChange() {}
  public func didRepeatChange() {}

  public func didShuffleChange() {
    guard isPlaybackStarted else { return }
    downloadNextItem()
  }
}
