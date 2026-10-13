//
//  HomeVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 24.11.25.
//  Copyright (c) 2025 Maximilian Bauer. All rights reserved.
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
import OSLog
import UIKit

// MARK: - HomeVC

final class HomeVC: UICollectionViewController {
  // MARK: - Properties

  private var dataSource: UICollectionViewDiffableDataSource<HomeSection, HomeItem>!
  private var lastAppliedDecadeTitle: String?
  private var lastAppliedGenreTitle: String?
  private let log = OSLog(subsystem: "Amperfy", category: "HomeVC")

  private static let itemWidth: CGFloat = 160.0

  private var userButton: UIButton?
  private var userBarButtonItem: UIBarButtonItem?
  private let account: Account
  private var accountNotificationHandler: AccountNotificationHandler?
  private let sharedHome: HomeManager

  // MARK: - Init

  init(account: Account) {
    self.account = account
    let appDelegate = (UIApplication.shared.delegate as! AppDelegate)
    self.sharedHome = HomeManager(
      account: account,
      storage: appDelegate.storage,
      getMeta: appDelegate.getMeta,
      eventLogger: appDelegate.eventLogger
    )
    let layout = HomeVC.createLayout()
    super.init(collectionViewLayout: layout)
    sharedHome.applySnapshotCB = { [weak self] in
      guard let self else { return }
      applySnapshot(animated: true)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    // ensures that the collection view stops placing items under the sidebar
    collectionView.contentInsetAdjustmentBehavior = .scrollableAxes
    title = "Home"

    accountNotificationHandler = AccountNotificationHandler(
      storage: appDelegate.storage,
      notificationHandler: appDelegate.notificationHandler
    )
    accountNotificationHandler?.registerCallbackForActiveAccountChange { [weak self] accountInfo in
      guard let self else { return }
      setupUserNavButton(
        currentAccount: account,
        userButton: &userButton,
        userBarButtonItem: &userBarButtonItem
      )
    }

    navigationController?.navigationBar.prefersLargeTitles = true
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "Edit",
      style: .plain,
      target: self,
      action: #selector(editSectionsTapped)
    )
    configureCollectionView()
    configureDataSource()
    sharedHome.createFetchController()
    applySnapshot(animated: false)

    appDelegate.notificationHandler.register(
      self,
      selector: #selector(refreshOfflineMode),
      name: .offlineModeChanged,
      object: nil
    )
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = true
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
    sharedHome.updateFromRemote()
    sharedHome.updateDecadeAlbumsIfIntervalElapsed()
    sharedHome.updateGenreAlbumsIfIntervalElapsed()
  }

  // MARK: - Layout

  private static func createLayout() -> UICollectionViewCompositionalLayout {
    let layout = UICollectionViewCompositionalLayout { sectionIndex, _ in
      guard let _ = HomeSection(rawValue: sectionIndex) else { return nil }

      // Item: square image with title below -> estimate height accommodates label
      let itemSize = NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0),
        heightDimension: .fractionalHeight(1.0)
      )
      let item = NSCollectionLayoutItem(layoutSize: itemSize)

      // Group: fixed width to show large image; height estimated to fit image + label
      // We'll use a vertical group containing the cell's content; the cell itself handles layout.
      let groupSize = NSCollectionLayoutSize(
        widthDimension: .absolute(itemWidth),
        heightDimension: .estimated(210)
      )
      let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

      let sectionLayout = NSCollectionLayoutSection(group: group)
      sectionLayout.orthogonalScrollingBehavior = .continuous
      sectionLayout.interGroupSpacing = 12
      sectionLayout.contentInsets = NSDirectionalEdgeInsets(
        top: 8,
        leading: 16,
        bottom: 24,
        trailing: 16
      )

