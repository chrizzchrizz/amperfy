//
//  AppDelegatePlayQueueSyncExtension.swift
//  Amperfy
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

import AmperfyKit
import Foundation
import UIKit

extension AppDelegate {
  private var activePlayQueueSyncer: PlayQueueSyncer? {
    guard let accountInfo = storage.settings.accounts.active else { return nil }
    return getMeta(accountInfo).activePlayQueueSyncer
  }

  /// Ampache has no play queue on the server; whether the Subsonic server supports it is only
  /// known after the first request, the action reports it then.
  var isContinuePlaybackAvailable: Bool {
    guard storage.settings.user.isPlayQueueSyncEnabled, storage.settings.user.isOnlineMode,
          let accountInfo = storage.settings.accounts.active
    else { return false }
    return storage.main.library.getAccount(info: accountInfo).apiType != .ampache
  }

  func createContinuePlaybackAction(presentingVC: UIViewController? = nil) -> UIAction {
    UIAction(title: "Continue Playback", image: .continuePlayback) { _ in
      self.continuePlaybackFromOtherDevice(presentingVC: presentingVC)
    }
  }

  /// Saves the play queue of all accounts before the app moves to the background.
  func savePlayQueueBeforeBackground() {
    guard storage.settings.user.isPlayQueueSyncEnabled else { return }
    let syncers = storage.settings.accounts.allAccounts.compactMap {
      getMeta($0).activePlayQueueSyncer
    }
    guard !syncers.isEmpty else { return }
    var backgroundTask = UIBackgroundTaskIdentifier.invalid
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save Play Queue") {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
    Task { @MainActor in
      for syncer in syncers {
        await syncer.saveNow()
      }
      guard backgroundTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }

  /// Loads the play queue another device saved and asks before it replaces the current queue.
  func continuePlaybackFromOtherDevice(presentingVC: UIViewController? = nil) {
    guard let syncer = activePlayQueueSyncer else { return }
    Task { @MainActor in
      guard await syncer.isContinuePlaybackAvailable() else {
        presentContinuePlaybackAlert(
          title: "Not Supported",
          message: "The server doesn't store a play queue.",
          presentingVC: presentingVC
        )
        return
      }
      do {
        guard let playQueue = try await syncer.requestServerPlayQueue(),
              !playQueue.songs.isEmpty
        else {
          presentContinuePlaybackAlert(
            title: "No Saved Play Queue",
            message: "No device has saved a play queue on the server yet.",
            presentingVC: presentingVC
          )
          return
        }
        presentContinuePlaybackConfirmation(
          playQueue: playQueue,
          syncer: syncer,
          presentingVC: presentingVC
        )
      } catch {
        eventLogger.report(topic: "Continue Playback", error: error, displayPopup: true)
      }
    }
  }

  private func presentContinuePlaybackConfirmation(
    playQueue: ServerPlayQueue,
    syncer: PlayQueueSyncer,
    presentingVC: UIViewController?
  ) {
    let startSong = playQueue.songs[playQueue.startIndex]
    var lines = [startSong.displayString]
    var savedBy = [String]()
    if let changedBy = playQueue.info.changedBy, !changedBy.isEmpty {
      savedBy.append(Self.deviceName(clientName: changedBy))
    }
    if let changed = playQueue.info.changed {
      let formatter = DateFormatter()
      formatter.dateStyle = .short
      formatter.timeStyle = .short
      formatter.doesRelativeDateFormatting = true
      savedBy.append(formatter.string(from: changed))
    }
    if !savedBy.isEmpty {
      lines.append(savedBy.joined(separator: " - "))
    }
    lines.append(playQueue.songs.count == 1 ? "1 Song" : "\(playQueue.songs.count) Songs")

    let alert = UIAlertController(
      title: "Continue Playback?",
      message: lines.joined(separator: "\n"),
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
      syncer.continuePlayback(of: playQueue)
    })
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(alert: alert, on: presentingVC)
  }

  /// "Amperfy (iPhone)" -> "iPhone", other clients are shown as they are.
  private static func deviceName(clientName: String) -> String {
    guard clientName.hasPrefix("Amperfy ("), clientName.hasSuffix(")") else { return clientName }
    return String(clientName.dropFirst("Amperfy (".count).dropLast())
  }

  private func presentContinuePlaybackAlert(
    title: String,
    message: String,
    presentingVC: UIViewController?
  ) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert: alert, on: presentingVC)
  }

  /// The view controller of the menu may be gone after the request.
  private func present(alert: UIAlertController, on presentingVC: UIViewController?) {
    if let presentingVC, presentingVC.viewIfLoaded?.window != nil,
       presentingVC.presentedViewController == nil {
      presentingVC.present(alert, animated: true)
    } else {
      Self.topViewController()?.present(alert, animated: true)
    }
  }
}
