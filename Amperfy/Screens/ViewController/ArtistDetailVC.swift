//
//  ArtistDetailVC.swift
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
import CoreData
import UIKit

// MARK: - ArtistDetailVC

class ArtistDetailVC: MultiSourceTableViewController {
  /// The top section is needed due to display bugs
  private enum Section: Int, CaseIterable {
    case top
    case albums
    case compilations
    case songs
  }

  private let artist: Artist
  var albumToScrollTo: Album?
  private var albumsFetchedResultsController: ArtistAlbumsItemsFetchedResultsController!
  private var compilationsFetchedResultsController: ArtistAlbumsItemsFetchedResultsController!
  private var songsFetchedResultsController: ArtistSongsItemsFetchedResultsController!
  private var optionsButton: UIBarButtonItem!
  private var detailOperationsView: GenericDetailTableHeader?
  private var artworkBackground: ArtworkBackgroundController!
  private var albumsGridVC: ArtistAlbumsGridVC!
  private var compilationsGridVC: ArtistAlbumsGridVC!

  init(account: Account, artist: Artist) {
    self.artist = artist
    super.init(style: .grouped, account: account)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    appDelegate.userStatistics.visited(.artistDetail)

    optionsButton = UIBarButtonItem.createOptionsBarButton()

    albumsFetchedResultsController = ArtistAlbumsItemsFetchedResultsController(
      for: artist,
      isCompilation: false,
      coreDataCompanion: appDelegate.storage.main,
      isGroupedInAlphabeticSections: false
    )
    albumsFetchedResultsController.delegate = self
    compilationsFetchedResultsController = ArtistAlbumsItemsFetchedResultsController(
      for: artist,
      isCompilation: true,
      coreDataCompanion: appDelegate.storage.main,
      isGroupedInAlphabeticSections: false
    )
    compilationsFetchedResultsController.delegate = self
    songsFetchedResultsController = ArtistSongsItemsFetchedResultsController(
      for: artist,
      displayFilter: appDelegate.storage.settings.user.artistsFilterSetting,
      coreDataCompanion: appDelegate.storage.main,
      isGroupedInAlphabeticSections: false
    )
    songsFetchedResultsController.delegate = self
    tableView.register(nibName: GenericTableCell.typeName)
    tableView.register(nibName: PlayableTableCell.typeName)
    tableView.register(
      ArtistAlbumsGridCell.self,
      forCellReuseIdentifier: ArtistAlbumsGridCell.reuseID
    )

    albumsGridVC = ArtistAlbumsGridVC(
      account: account,
      albumCount: { [weak self] in
        self?.albumsFetchedResultsController.sections?[0].numberOfObjects ?? 0
      },
      album: { [weak self] row in
        self?.albumsFetchedResultsController.getWrappedEntity(at: IndexPath(row: row, section: 0))
      },
      owner: self
    )
    addChild(albumsGridVC)
    albumsGridVC.didMove(toParent: self)
    compilationsGridVC = ArtistAlbumsGridVC(
      account: account,
      albumCount: { [weak self] in
        self?.compilationsFetchedResultsController.sections?[0].numberOfObjects ?? 0
      },
      album: { [weak self] row in
        self?.compilationsFetchedResultsController.getWrappedEntity(at: IndexPath(
          row: row,
          section: 0
        ))
      },
      owner: self
    )
    addChild(compilationsGridVC)
    compilationsGridVC.didMove(toParent: self)
    tableView.sectionHeaderHeight = 0.0
    tableView.estimatedSectionHeaderHeight = 0.0
    tableView.sectionFooterHeight = 0.0
    tableView.estimatedSectionFooterHeight = 0.0
    tableView.sectionHeaderTopPadding = 0.0
    tableView.backgroundColor = .clear

    configureSearchController(placeholder: "Albums and Songs", scopeButtonTitles: ["All", "Cached"])
    let playShuffleInfoConfig = PlayShuffleInfoConfiguration(
      infoCB: {
        "\(self.artist.albumCount) Album\(self.artist.albumCount == 1 ? "" : "s") \(CommonString.oneMiddleDot) \(self.artist.songCount) Song\(self.artist.songCount == 1 ? "" : "s")"
      },
      playContextCb: { () in
        let songs = self.songsFetchedResultsController
          .getContextSongs(onlyCachedSongs: self.appDelegate.storage.settings.user.isOfflineMode) ??
          []
        let sortedSongs = songs.filterSongs().sortByAlbum()
        return PlayContext(containable: self.artist, playables: sortedSongs)
      },
      player: appDelegate.player,
      isInfoAlwaysHidden: true
    )
    let detailHeaderConfig = DetailHeaderConfiguration(
      entityContainer: artist,
      rootView: self,
      tableView: tableView,
      playShuffleInfoConfig: playShuffleInfoConfig
    )
    detailOperationsView = GenericDetailTableHeader
      .createTableHeader(configuration: detailHeaderConfig)

    optionsButton = UIBarButtonItem.createOptionsBarButton()
    optionsButton.menu = UIMenu.lazyMenu {
      EntityPreviewActionBuilder(container: self.artist, on: self).createMenuActions()
    }
    navigationItem.rightBarButtonItem = optionsButton

    // as early as possible, so the default color is barely visible during the push
    artworkBackground = ArtworkBackgroundController(
      owner: self,
      account: account,
      detailHeader: { [weak self] in self?.detailOperationsView },
      imagePath: { [weak self] setting in self?.artist.imagePath(setting: setting) }
    )
    artworkBackground.update()
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
      self.artworkBackground.update(animated: true)
    }

