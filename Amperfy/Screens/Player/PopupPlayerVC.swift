//
//  PopupPlayerVC.swift
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
import CoreMedia
import UIKit

// MARK: - PopupPlayerLayout

enum PopupPlayerLayout {
  /// big artwork above the title
  case large
  /// small artwork and title in the first row of the queue
  case compact
  /// small artwork and title in a header, the lyrics fill the space below
  case lyrics
}

// MARK: - PopupPlayerVC

class PopupPlayerVC: UIViewController, UIScrollViewDelegate {
  @IBOutlet
  weak var tableView: UITableView!
  @IBOutlet
  weak var largePlayerPlaceholderView: UIView!
  @IBOutlet
  weak var controlPlaceholderView: UIView!
  @IBOutlet
  weak var backgroundColorView: UIImageView!

  lazy var tableViewKeyCommandsController = TableViewKeyCommandsController(
    tableView: tableView,
    overrideFirstLastIndexPath: IndexPath(
      row: 0,
      section: PlayerSectionCategory.currentlyPlaying.rawValue
    )
  )

  var player: PlayerFacade!
  var playerHandler: PlayerUIHandler?
  var controlView: PlayerControlView?
  var largeCurrentlyPlayingView: LargeCurrentlyPlayingPlayerView?
  var accountNotificationHandler: AccountNotificationHandler?
  private var windowStyleObservation: (any UITraitChangeRegistration)?

