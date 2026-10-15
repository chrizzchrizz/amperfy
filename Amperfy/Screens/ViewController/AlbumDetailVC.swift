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
  private var artworkBackground: ArtworkBackgroundController!
  private var similarContentFooter: SimilarContentFooterView?
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
    tableView.separatorStyle = .none // rows draw their own separators

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
    artworkBackground = ArtworkBackgroundController(
      owner: self,
      account: account,
      detailHeader: { [weak self] in self?.detailOperationsView },
      imagePath: { [weak self] setting in self?.album.imagePath(setting: setting) }
    )
    artworkBackground.update()
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
      self.artworkBackground.update(animated: true)
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = false
    artworkBackground.applyNavigationBarStyle()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // the navigation bar is shared with other screens
    artworkBackground.resetNavigationBarStyle()
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
      self.artworkBackground.update()
    }
    loadSimilarContent()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layoutSimilarContentFooter()
  }

  private func loadSimilarContent() {
    guard similarContentFooter == nil else { return }
    let footer = SimilarContentFooterView(
      theme: appDelegate.storage.settings.accounts.getSetting(account.info).read.themePreference
    )
    footer.onArtistSelected = { [weak self] artist in
      guard let self else { return }
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist),
        animated: true
      )
    }
    footer.onAlbumSelected = { [weak self] album in
      guard let self else { return }
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
        animated: true
      )
    }
    similarContentFooter = footer

    let librarySyncer = appDelegate.getMeta(account.info).librarySyncer
    Task { @MainActor in
      // similar content is optional, a failing server agent must not disturb the screen
      if let artist = album.artist {
        do {
          footer.display(artists: try await librarySyncer.requestSimilarArtists(
            artist: artist,
            count: 15
          ))
        } catch {
          appDelegate.eventLogger.report(topic: "Similar Artists", error: error)
        }
      }
      do {
        let albums = try await librarySyncer.requestSimilarAlbums(album: album, count: 40)
        footer.display(albums: Array(albums.prefix(12)))
      } catch {
        appDelegate.eventLogger.report(topic: "Similar Albums", error: error)
      }
      if footer.hasContent {
        tableView.tableFooterView = footer
        layoutSimilarContentFooter()
      }
    }
  }

  private func layoutSimilarContentFooter() {
    guard let footer = similarContentFooter, tableView.tableFooterView === footer,
          tableView.bounds.width > 0 else { return }
    let height = footer.systemLayoutSizeFitting(
      CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    guard footer.frame.size != CGSize(width: tableView.bounds.width, height: height) else { return }
    footer.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: height)
    tableView.tableFooterView = footer
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
    cell.contentColorOverride = artworkBackground.contentColor
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