    containableAtIndexPathCallback = { indexPath in
      switch Section(rawValue: indexPath.section) {
      case .songs:
        return self.songsFetchedResultsController.getWrappedEntity(at: IndexPath(
          row: indexPath.row,
          section: 0
        ))
      default:
        return nil
      }
    }
    playContextAtIndexPathCallback = { indexPath in
      switch Section(rawValue: indexPath.section) {
      case .songs:
        let songIndexPath = IndexPath(row: indexPath.row, section: 0)
        return self.convertIndexPathToPlayContext(songIndexPath: songIndexPath)
      default:
        return nil
      }
    }
    swipeCallback = { indexPath, completionHandler in
      switch Section(rawValue: indexPath.section) {
      case .songs:
        let songIndexPath = IndexPath(row: indexPath.row, section: 0)
        let song = self.songsFetchedResultsController.getWrappedEntity(at: songIndexPath)
        let playContext = self.convertIndexPathToPlayContext(songIndexPath: songIndexPath)
        completionHandler(SwipeActionContext(containable: song, playContext: playContext))
      default:
        completionHandler(nil)
      }
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = false
    artworkBackground.applyNavigationBarStyle()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
    albumsFetchedResultsController?.delegate = self
    compilationsFetchedResultsController?.delegate = self
    songsFetchedResultsController?.delegate = self
    Task { @MainActor in
      do {
        try await artist.fetch(
          storage: self.appDelegate.storage,
          librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
          playableDownloadManager: self.appDelegate.getMeta(self.account.info)
            .playableDownloadManager
        )
      } catch {
        self.appDelegate.eventLogger.report(topic: "Artist Sync", error: error)
      }
      self.detailOperationsView?.refresh()
      self.artworkBackground.update()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // the navigation bar is shared with other screens
    artworkBackground.resetNavigationBarStyle()
    albumsFetchedResultsController?.delegate = nil
    compilationsFetchedResultsController?.delegate = nil
    songsFetchedResultsController?.delegate = nil
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    defer { albumToScrollTo = nil }
    guard let albumToScrollTo else { return }
    let grids: [(Section, ArtistAlbumsItemsFetchedResultsController, ArtistAlbumsGridVC)] = [
      (.albums, albumsFetchedResultsController, albumsGridVC),
      (.compilations, compilationsFetchedResultsController, compilationsGridVC),
    ]
    for (section, fetchedResultsController, gridVC) in grids {
      guard let indexPath = fetchedResultsController.fetchResultsController
        .indexPath(forObject: albumToScrollTo.managedObject) else { continue }
      // all albums of a section are inside one row
      tableView.scrollToRow(
        at: IndexPath(row: 0, section: section.rawValue),
        at: .top,
        animated: true
      )
      gridVC.scrollToAlbum(at: indexPath.row)
      return
    }
  }

  func convertIndexPathToPlayContext(songIndexPath: IndexPath) -> PlayContext? {
    guard let songs = songsFetchedResultsController
      .getContextSongs(onlyCachedSongs: appDelegate.storage.settings.user.isOfflineMode)
    else { return nil }
    let selectedSong = songsFetchedResultsController.getWrappedEntity(at: songIndexPath)
    guard let playContextIndex = songs.firstIndex(of: selectedSong) else { return nil }
    return PlayContext(containable: artist, index: playContextIndex, playables: songs)
  }

  func convertCellViewToPlayContext(cell: UITableViewCell) -> PlayContext? {
    guard let indexPath = tableView.indexPath(for: cell),
          indexPath.section == Section.songs.rawValue
    else { return nil }
    return convertIndexPathToPlayContext(songIndexPath: IndexPath(row: indexPath.row, section: 0))
  }

  // MARK: - Table view data source

  override func numberOfSections(in tableView: UITableView) -> Int {
    Section.allCases.count
  }

  override func tableView(
    _ tableView: UITableView,
    viewForHeaderInSection section: Int
  )
    -> UIView? {
    switch Section(rawValue: section) {
    case .albums:
      return ArtistSectionHeaderView(title: "Albums", bottomPadding: 0)
    case .compilations:
      return ArtistSectionHeaderView(title: "Compilations", bottomPadding: 0)
    case .songs:
      return ArtistSectionHeaderView(
        title: "Songs",
        bottomPadding: ArtistSectionHeaderView.contentSpacing
      )
    default:
      return nil
    }
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch Section(rawValue: section) {
    case .albums:
      // all albums are shown in one horizontally scrolling row
      return (albumsFetchedResultsController.sections?[0].numberOfObjects ?? 0) > 0 ? 1 : 0
    case .compilations:
      return (compilationsFetchedResultsController.sections?[0].numberOfObjects ?? 0) > 0 ? 1 : 0
    case .songs:
      return songsFetchedResultsController.sections?[0].numberOfObjects ?? 0
    default:
      return 0
    }
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    switch Section(rawValue: indexPath.section) {
    case .albums:
      let cell = tableView.dequeueReusableCell(
        withIdentifier: ArtistAlbumsGridCell.reuseID,
        for: indexPath
      ) as! ArtistAlbumsGridCell
      cell.embed(gridVC: albumsGridVC)
      return cell
    case .compilations:
      let cell = tableView.dequeueReusableCell(
        withIdentifier: ArtistAlbumsGridCell.reuseID,
        for: indexPath
      ) as! ArtistAlbumsGridCell
      cell.embed(gridVC: compilationsGridVC)
      return cell
    case .songs:
      let cell: PlayableTableCell = dequeueCell(for: tableView, at: indexPath)
      let song = songsFetchedResultsController.getWrappedEntity(at: IndexPath(
        row: indexPath.row,
        section: 0
      ))
      cell.contentColorOverride = artworkBackground.contentColor
      cell.display(playable: song, playContextCb: convertCellViewToPlayContext, rootView: self)
      return cell
    default:
      return UITableViewCell()
    }
  }

  override func tableView(
    _ tableView: UITableView,
    heightForHeaderInSection section: Int
  )
    -> CGFloat {
    switch Section(rawValue: section) {
    case .albums:
      return albumsFetchedResultsController.sections?[0]
        .numberOfObjects ?? 0 > 0 ? ArtistSectionHeaderView.height(bottomPadding: 0) : 0
    case .compilations:
      return compilationsFetchedResultsController.sections?[0]
        .numberOfObjects ?? 0 > 0 ? ArtistSectionHeaderView.height(bottomPadding: 0) : 0
    case .songs:
      return songsFetchedResultsController.sections?[0]
        .numberOfObjects ?? 0 > 0 ?
        ArtistSectionHeaderView.height(bottomPadding: ArtistSectionHeaderView.contentSpacing) : 0
    default:
      return 0.0
    }
  }

  override func tableView(
    _ tableView: UITableView,
    heightForRowAt indexPath: IndexPath
  )
    -> CGFloat {
    switch Section(rawValue: indexPath.section) {
    case .albums:
      return albumsGridVC.contentHeight
    case .compilations:
      return compilationsGridVC.contentHeight
    case .songs:
      return PlayableTableCell.rowHeight
    default:
      return 0.0
    }
  }

  override func tableView(
    _ tableView: UITableView,
    estimatedHeightForRowAt indexPath: IndexPath
  )
    -> CGFloat {
    switch Section(rawValue: indexPath.section) {
    case .albums:
      return albumsGridVC.contentHeight
    case .compilations:
      return compilationsGridVC.contentHeight
    case .songs:
      return PlayableTableCell.rowHeight
    default:
      return 0.0
    }
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    // albums are selected inside the grid
  }

  override func updateSearchResults(for searchController: UISearchController) {
    guard let searchText = searchController.searchBar.text else { return }
    if !searchText.isEmpty, searchController.searchBar.selectedScopeButtonIndex == 0 {
      albumsFetchedResultsController.search(searchText: searchText, onlyCached: false)
      compilationsFetchedResultsController.search(searchText: searchText, onlyCached: false)
      songsFetchedResultsController.search(searchText: searchText, onlyCachedSongs: false)
    } else if searchController.searchBar.selectedScopeButtonIndex == 1 {
      albumsFetchedResultsController.search(searchText: searchText, onlyCached: true)
      compilationsFetchedResultsController.search(searchText: searchText, onlyCached: true)
      songsFetchedResultsController.search(searchText: searchText, onlyCachedSongs: true)
    } else {
      albumsFetchedResultsController.showAllResults()
      compilationsFetchedResultsController.showAllResults()
      songsFetchedResultsController.showAllResults()
    }
    tableView.reloadData()
  }

  override func controller(
    _ controller: NSFetchedResultsController<NSFetchRequestResult>,
    didChange anObject: Any,
    at indexPath: IndexPath?,
    for type: NSFetchedResultsChangeType,
    newIndexPath: IndexPath?
  ) {
    var section = 0
    switch controller {
    case albumsFetchedResultsController.fetchResultsController,
         compilationsFetchedResultsController.fetchResultsController:
      // the grids are reloaded as a whole in controllerDidChangeContent
      return
    case songsFetchedResultsController.fetchResultsController:
      section = Section.songs.rawValue
    default:
      return
    }

    resultUpdateHandler?.applyChangesOfMultiRowType(
      controller,
      didChange: anObject,
      determinedSection: section,
      at: indexPath,
      for: type,
      newIndexPath: newIndexPath
    )
  }

  override func controllerDidChangeContent(
    _ controller: NSFetchedResultsController<NSFetchRequestResult>
  ) {
    super.controllerDidChangeContent(controller)
    switch controller {
    case albumsFetchedResultsController.fetchResultsController:
      reloadGrid(
        albumsGridVC,
        in: .albums,
        fetchedResultsController: albumsFetchedResultsController
      )
    case compilationsFetchedResultsController.fetchResultsController:
      reloadGrid(
        compilationsGridVC,
        in: .compilations,
        fetchedResultsController: compilationsFetchedResultsController
      )
    default:
      break
    }
  }

  private func reloadGrid(
    _ gridVC: ArtistAlbumsGridVC,
    in section: Section,
    fetchedResultsController: ArtistAlbumsItemsFetchedResultsController
  ) {
    let hasAlbums = (fetchedResultsController.sections?[0].numberOfObjects ?? 0) > 0
    if hasAlbums != (tableView.numberOfRows(inSection: section.rawValue) > 0) {
      tableView.reloadSections([section.rawValue], with: .none)
    } else {
      gridVC.reload()
      tableView.performBatchUpdates(nil)
    }
  }

  override func controller(
    _ controller: NSFetchedResultsController<NSFetchRequestResult>,
    didChange sectionInfo: NSFetchedResultsSectionInfo,
    atSectionIndex sectionIndex: Int,
    for type: NSFetchedResultsChangeType
  ) {}
}

// MARK: - ArtistAlbumsGridCell

/// Hosts the album row inside the table.
final class ArtistAlbumsGridCell: UITableViewCell {
  static let reuseID = "ArtistAlbumsGridCell"

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear
    selectionStyle = .none
    separatorInset = UIEdgeInsets(top: 0, left: .greatestFiniteMagnitude, bottom: 0, right: 0)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func embed(gridVC: ArtistAlbumsGridVC) {
    let gridView: UIView = gridVC.view
    guard gridView.superview !== contentView else { return }
    // a reused cell may still host the grid of the other section
    contentView.subviews.forEach { $0.removeFromSuperview() }
    gridView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(gridView)
    NSLayoutConstraint.activate([
      gridView.topAnchor.constraint(equalTo: contentView.topAnchor),
      gridView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      gridView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      gridView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
    ])
  }
}

// MARK: - ArtistAlbumsGridVC

/// Albums of an artist in one horizontally scrolling row with the tiles of the home screen.
final class ArtistAlbumsGridVC: UICollectionViewController, UICollectionViewDelegateFlowLayout {
  private static let itemWidth: CGFloat = 160.0
  private static let spacing: CGFloat = 12.0
  private static let sideInset: CGFloat = 16.0
  private static let topInset = ArtistSectionHeaderView.contentSpacing
  private static let bottomInset: CGFloat = 24.0
  private static let labelsHeight: CGFloat = 50.0

