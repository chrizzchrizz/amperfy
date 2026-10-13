//
//  AlbumDetailVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 09.03.19.
//  Copyright (c) 2019 Maximilian Bauer. All rights reserved.
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

// MARK: - AlbumDetailDiffableDataSource

class AlbumDetailDiffableDataSource: BasicUITableViewDiffableDataSource {
  override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
    false
  }

  override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
    // Return true to be enable swipe
    true
  }
}

// MARK: - AlbumDetailVC

class AlbumDetailVC: SingleSnapshotFetchedResultsTableViewController<SongMO> {
  var songToScrollTo: Song?
  private var fetchedResultsController: AlbumSongsFetchedResultsController!
  private var optionsButton: UIBarButtonItem!
  private var detailOperationsView: GenericDetailTableHeader?
  private var contentColor: UIColor?
  private var navigationBarStyle: UIUserInterfaceStyle = .unspecified
  let album: Album

  init(account: Account, album: Album) {
    self.album = album
    super.init(style: .grouped, account: account)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func createDiffableDataSource() -> BasicUITableViewDiffableDataSource {
    let source =
      AlbumDetailDiffableDataSource(tableView: tableView) { tableView, indexPath, objectID -> UITableViewCell? in
        guard let object = try? self.appDelegate.storage.main.context
          .existingObject(with: objectID),
          let songMO = object as? SongMO
        else {
          fatalError("Managed object should be available")
        }
        let song = Song(managedObject: songMO)
        return self.createCell(tableView, forRowAt: indexPath, song: song)
      }
    return source
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    appDelegate.userStatistics.visited(.albumDetail)

    optionsButton = UIBarButtonItem.createOptionsBarButton()

    fetchedResultsController = AlbumSongsFetchedResultsController(
      forAlbum: album,
      coreDataCompanion: appDelegate.storage.main,
      isGroupedInAlphabeticSections: false
    )
    singleFetchedResultsController = fetchedResultsController
    singleFetchedResultsController?.delegate = self
    singleFetchedResultsController?.fetch()

    configureSearchController(
      placeholder: "Search in \"Album\"",
      scopeButtonTitles: ["All", "Cached"]
    )
    tableView.register(nibName: PlayableTableCell.typeName)
    tableView.rowHeight = PlayableTableCell.rowHeight
    // Catalyst also need an estimate to calculate the correct height before scrolling
    tableView.estimatedRowHeight = PlayableTableCell.rowHeight
    tableView.sectionFooterHeight = 0.0
    tableView.estimatedSectionFooterHeight = 0.0
    tableView.sectionHeaderHeight = 0.0
    tableView.estimatedSectionHeaderHeight = 0.0
    tableView.backgroundColor = .backgroundColor

    let playShuffleInfoConfig = PlayShuffleInfoConfiguration(
      infoCB: { "\(self.album.songCount) Song\(self.album.songCount == 1 ? "" : "s")" },
      playContextCb: { () in PlayContext(
        containable: self.album,
        playables: self.fetchedResultsController
          .getContextSongs(onlyCachedSongs: self.appDelegate.storage.settings.user.isOfflineMode) ??
          []
      ) },
      player: appDelegate.player,
      isInfoAlwaysHidden: true
    )
    let detailHeaderConfig = DetailHeaderConfiguration(
      entityContainer: album,
      rootView: self,
      tableView: tableView,
      playShuffleInfoConfig: playShuffleInfoConfig
    )
    detailOperationsView = GenericDetailTableHeader
      .createTableHeader(configuration: detailHeaderConfig)

    optionsButton = UIBarButtonItem.createOptionsBarButton()
    optionsButton.menu = UIMenu.lazyMenu {
      EntityPreviewActionBuilder(container: self.album, on: self).createMenuActions()
    }
    navigationItem.rightBarButtonItem = optionsButton

    containableAtIndexPathCallback = { indexPath in
      self.fetchedResultsController.getWrappedEntity(at: indexPath)
    }
    playContextAtIndexPathCallback = convertIndexPathToPlayContext
    swipeCallback = { indexPath, completionHandler in
      let song = self.fetchedResultsController.getWrappedEntity(at: indexPath)
      let playContext = self.convertIndexPathToPlayContext(songIndexPath: indexPath)
      completionHandler(SwipeActionContext(containable: song, playContext: playContext))
    }

    // as early as possible, so the default color is barely visible during the push
    updateBackgroundColorFromArtwork()
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
      self.updateBackgroundColorFromArtwork(animated: true)
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = false
    applyNavigationBarStyle()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // the navigation bar is shared with other screens
    navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
  }

  /// Title, back button and bar buttons follow the artwork background while this screen is visible.
  private func applyNavigationBarStyle() {
    navigationController?.navigationBar.overrideUserInterfaceStyle = navigationBarStyle
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()

    Task { @MainActor in
      do {
        try await album.fetch(
          storage: self.appDelegate.storage,
          librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
          playableDownloadManager: self.appDelegate.getMeta(self.account.info)
            .playableDownloadManager
        )
      } catch {
        self.appDelegate.eventLogger.report(topic: "Album Sync", error: error)
      }
      self.detailOperationsView?.refresh()
      self.updateBackgroundColorFromArtwork()
    }
  }

  private func updateBackgroundColorFromArtwork(animated: Bool? = nil) {
    let artworkDisplayPreference = appDelegate.storage.settings.accounts
      .getSetting(account.info).read.artworkDisplayPreference
    guard let imagePath = album.imagePath(setting: artworkDisplayPreference) else { return }

    let isDarkMode = traitCollection.userInterfaceStyle == .dark
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
      self.applyBackground(color: color, animated: animated ?? (self.view.window != nil))
    }
  }

