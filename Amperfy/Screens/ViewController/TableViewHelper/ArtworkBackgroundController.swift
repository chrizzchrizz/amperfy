//
//  ArtworkBackgroundController.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 11.10.26.
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

import AmperfyKit
import UIKit

// MARK: - ArtworkBackgroundController

/// Colors a table screen (background, header, cells, search field, navigation bar) with the main color of an artwork.
/// The owning screen forwards its lifecycle events and passes `contentColor` to its cells.
@MainActor
final class ArtworkBackgroundController {
  private unowned let owner: BasicTableViewController
  private let account: Account
  private let detailHeader: () -> GenericDetailTableHeader?
  private let imagePath: (ArtworkDisplayPreference) -> String?

  private(set) var contentColor: UIColor?
  private var navigationBarStyle: UIUserInterfaceStyle = .unspecified

  private static let mainColorCache = NSCache<NSString, UIColor>()

  init(
    owner: BasicTableViewController,
    account: Account,
    detailHeader: @escaping () -> GenericDetailTableHeader?,
    imagePath: @escaping (ArtworkDisplayPreference) -> String?
  ) {
    self.owner = owner
    self.account = account
    self.detailHeader = detailHeader
    self.imagePath = imagePath
  }

  /// Title, back button and bar buttons follow the artwork background while the screen is visible.
  func applyNavigationBarStyle() {
    owner.navigationController?.navigationBar.overrideUserInterfaceStyle = navigationBarStyle
  }

  /// The navigation bar is shared with other screens.
  func resetNavigationBarStyle() {
    owner.navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
  }

  func update(animated: Bool? = nil) {
    let artworkDisplayPreference = owner.appDelegate.storage.settings.accounts
      .getSetting(account.info).read.artworkDisplayPreference
    guard let imagePath = imagePath(artworkDisplayPreference) else { return }

    let isDarkMode = owner.traitCollection.userInterfaceStyle == .dark
    let cacheKey = (imagePath + (isDarkMode ? "|dark" : "|light")) as NSString
    if let cached = Self.mainColorCache.object(forKey: cacheKey) {
      applyBackground(color: cached, animated: animated ?? false)
      return
    }
    Task { @MainActor in
      let color = await Self.loadMainColor(imagePath: imagePath, forDarkBackground: isDarkMode)
      guard let color else { return }
      Self.mainColorCache.setObject(color, forKey: cacheKey)
      // only fade in if the user already sees the screen
      self.applyBackground(color: color, animated: animated ?? (self.owner.view.window != nil))
    }
  }

  private func applyBackground(color: UIColor, animated: Bool) {
    // the color is already chosen for the current interface style
    let backgroundColor = color
    // dark style renders labels, separators and cells white, light style black
    let prefersDarkContent = backgroundColor.prefersDarkContent
    let tableView: UITableView = owner.tableView
    let contentColor: UIColor = prefersDarkContent ? .black : .white
    self.contentColor = contentColor

    tableView.overrideUserInterfaceStyle = prefersDarkContent ? .light : .dark
    tableView.separatorColor = contentColor.withAlphaComponent(0.3)
    if let header = detailHeader() {
      header.subtitleLabel.textColor = contentColor
      header.playShuffleInfoView?.applyContentColors(forBackground: backgroundColor)
      header.applyContentColor(contentColor)
      header.enableCoverShadow()
    }
    applySearchBarColors(contentColor: contentColor, prefersDarkContent: prefersDarkContent)
    for case let cell as PlayableTableCell in tableView.visibleCells {
      cell.contentColorOverride = contentColor
      cell.refresh()
      cell.setNeedsLayout() // cells drawing their own separators pick up the new separatorColor
    }
    navigationBarStyle = prefersDarkContent ? .light : .dark
    applyNavigationBarStyle()
    let update = { tableView.backgroundColor = backgroundColor }
    if animated {
      UIView.animate(withDuration: 0.2, animations: update)
    } else {
      update()
    }
  }

  /// Search field text, placeholder, icon and fill follow the artwork background.
  private func applySearchBarColors(contentColor: UIColor, prefersDarkContent: Bool) {
    let searchBar = owner.searchController.searchBar
    searchBar.overrideUserInterfaceStyle = prefersDarkContent ? .light : .dark
    searchBar.tintColor = contentColor
    let textField = searchBar.searchTextField
    textField.textColor = contentColor
    textField.backgroundColor = contentColor.withAlphaComponent(0.12)
    textField.leftView?.tintColor = contentColor.withAlphaComponent(0.6)
    textField.attributedPlaceholder = NSAttributedString(
      string: searchBar.placeholder ?? "",
      attributes: [.foregroundColor: contentColor.withAlphaComponent(0.6)]
    )
  }

  @concurrent
  private static func loadMainColor(imagePath: String, forDarkBackground: Bool) async -> UIColor? {
    UIImage(contentsOfFile: imagePath)?.mainColor(forDarkBackground: forDarkBackground)
  }
}