  private let account: Account
  private let albumCount: () -> Int
  private let album: (Int) -> Album?
  private unowned let owner: ArtistDetailVC

  init(
    account: Account,
    albumCount: @escaping () -> Int,
    album: @escaping (Int) -> Album?,
    owner: ArtistDetailVC
  ) {
    self.account = account
    self.albumCount = albumCount
    self.album = album
    self.owner = owner
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .horizontal
    layout.minimumInteritemSpacing = Self.spacing
    layout.minimumLineSpacing = Self.spacing
    layout.sectionInset = UIEdgeInsets(
      top: Self.topInset,
      left: Self.sideInset,
      bottom: Self.bottomInset,
      right: Self.sideInset
    )
    super.init(collectionViewLayout: layout)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    collectionView.backgroundColor = .clear
    collectionView.showsHorizontalScrollIndicator = false
    collectionView.register(
      UINib(nibName: AlbumCollectionCell.typeName, bundle: .main),
      forCellWithReuseIdentifier: AlbumCollectionCell.typeName
    )
  }

  func reload() {
    collectionView.reloadData()
  }

  func scrollToAlbum(at row: Int) {
    collectionView.scrollToItem(
      at: IndexPath(item: row, section: 0),
      at: .centeredHorizontally,
      animated: true
    )
  }