  private func applyBackground(color: UIColor, animated: Bool) {
    // the color is already chosen for the current interface style
    let backgroundColor = color
    // dark style renders labels, separators and cells white, light style black
    let prefersDarkContent = backgroundColor.prefersDarkContent
    tableView.overrideUserInterfaceStyle = prefersDarkContent ? .light : .dark
    detailOperationsView?.subtitleLabel.textColor = prefersDarkContent ? .black : .white
    detailOperationsView?.playShuffleInfoView?.applyContentColors(forBackground: backgroundColor)
    applySearchBarColors(prefersDarkContent: prefersDarkContent)
    let contentColor: UIColor = prefersDarkContent ? .black : .white
    self.contentColor = contentColor
    tableView.separatorColor = contentColor.withAlphaComponent(0.3)
    detailOperationsView?.applyContentColor(contentColor)
    detailOperationsView?.enableCoverShadow()
    for case let cell as PlayableTableCell in tableView.visibleCells {
      cell.contentColorOverride = contentColor
      cell.refresh()
      cell.setNeedsLayout() // cells drawing their own separators pick up the new separatorColor
    }
    navigationBarStyle = prefersDarkContent ? .light : .dark
    applyNavigationBarStyle()
    let update = { self.tableView.backgroundColor = backgroundColor }
    if animated {
      UIView.animate(withDuration: 0.2, animations: update)
    } else {
      update()
    }
  }

  /// Search field text, placeholder, icon and fill follow the artwork background.
  private func applySearchBarColors(prefersDarkContent: Bool) {
    let contentColor: UIColor = prefersDarkContent ? .black : .white
    let searchBar = searchController.searchBar
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

  private static let mainColorCache = NSCache<NSString, UIColor>()

  @concurrent
  private static func loadMainColor(imagePath: String, forDarkBackground: Bool) async -> UIColor? {
    UIImage(contentsOfFile: imagePath)?.mainColor(forDarkBackground: forDarkBackground)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    defer { songToScrollTo = nil }
    guard let songToScrollTo = songToScrollTo,
          let indexPath = fetchedResultsController.fetchResultsController
          .indexPath(forObject: songToScrollTo.managedObject)
    else { return }
    tableView.scrollToRow(at: indexPath, at: .top, animated: true)
  }

  func convertIndexPathToPlayContext(songIndexPath: IndexPath) -> PlayContext? {
    guard let songs = fetchedResultsController
      .getContextSongs(onlyCachedSongs: appDelegate.storage.settings.user.isOfflineMode)
    else { return nil }
    let selectedSong = fetchedResultsController.getWrappedEntity(at: songIndexPath)
    guard let playContextIndex = songs.firstIndex(of: selectedSong) else { return nil }
    return PlayContext(containable: album, index: playContextIndex, playables: songs)
  }

  func convertCellViewToPlayContext(cell: UITableViewCell) -> PlayContext? {
    guard let indexPath = tableView.indexPath(for: cell) else { return nil }
    return convertIndexPathToPlayContext(songIndexPath: indexPath)
  }

  func createCell(
    _ tableView: UITableView,
    forRowAt indexPath: IndexPath,
    song: Song
  )
    -> UITableViewCell {
    let cell: PlayableTableCell = dequeueCell(for: tableView, at: indexPath)
    cell.contentColorOverride = contentColor
    cell.display(
      playable: song,
      playContextCb: convertCellViewToPlayContext,
      rootView: self,
      isDislayAlbumTrackNumberStyle: true
    )
    return cell
  }

  override func updateSearchResults(for searchController: UISearchController) {
    fetchedResultsController.search(
      searchText: searchController.searchBar.text ?? "",
      onlyCachedSongs: searchController.searchBar.selectedScopeButtonIndex == 1
    )
    tableView.reloadData()
  }
}