  var currentlyPlayingTableCell: CurrentlyPlayingTableCell?
  var currentLayout: PopupPlayerLayout?
  let lyricsLayoutView = UIView()
  let lyricsContainerView = UIView()
  var lyricsHeaderCell: CurrentlyPlayingTableCell?
  var contextPrevQueueSectionHeader: ContextQueuePrevSectionHeader?
  var userQueueSectionHeader: UserQueueSectionHeader?
  var contextNextQueueSectionHeader: ContextQueueNextSectionHeader?
  var activeDisplayedSectionHeader = Set<PlayerSectionCategory>()
  lazy var clearEmptySectionFooter = {
    let view = UIView()
    view.backgroundColor = .clear
    view.isHidden = true
    return view
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    // darkened artwork color needs white labels
    overrideUserInterfaceStyle = .dark

    tableView.delegate = self
    tableView.dataSource = self
    tableView.dragDelegate = self
    tableView.dropDelegate = self
    tableView.dragInteractionEnabled = true

    player = appDelegate.player
    player.addNotifier(notifier: self)
    playerHandler = PlayerUIHandler(player: player, style: .popupPlayer)

    if let createdPlayerControlView = ViewCreator<PlayerControlView>.createFromNib() {
      controlView = createdPlayerControlView
      createdPlayerControlView.prepare(toWorkOnRootView: self)
      createdPlayerControlView.translatesAutoresizingMaskIntoConstraints = false
      controlPlaceholderView.addSubview(createdPlayerControlView)
      NSLayoutConstraint.activate([
        createdPlayerControlView.topAnchor.constraint(equalTo: controlPlaceholderView.topAnchor),
        createdPlayerControlView.bottomAnchor
          .constraint(equalTo: controlPlaceholderView.bottomAnchor),
        createdPlayerControlView.leadingAnchor
          .constraint(equalTo: controlPlaceholderView.leadingAnchor),
        createdPlayerControlView.trailingAnchor
          .constraint(equalTo: controlPlaceholderView.trailingAnchor),
      ])
    }
    setupLyricsLayout()
    if let createdLargeCurrentlyPlayingView = ViewCreator<LargeCurrentlyPlayingPlayerView>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: largePlayerPlaceholderView.bounds.size.width,
        height: largePlayerPlaceholderView.bounds.size.height
      )) {
      largeCurrentlyPlayingView = createdLargeCurrentlyPlayingView
      createdLargeCurrentlyPlayingView.prepare(toWorkOnRootView: self)
      largePlayerPlaceholderView.addSubview(createdLargeCurrentlyPlayingView)
    }

    setupTableView()
    fetchSongInfoAndUpdateViews()

    if let sectionView = ViewCreator<ContextQueuePrevSectionHeader>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: view.bounds.size.width,
        height: ContextQueuePrevSectionHeader.frameHeight
      )) {
      contextPrevQueueSectionHeader = sectionView
      contextPrevQueueSectionHeader?.display(name: "Previous")
    }
    if let sectionView = ViewCreator<UserQueueSectionHeader>.createFromNib(withinFixedFrame: CGRect(
      x: 0,
      y: 0,
      width: view.bounds.size.width,
      height: UserQueueSectionHeader.frameHeight
    )) {
      userQueueSectionHeader = sectionView
      userQueueSectionHeader?.display(name: "Next from Queue", buttonPressAction: clearUserQueue)
    }
    if let sectionView = ViewCreator<ContextQueueNextSectionHeader>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: view.bounds.size.width,
        height: ContextQueueNextSectionHeader.frameHeight
      )) {
      contextNextQueueSectionHeader = sectionView
      contextNextQueueSectionHeader?.prepare(toWorkOnRootView: self)
    }

    accountNotificationHandler = AccountNotificationHandler(
      storage: appDelegate.storage,
      notificationHandler: appDelegate.notificationHandler
    )
    accountNotificationHandler?.registerCallbackForAllAccounts { [weak self] accountInfo in
      guard let self else { return }
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: appDelegate.getMeta(accountInfo).artworkDownloadManager
      )
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: appDelegate.getMeta(accountInfo).playableDownloadManager
      )
    }

    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        self.refresh()
      }
    )
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    refreshCellMasks()
    refreshBottomFadeMask()
    controlView?.refreshView()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    appDelegate.userStatistics.visited(.popupPlayer)
    // the player overrides its own style, so system style changes are only visible on the window
    if windowStyleObservation == nil {
      windowStyleObservation = view.window?.registerForTraitChanges(
        [UITraitUserInterfaceStyle.self]
      ) { (_: UIWindow, _) in
        self.refreshBackgroundItemArtwork()
      }
    }
    becomeFirstResponder()
    applyDisplayLayout(animated: false)
    reloadData()
    scrollToCurrentlyPlayingRow()
    controlView?.refreshView()
    refresh()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    resignFirstResponder()
  }

  override func viewWillLayoutSubviews() {
    adjustLayoutMargins()
  }

  /// Table view and lyrics layout share the same area, the lyrics layout has its own header row.
  private func setupLyricsLayout() {
    lyricsLayoutView.translatesAutoresizingMaskIntoConstraints = false
    lyricsLayoutView.isHidden = true
    lyricsLayoutView.alpha = 0.0
    view.insertSubview(lyricsLayoutView, aboveSubview: tableView)
    lyricsContainerView.translatesAutoresizingMaskIntoConstraints = false
    lyricsLayoutView.addSubview(lyricsContainerView)
    NSLayoutConstraint.activate([
      lyricsLayoutView.topAnchor.constraint(equalTo: tableView.topAnchor),
      lyricsLayoutView.bottomAnchor.constraint(equalTo: tableView.bottomAnchor),
      lyricsLayoutView.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
      lyricsLayoutView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
      lyricsContainerView.bottomAnchor.constraint(equalTo: lyricsLayoutView.bottomAnchor),
      lyricsContainerView.leadingAnchor.constraint(equalTo: lyricsLayoutView.leadingAnchor),
      lyricsContainerView.trailingAnchor.constraint(equalTo: lyricsLayoutView.trailingAnchor),
    ])

    guard let header = ViewCreator<CurrentlyPlayingTableCell>.createFromNib() else {
      lyricsContainerView.topAnchor.constraint(equalTo: lyricsLayoutView.topAnchor).isActive = true
      return
    }
    lyricsHeaderCell = header
    header.prepare(toWorkOnRootView: self)
    header.backgroundColor = .clear
    header.translatesAutoresizingMaskIntoConstraints = false
    lyricsLayoutView.addSubview(header)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: lyricsLayoutView.topAnchor),
      header.leadingAnchor.constraint(equalTo: lyricsLayoutView.leadingAnchor),
      header.trailingAnchor.constraint(equalTo: lyricsLayoutView.trailingAnchor),
      header.heightAnchor.constraint(equalToConstant: CurrentlyPlayingTableCell.rowHeight),
      lyricsContainerView.topAnchor.constraint(equalTo: header.bottomAnchor),
    ])
  }

  func setLyricsDisplayed(_ isDisplayed: Bool) {
    appDelegate.storage.settings.user.isPlayerLyricsDisplayed = isDisplayed
    if !isDisplayed {
      // leaving the lyrics always shows the cover, also if the queue was shown before
      appDelegate.storage.settings.user.playerDisplayStyle = .large
    }
    applyDisplayLayout(animated: true)
    controlView?.refreshDisplayLyricsButton()
    controlView?.refreshDisplayPlaylistButton()
  }

  /// The lyrics come with the song info, until it is fetched "No Lyrics" would only flash up.
  private(set) var isFetchingSongInfo = false

  func fetchSongInfoAndUpdateViews() {
    guard appDelegate.storage.settings.user.isOnlineMode,
          let song = player.currentlyPlaying?.asSong,
          let account = song.account
    else { return }

    isFetchingSongInfo = true
    Task { @MainActor in
      do {
        try await self.appDelegate.getMeta(account.info).librarySyncer.sync(song: song)
      } catch {
        self.appDelegate.eventLogger.report(topic: "Song Info", error: error)
      }
      self.isFetchingSongInfo = false
      self.refreshCurrentlyPlayingInfoView()
    }
  }

  func reloadData() {
    tableView.reloadData()
    scrollToCurrentlyPlayingRow()
  }

  func scrollToCurrentlyPlayingRow() {
    tableView.scrollToRow(
      at: IndexPath(row: 0, section: PlayerSectionCategory.currentlyPlaying.rawValue),
      at: .top,
      animated: false
    )
  }

  func favoritePressed() {
    switch player.playerMode {
    case .music:
      guard let playableInfo = player.currentlyPlaying else { return }
      if playableInfo.isSong, let account = playableInfo.account {
        Task { @MainActor in
          do {
            try await playableInfo
              .remoteToggleFavorite(
                syncer: self.appDelegate.getMeta(account.info)
                  .librarySyncer
              )
          } catch {
            self.appDelegate.eventLogger.report(topic: "Toggle Favorite", error: error)
          }
          self.refresh()
        }
      } else if let radio = playableInfo.asRadio,
                let siteURL = radio.siteURL {
        UIApplication.shared.open(siteURL)
      }
    case .podcast:
      guard let podcastEpisode = player.currentlyPlaying?.asPodcastEpisode
      else { return }
      let plainDetailsVC = PlainDetailsVC()
      plainDetailsVC.display(podcastEpisode: podcastEpisode, on: self)
      present(plainDetailsVC, animated: true)
    }
  }

  func displayArtistDetail() {
    if let song = player.currentlyPlaying?.asSong, let artist = song.artist,
       let account = artist.account {
      let artistDetailVC = AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist)
      closePopupPlayerAndDisplayInLibraryTab(vc: artistDetailVC)
    }
  }

  func displayAlbumDetail() {
    if let song = player.currentlyPlaying?.asSong, let album = song.album,
       let account = album.account {
      let albumDetailVC = AppStoryboard.Main.segueToAlbumDetail(
        account: account,
        album: album,
        songToScrollTo: song
      )
      closePopupPlayerAndDisplayInLibraryTab(vc: albumDetailVC)
    }
  }

  func displayPodcastDetail() {
    if let podcastEpisode = player.currentlyPlaying?.asPodcastEpisode,
       let podcast = podcastEpisode.podcast,
       let account = podcastEpisode.account {
      let podcastDetailVC = AppStoryboard.Main.segueToPodcastDetail(
        account: account,
        podcast: podcast,
        episodeToScrollTo: podcastEpisode
      )
      closePopupPlayerAndDisplayInLibraryTab(vc: podcastDetailVC)
    }
  }

  func closePopupPlayer() {
    guard let hostingSplitVC = AppDelegate.mainWindowHostVC else { return }
    hostingSplitVC.visualizePopupPlayer(direction: .close, animated: true)
  }

  func closePopupPlayerAndDisplayInLibraryTab(vc: UIViewController) {
    #if targetEnvironment(macCatalyst)
      if view.window?.windowScene?.delegate is MiniPlayerSceneDelegate {
        displayInMainWindowAndCloseMiniPlayer(vc: vc)
        return
      }
    #endif
    guard let hostingSplitVC = AppDelegate.mainWindowHostVC else { return }
    hostingSplitVC.visualizePopupPlayer(direction: .close, animated: true, completion: { () in
      hostingSplitVC.pushNavLibrary(vc: vc)
    })
  }

  #if targetEnvironment(macCatalyst)
    /// The mini player lives in its own window scene: show the content in the main window (opening it if necessary)
    /// and close the mini player afterwards, so it stays open if the main window can't be reached.
    private func displayInMainWindowAndCloseMiniPlayer(vc: UIViewController) {
      if appDelegate.isMainWindowOpen {
        if let mainSession = AppDelegate.mainSceneDelegate?.window?.windowScene?.session {
          UIApplication.shared.requestSceneSessionActivation(
            mainSession,
            userActivity: nil,
            options: nil,
            errorHandler: nil
          )
        }
      } else {
        appDelegate.openMainWindow()
      }
      Task { @MainActor [weak self] in
        // a newly requested main window needs a moment until its content is loaded
        for _ in 0 ..< 50 {
          if let hostVC = AppDelegate.mainWindowHostVC, Self.isLibraryReady(hostVC: hostVC) {
            // the main window's popup player might be expanded, it would cover the pushed screen
            hostVC.visualizePopupPlayer(direction: .close, animated: true, completion: {
              hostVC.pushNavLibrary(vc: vc)
              // the main window exists by now, so closing the mini player won't open another one
              self?.appDelegate.closeMiniPlayer()
              self?.appDelegate.rebuildMainMenu()
            })
            return
          }
          try? await Task.sleep(nanoseconds: 100_000_000)
        }
      }
    }

    private static func isLibraryReady(hostVC: MainSceneHostingViewController) -> Bool {
      guard let splitVC = hostVC as? SplitVC else { return true }
      return splitVC.viewController(for: .secondary) is UINavigationController
    }
  #endif

  func refreshUserQueueSectionHeader() {
    guard let userQueueSectionView = userQueueSectionHeader else { return }
    if player.userQueueCount == 0 {
      userQueueSectionView.hide()
    } else {
      userQueueSectionView.display(
        name: PlayerQueueType.user.description,
        buttonPressAction: clearUserQueue
      )
    }
  }

  func refreshContextQueueSectionHeader() {
    guard let contextNextQueueSectionHeader = contextNextQueueSectionHeader else { return }
    contextNextQueueSectionHeader.refresh()
  }

  // MARK: - UIScrollViewDelegate

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    refreshCellMasks()
    refreshBottomFadeMask()
  }

  /// Fades out the rows at the bottom edge of the list. The mask lives in the bounds of the
  /// scroll view, so its frame follows the content offset.
  func refreshBottomFadeMask() {
    let fadeHeight: CGFloat = 70.0
    let bounds = tableView.bounds
    guard bounds.height > fadeHeight else {
      tableView.layer.mask = nil
      return
    }
    let mask = (tableView.layer.mask as? CAGradientLayer) ?? CAGradientLayer()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    mask.frame = bounds
    mask.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
    let fadeStart = NSNumber(value: Double((bounds.height - fadeHeight) / bounds.height))
    mask.locations = [0.0, fadeStart, 1.0]
    mask.startPoint = CGPoint(x: 0.5, y: 0.0)
    mask.endPoint = CGPoint(x: 0.5, y: 1.0)
    tableView.layer.mask = mask
    CATransaction.commit()
  }

  func refreshCellMasks() {
    guard let topSection = Array(activeDisplayedSectionHeader)
      .sorted(by: { $0.rawValue < $1.rawValue }).first
    else { return }

    let topSectionHeight = tableView(tableView, heightForHeaderInSection: topSection.rawValue)
    let scrollOffset = tableView.contentOffset.y

    for cell in tableView.visibleCells {
      let hiddenFrameHeight = scrollOffset + topSectionHeight - cell.frame.origin.y
      if hiddenFrameHeight >= 0 || hiddenFrameHeight <= cell.frame.size.height {
        if let customCell = cell as? PlayableTableCell {
          customCell.maskCell(fromTop: hiddenFrameHeight)
        }
      }
    }
  }

  func refreshCellsContent() {
    for cell in tableView.visibleCells {
      guard let playableCell = cell as? PlayableTableCell else { continue }
      playableCell.refresh()
    }
  }
}

// MARK: MusicPlayable

extension PopupPlayerVC: MusicPlayable {
  func didStartPlayingFromBeginning() {
    fetchSongInfoAndUpdateViews()
    largeCurrentlyPlayingView?.initializeLyrics()
    applyDisplayLayout(animated: false)
  }

  func didStartPlaying() {
    reloadData()
    refresh()
  }

  func didStopPlaying() {
    reloadData()
    refresh()
  }

  func didPlaylistChange() {
    reloadData()
    refresh()
  }

  func didPause() {}
  func didElapsedTimeChange() {}

  func didLyricsTimeChange(time: CMTime) {
    largeCurrentlyPlayingView?.refreshLyricsTime(time: time)
  }

  func didArtworkChange() {
    refreshCurrentlyPlayingArtworks()
  }

  func didNowPlayingInfoChange() {
    refreshCurrentlyPlayingInfoView()
  }

  func didShuffleChange() {}
  func didRepeatChange() {}
  func didPlaybackRateChange() {}
}