  // MARK: - Data source

  override func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  )
    -> Int {
    albumCount()
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  )
    -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: AlbumCollectionCell.typeName,
      for: indexPath
    ) as! AlbumCollectionCell
    if let album = album(indexPath.row) {
      cell.display(
        container: album,
        rootView: self,
        rootFlowLayout: self,
        initialIndexPath: indexPath
      )
    }
    return cell
  }

  // MARK: - Layout

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  )
    -> CGSize {
    Self.itemSize
  }

  private static let itemSize = CGSize(width: itemWidth, height: itemWidth + labelsHeight)

  /// Height of the row; the table row gets exactly this height.
  var contentHeight: CGFloat {
    albumCount() > 0 ? Self.topInset + Self.itemSize.height + Self.bottomInset : 0
  }

  // MARK: - Selection

  override func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    guard let album = album(indexPath.row) else { return }
    owner.navigationController?.pushViewController(
      AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
      animated: true
    )
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemAt indexPath: IndexPath,
    point: CGPoint
  )
    -> UIContextMenuConfiguration? {
    guard let album = album(indexPath.row) else { return nil }
    let owner = owner
    return UIContextMenuConfiguration(identifier: nil, previewProvider: {
      let vc = EntityPreviewVC()
      vc.display(container: album, on: owner)
      Task { @MainActor in
        do {
          try await album.fetch(
            storage: owner.appDelegate.storage,
            librarySyncer: owner.appDelegate.getMeta(owner.account.info).librarySyncer,
            playableDownloadManager: owner.appDelegate.getMeta(owner.account.info)
              .playableDownloadManager
          )
        } catch {
          owner.appDelegate.eventLogger.report(topic: "Preview Sync", error: error)
        }
        vc.refresh()
      }
      return vc
    }) { _ in
      EntityPreviewActionBuilder(
        container: album,
        on: owner,
        playContextCb: { PlayContext(containable: album) }
      ).createMenu()
    }
  }
}