      // Header
      let headerSize = NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0),
        heightDimension: .estimated(44)
      )
      let header = NSCollectionLayoutBoundarySupplementaryItem(
        layoutSize: headerSize,
        elementKind: UICollectionView.elementKindSectionHeader,
        alignment: .top
      )
      header.pinToVisibleBounds = false
      header.zIndex = 1
      sectionLayout.boundarySupplementaryItems = [header]

      return sectionLayout
    }
    return layout
  }

  // MARK: - CollectionView Setup

  private func configureCollectionView() {
    collectionView.backgroundColor = .systemBackground
    collectionView.register(
      UINib(nibName: AlbumCollectionCell.typeName, bundle: .main),
      forCellWithReuseIdentifier: AlbumCollectionCell.typeName
    )
    collectionView.register(
      SectionHeaderView.self,
      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
      withReuseIdentifier: SectionHeaderView.reuseID
    )
  }

  // MARK: - Data Source

  private func configureDataSource() {
    dataSource = UICollectionViewDiffableDataSource<
      HomeSection,
      HomeItem
    >(collectionView: collectionView) { collectionView, indexPath, item in
      let cell = collectionView.dequeueReusableCell(
        withReuseIdentifier: AlbumCollectionCell.typeName,
        for: indexPath
      ) as! AlbumCollectionCell
      cell.display(
        container: item.playableContainable,
        rootView: self,
        itemWidth: Self.itemWidth,
        initialIndexPath: indexPath
      )
      return cell
    }

    dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
      guard kind == UICollectionView.elementKindSectionHeader,
            let header = collectionView.dequeueReusableSupplementaryView(
              ofKind: kind,
              withReuseIdentifier: SectionHeaderView.reuseID,
              for: indexPath
            ) as? SectionHeaderView,
            let section = self.dataSource.snapshot().sectionIdentifiers.element(at: indexPath.section)
      else {
        return nil
      }
      header.setRefreshMenu(nil)
      switch section {
      case .decadeAlbums: header.title = self.sharedHome.decadeSectionTitle
      case .genreAlbums: header.title = self.sharedHome.genreSectionTitle
      default: header.title = section.title
      }
      if let displayType = section.libraryDisplayType {
        header.setTapHandler { [weak self] in self?.showLibraryList(displayType) }
      } else {
        header.setTapHandler(nil)
      }
      if section == .randomAlbums {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomAlbumsSection() }
      } else if section == .compilations {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshCompilationsSection() }
      } else if section == .randomArtists {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomArtistsSection() }
      } else if section == .randomGenres {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomGenresSection() }
      } else if section == .randomSongs {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomSongsSection() }
      } else if section == .genreAlbums {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshGenreAlbumsSection() }
        #if DEBUG
          header.setRefreshMenu(self.createGenreDebugMenu())
        #endif
      } else if section == .decadeAlbums {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshDecadeAlbumsSection() }
        #if DEBUG
          header.setRefreshMenu(self.createDecadeDebugMenu())
        #endif
      } else {
        header.showsRefreshButton = false
        header.setRefreshHandler(nil)
      }
      return header
    }
  }

  private func applySnapshot(animated: Bool = true) {
    var snapshot = NSDiffableDataSourceSnapshot<HomeSection, HomeItem>()
    // decade and genre sections are hidden as long as nothing qualifies (not enough albums)
    let sections = sharedHome.orderedVisibleSections.filter {
      switch $0 {
      case .decadeAlbums: return sharedHome.currentDecade != nil
      case .genreAlbums: return sharedHome.currentGenreGroup != nil
      default: return true
      }
    }
    snapshot.appendSections(sections)
    for section in sections {
      // Ids are stable per entity, so a repeated entity would be a duplicate identifier (assert).
      var seenIds = Set<String>()
      let items = (sharedHome.data[section] ?? []).filter { seenIds.insert($0.id).inserted }
      snapshot.appendItems(items, toSection: section)
    }
    let oldItems = dataSource.snapshot().itemIdentifiers
    let oldFingerprints = Dictionary(oldItems.map { ($0.id, $0.artworkFingerprint) }) { first, _ in
      first
    }
    let changedItems = snapshot.itemIdentifiers.filter {
      guard let old = oldFingerprints[$0.id] else { return false }
      return old != $0.artworkFingerprint
    }
    snapshot.reconfigureItems(changedItems)
    // headers are only configured when dequeued -> reload the section if the decade title changed
    let decadeTitle = sharedHome.decadeSectionTitle
    if decadeTitle != lastAppliedDecadeTitle, sections.contains(.decadeAlbums) {
      snapshot.reloadSections([.decadeAlbums])
    }
    lastAppliedDecadeTitle = decadeTitle
    let genreTitle = sharedHome.genreSectionTitle
    if genreTitle != lastAppliedGenreTitle, sections.contains(.genreAlbums) {
      snapshot.reloadSections([.genreAlbums])
    }
    lastAppliedGenreTitle = genreTitle
    dataSource.apply(snapshot, animatingDifferences: animated)
  }

  @objc
  private func refreshOfflineMode() {
    os_log("HomeVC: OfflineModeChanged", log: self.log, type: .info)
    sharedHome.createFetchController()
  }

  @objc
  private func editSectionsTapped() {
    presentSectionEditor()
  }

  private func presentSectionEditor() {
    // Build a simple editor using a temporary UIViewController with a table view
    let editor = HomeEditorVC(current: sharedHome.orderedVisibleSections) { [weak self] newOrder in
      guard let self else { return }
      sharedHome.orderedVisibleSections = newOrder
      if let accountInfo = appDelegate.storage.settings.accounts.active {
        appDelegate.storage.settings.accounts.updateSetting(accountInfo) { accountSettings in
          accountSettings.homeSections = newOrder
        }
      }
      applySnapshot(animated: true)

      sharedHome.createFetchController()
      sharedHome.updateFromRemote()
    }
    #if targetEnvironment(macCatalyst)
      // reordering via drag & drop did not drop inside a form sheet on macOS
      navigationController?.pushViewController(editor, animated: true)
    #else
      let nav = UINavigationController(rootViewController: editor)
      nav.modalPresentationStyle = .formSheet
      present(nav, animated: true)
    #endif
  }

  @objc
  func refreshRandomAlbumsSection() {
    Task { @MainActor in
      await sharedHome.updateRandomAlbums(isOfflineMode: sharedHome.isOfflineMode)
    }
  }

  @objc
  func refreshCompilationsSection() {
    Task { @MainActor in
      await sharedHome.updateCompilations(isOfflineMode: sharedHome.isOfflineMode)
    }
  }

  @objc
  func refreshRandomArtistsSection() {
    Task { @MainActor in
      await sharedHome.updateRandomArtists(isOfflineMode: sharedHome.isOfflineMode)
    }
  }

  @objc
  func refreshRandomGenresSection() {
    Task { @MainActor in
      await sharedHome.updateRandomGenres()
    }
  }

  #if DEBUG
    /// Debug only: long press on the decade refresh button lets you pick the decade.
    private func createDecadeDebugMenu() -> UIMenu {
      let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
        MainActor.assumeIsolated {
          guard let self else { completion([]); return }
          let decades = self.sharedHome.availableDecades()
          completion(decades.map { decade in
            UIAction(
              title: "\(decade)s",
              state: decade == self.sharedHome.currentDecade ? .on : .off
            ) { [weak self] _ in
              guard let self else { return }
              Task { @MainActor in
                await self.sharedHome.updateDecadeAlbums(
                  isOfflineMode: self.sharedHome.isOfflineMode,
                  forcedDecade: decade
                )
              }
            }
          })
        }
      }
      return UIMenu(title: "Debug: Select Decade", children: [deferred])
    }
  #endif

  #if DEBUG
    /// Debug only: long press on the genre refresh button lets you pick the genre group.
    private func createGenreDebugMenu() -> UIMenu {
      let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
        MainActor.assumeIsolated {
          guard let self else { completion([]); return }
          let groups = self.sharedHome.availableGenreGroups()
          completion(groups.map { group in
            UIAction(
              title: group.name,
              state: group == self.sharedHome.currentGenreGroup ? .on : .off
            ) { [weak self] _ in
              guard let self else { return }
              Task { @MainActor in
                await self.sharedHome.updateGenreAlbums(
                  isOfflineMode: self.sharedHome.isOfflineMode,
                  forcedGenreGroup: group
                )
              }
            }
          })
        }
      }
      return UIMenu(title: "Debug: Select Genre", children: [deferred])
    }
  #endif

  @objc
  func refreshGenreAlbumsSection() {
    Task { @MainActor in
      await sharedHome.updateGenreAlbums(isOfflineMode: sharedHome.isOfflineMode)
      scrollSectionToStart(.genreAlbums)
    }
  }

  @objc
  func refreshDecadeAlbumsSection() {
    Task { @MainActor in
      await sharedHome.updateDecadeAlbums(isOfflineMode: sharedHome.isOfflineMode)
      scrollSectionToStart(.decadeAlbums)
    }
  }

  @objc
  func refreshRandomSongsSection() {
    Task { @MainActor in
      await sharedHome.updateRandomSongs(isOfflineMode: sharedHome.isOfflineMode)
    }
  }

  // MARK: - Section Navigation

  private func showLibraryList(_ displayType: LibraryDisplayType) {
    navigationController?.pushViewController(
      displayType.controller(account: account, settings: appDelegate.storage.settings),
      animated: true
    )
    navigationController?.navigationBar.prefersLargeTitles = false
  }

  /// After a reload the section shows new content, so bring its horizontal list back to the first item.
  private func scrollSectionToStart(_ section: HomeSection) {
    let snapshot = dataSource.snapshot()
    guard let sectionIndex = snapshot.indexOfSection(section),
          snapshot.numberOfItems(inSection: section) > 0 else { return }
    collectionView.scrollToItem(
      at: IndexPath(item: 0, section: sectionIndex),
      at: .left,
      animated: true
    )
  }

  // MARK: - Selection Handling

  override func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    guard let playableContainer = dataSource.itemIdentifier(for: indexPath)?.playableContainable
    else { return }

    if let album = playableContainer as? Album {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let artist = playableContainer as? Artist {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let playlist = playableContainer as? Playlist {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToPlaylistDetail(account: account, playlist: playlist),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let song = playableContainer as? Song {
      appDelegate.player.play(context: PlayContext(containable: song))
    } else if let podcastEpisode = playableContainer as? PodcastEpisode,
              let podcast = podcastEpisode.podcast {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToPodcastDetail(
          account: account,
          podcast: podcast,
          episodeToScrollTo: podcastEpisode
        ),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let podcast = playableContainer as? Podcast {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToPodcastDetail(account: account, podcast: podcast),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let _ = playableContainer as? Radio {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToRadios(account: account),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let genre = playableContainer as? Genre {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToGenreDetail(account: account, genre: genre),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    }
  }
}

extension HomeVC {
  override func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemAt indexPath: IndexPath,
    point: CGPoint
  )
    -> UIContextMenuConfiguration? {
    guard let containable = dataSource.itemIdentifier(for: indexPath)?.playableContainable
    else { return nil }

    let identifier = NSString(string: TableViewPreviewInfo(
      playableContainerIdentifier: containable.containerIdentifier,
      indexPath: indexPath
    ).asJSONString())
    return UIContextMenuConfiguration(identifier: identifier, previewProvider: {
      let vc = EntityPreviewVC()
      vc.display(container: containable, on: self)
      Task { @MainActor in
        do {
          try await containable.fetch(
            storage: self.appDelegate.storage,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
        } catch {
          self.appDelegate.eventLogger.report(topic: "Preview Sync", error: error)
        }
        vc.refresh()
      }
      return vc
    }) { suggestedActions in
      var playIndexCB: (() -> PlayContext?)?
      playIndexCB = { PlayContext(containable: containable) }
      return EntityPreviewActionBuilder(
        container: containable,
        on: self,
        playContextCb: playIndexCB
      ).createMenu()
    }
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionCommitAnimating
  ) {
    animator.addCompletion {
      if let identifier = configuration.identifier as? String,
         let tvPreviewInfo = TableViewPreviewInfo.create(fromIdentifier: identifier),
         let containerIdentifier = tvPreviewInfo.playableContainerIdentifier,
         let container = self.appDelegate.storage.main.library
         .getContainer(identifier: containerIdentifier) {
        EntityPreviewActionBuilder(container: container, on: self).performPreviewTransition()
      }
    }
  }
}

// MARK: - SectionHeaderView

final class SectionHeaderView: UICollectionReusableView {
  static let reuseID = "SectionHeaderView"

  private let refreshButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.setImage(UIImage.refresh, for: .normal)
    btn.isHidden = true
    btn.accessibilityLabel = "Refresh Randoms"
    return btn
  }()

  private let titleLabel: UILabel = {
    let lbl = UILabel()
    lbl.translatesAutoresizingMaskIntoConstraints = false
    lbl.font = UIFont.preferredFont(forTextStyle: .title3).withWeight(.semibold)
    lbl.textColor = .label
    return lbl
  }()

  var showsRefreshButton: Bool {
    get { !refreshButton.isHidden }
    set { refreshButton.isHidden = !newValue }
  }

  func setRefreshHandler(_ handler: (() -> ())?) {
    refreshButton.removeTarget(nil, action: nil, for: .allEvents)
    guard let handler else { return }
    refreshButton.addAction(UIAction { _ in handler() }, for: .touchUpInside)
  }

  /// Shown on long press of the refresh button.
  func setRefreshMenu(_ menu: UIMenu?) {
    refreshButton.menu = menu
    refreshButton.showsMenuAsPrimaryAction = false
  }

  var title: String? {
    didSet { updateTitle() }
  }

  private func updateTitle() {
    guard let title else {
      titleLabel.attributedText = nil
      return
    }
    let result = NSMutableAttributedString(string: title)
    if tapHandler != nil {
      let pointSize = UIFont.preferredFont(forTextStyle: .subheadline).pointSize + 2
      let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold, scale: .small)
      let attachment = NSTextAttachment()
      attachment.image = UIImage(systemName: "chevron.right", withConfiguration: config)?
        .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
      result.append(NSAttributedString(string: " "))
      result.append(NSAttributedString(attachment: attachment))
    }
    titleLabel.attributedText = result
  }

  private var tapHandler: (() -> ())?

  func setTapHandler(_ handler: (() -> ())?) {
    tapHandler = handler
    updateTitle()
    isUserInteractionEnabled = true
    accessibilityTraits = handler == nil ? [] : .button
  }

  @objc
  private func headerTapped() {
    tapHandler?()
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(titleLabel)
    addSubview(refreshButton)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTapped)))
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: refreshButton.leadingAnchor,
        constant: -8
      ),
      titleLabel.topAnchor.constraint(equalTo: topAnchor),
      titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
      refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      refreshButton.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    addSubview(titleLabel)
    addSubview(refreshButton)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTapped)))
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: refreshButton.leadingAnchor,
        constant: -8
      ),
      titleLabel.topAnchor.constraint(equalTo: topAnchor),
      titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
      refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      refreshButton.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }
}

extension UIFont {
  fileprivate func withWeight(_ weight: UIFont.Weight) -> UIFont {
    let descriptor = fontDescriptor.addingAttributes([
      UIFontDescriptor.AttributeName.traits: [UIFontDescriptor.TraitKey.weight: weight],
    ])
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}

extension HomeSection {
  /// The library overview matching this section; nil if there is none (e.g. random sections).
  fileprivate var libraryDisplayType: LibraryDisplayType? {
    switch self {
    case .recentlyPlayedAlbums: return .recentAlbums
    case .newestAlbums: return .newestAlbums
    case .latestReleasedAlbums: return .latestReleasedAlbums
    case .compilations: return .compilations
    case .lastTimePlayedPlaylists: return .playlists
    case .podcasts: return .podcasts
    case .radios: return .radios
    case .newestPodcastEpisodes, .randomAlbums, .randomArtists, .randomGenres, .randomSongs,
         .decadeAlbums, .genreAlbums:
      return nil
    }
  }
}
