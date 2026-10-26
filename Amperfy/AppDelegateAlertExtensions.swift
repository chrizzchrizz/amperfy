//
//  AppDelegateAlertExtensions.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 13.10.21.
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

import AmperfyKit
import Foundation
import OSLog
import UIKit

extension AppDelegate {
  static var mainSceneDelegate: SceneDelegate? {
    UIApplication.shared.connectedScenes
      // only scenes that are attached
      .filter { $0.activationState.rawValue >= 0 }
      // sort order: foregroundActive < foregroundInactive < background
      // this places the active tab first
      .sorted { $0.activationState.rawValue < $1.activationState.rawValue }
      // only "main" scene delegates
      .compactMap { $0.delegate as? SceneDelegate }.first
  }

  public func closeAllButActiveMainTabs() {
    var allMainScenes = UIApplication.shared.connectedScenes
      // only scenes that are attached
      .filter { $0.activationState.rawValue >= 0 }
      // sort order: foregroundActive < foregroundInactive < background
      // this places the active tab first
      .sorted { $0.activationState.rawValue < $1.activationState.rawValue }
      // only "main" scene delegates
      .filter { $0.delegate is SceneDelegate }
    if !allMainScenes.isEmpty {
      allMainScenes.removeFirst()
    }
    for scene in allMainScenes {
      terminateScene(scene)
    }
  }

  private func terminateScene(_ scene: UIScene) {
    UIApplication.shared.requestSceneSessionDestruction(
      scene.session,
      options: nil,
      errorHandler: { error in
        os_log(
          "AppDelegate: terminateScene failed: %s",
          log: self.log,
          type: .info,
          error.localizedDescription
        )
      }
    )
  }

  static var window: UIWindow? {
    mainSceneDelegate?.window
  }

  static func rootViewController() -> UIViewController? {
    Self.window?.rootViewController
  }

  static func topViewController(
    base: UIViewController? =
      window?.rootViewController
  )
    -> UIViewController? {
    if base?.presentedViewController is UIAlertController {
      return base
    }
    if let nav = base as? UINavigationController {
      return topViewController(base: nav.visibleViewController)
    }
    if let tab = base as? TabBarVC {
      return tab
    }
    if let splitVC = base as? SplitVC {
      return splitVC
    }
    if let presented = base?.presentedViewController {
      return topViewController(base: presented)
    }
    return base
  }

  static var mainWindowHostVC: MainSceneHostingViewController? {
    guard let topView = Self.topViewController(),
          (UIApplication.shared.delegate as! AppDelegate).storage.settings.app.isLibrarySynced
    else { return nil }
    return AppStoryboard.Main.checkForMainWindow(vc: topView)
  }
}

// MARK: - AppDelegate + AlertDisplayable

extension AppDelegate: AlertDisplayable {
  func display(
    title: String,
    subtitle: String,
    style: LogEntryType,
    notificationBanner popupVC: UIViewController
  ) {
    guard !ToastView.isVisible,
          let topView = Self.topViewController(),
          topView.presentedViewController == nil,
          let window = Self.window
    else { return }

    ToastView.show(
      title: title,
      subtitle: subtitle,
      style: style,
      in: window,
      placement: Self.toastPlacement(in: window, host: topView)
    ) {
      guard let topView = Self.topViewController(),
            topView.presentedViewController == nil
      else { return }
      topView.present(popupVC, animated: true, completion: nil)
    }
  }

  /// The toast floats above the mini player if it is shown, otherwise above the tab bar or the
  /// bottom safe area. With a split view it is centered on the content column next to the sidebar.
  private static func toastPlacement(in window: UIWindow, host: UIViewController) -> ToastPlacement {
    ToastPlacement(
      centerX: toastCenterX(in: window, host: host),
      bottomEdge: toastBottomEdge(in: window, host: host)
    )
  }

  private static func toastCenterX(in window: UIWindow, host: UIViewController) -> CGFloat {
    guard let contentView = (host as? SplitVC)?.viewController(for: .secondary)?.view,
          contentView.window === window else { return window.bounds.midX }
    let frame = contentView.convert(contentView.bounds, to: window)
    return frame.isEmpty ? window.bounds.midX : frame.midX
  }

  private static func toastBottomEdge(in window: UIWindow, host: UIViewController) -> CGFloat {
    let safeBottom = window.bounds.maxY - window.safeAreaInsets.bottom
    // frames in the upper half belong to a top tab bar (iPad), not to a bottom bar
    func lowerEdge(of view: UIView) -> CGFloat? {
      guard view.window === window, !view.isHidden, view.alpha > 0.01 else { return nil }
      let frame = view.convert(view.bounds, to: window)
      guard !frame.isEmpty, frame.minY > window.bounds.midY else { return nil }
      return frame.minY
    }

    let miniPlayer = (host as? TabBarVC)?.miniPlayer ?? (host as? SplitVC)?.miniPlayer
    if let miniPlayer, miniPlayer.isPlayableLoaded,
       let edge = lowerEdge(of: miniPlayer.glassContainer) {
      return edge
    }
    if let tabBar = (host as? TabBarVC)?.tabBar, let edge = lowerEdge(of: tabBar) {
      return edge
    }
    return safeBottom
  }

  func display(popup popupVC: UIViewController) {
    guard let topView = Self.topViewController(),
          topView.presentedViewController == nil
    else { return }
    popupVC.modalPresentationStyle = .overCurrentContext
    popupVC.modalTransitionStyle = .crossDissolve
    topView.present(popupVC, animated: true, completion: nil)
  }

  func createPopupVC(
    topic: String,
    shortMessage: String,
    detailMessage: String,
    logType: LogEntryType
  )
    -> UIViewController {
    let popupVC = NotificationDetailVC()
    popupVC.display(title: topic, message: detailMessage, type: logType)
    return popupVC
  }
}