// MARK: - ArtistSectionHeaderView

/// Section title in the style of the home screen sections.
private final class ArtistSectionHeaderView: UIView {
  private static let topPadding: CGFloat = 16.0

  private static var font: UIFont {
    UIFont.systemFont(
      ofSize: UIFont.preferredFont(forTextStyle: .title3).pointSize,
      weight: .semibold
    )
  }

  /// Space between the title and the content below, like on the home screen.
  /// The album grid adds it as its own top inset, the song rows get it from the header.
  static let contentSpacing: CGFloat = 8.0

  /// Like on the home screen the header only is as high as its title.
  static func height(bottomPadding: CGFloat) -> CGFloat {
    topPadding + ceil(font.lineHeight) + bottomPadding
  }

  private static let sideInset: CGFloat = 16.0

  private let titleLabel = UILabel()
  private var isPinnedToTable = false

  init(title: String, bottomPadding: CGFloat) {
    super.init(frame: .zero)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = title
    titleLabel.font = Self.font
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = .label
    addSubview(titleLabel)
    // fallback until the header is part of the table view, replaced by the table's safe area
    let fallbackLeading = titleLabel.leadingAnchor.constraint(
      equalTo: leadingAnchor,
      constant: Self.sideInset
    )
    let fallbackTrailing = titleLabel.trailingAnchor.constraint(
      equalTo: trailingAnchor,
      constant: -Self.sideInset
    )
    fallbackLeading.priority = .defaultLow
    fallbackTrailing.priority = .defaultLow
    NSLayoutConstraint.activate([
      fallbackLeading,
      fallbackTrailing,
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Self.topPadding),
      titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomPadding),
    ])
  }

  /// Section headers span the whole table width, also below the sidebar on Mac and iPad.
  /// Like the album grid (inside the cell's content view) the title keeps out of the safe area.
  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    guard !isPinnedToTable else { return }
    var view = superview
    while let current = view, !(current is UITableView) { view = current.superview }
    guard let tableView = view as? UITableView else { return }
    isPinnedToTable = true
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(
        equalTo: tableView.safeAreaLayoutGuide.leadingAnchor,
        constant: Self.sideInset
      ),
      titleLabel.trailingAnchor.constraint(
        equalTo: tableView.safeAreaLayoutGuide.trailingAnchor,
        constant: -Self.sideInset
      ),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
