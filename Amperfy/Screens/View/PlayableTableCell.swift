//
//  SongTableCell.swift
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

typealias GetPlayContextFromTableCellCallback = (UITableViewCell) -> PlayContext?
typealias GetPlayerIndexFromTableCellCallback = (PlayableTableCell) -> PlayerIndex?

// MARK: - DisplayMode

enum DisplayMode {
  case normal
  case selection
  case reorder
  case add
}

// MARK: - PlayableTableCellStyle

enum PlayableTableCellStyle {
  case none
  case trackNumber
  case artwork
}

// MARK: - PlayableTableCell

@MainActor
class PlayableTableCell: BasicTableCell {
  @IBOutlet
  weak var titleLabel: UILabel!
  @IBOutlet
  weak var artistLabel: UILabel!
  @IBOutlet
  weak var durationLabel: UILabel!
  @IBOutlet
  weak var entityImage: EntityImageView!
  @IBOutlet
  weak var trackNumberLabel: UILabel!
  @IBOutlet
  weak var trackNumberContainer: UIView!
  @IBOutlet
  weak private var cacheIconImage: UIImageView!
  @IBOutlet
  weak private var favoriteIconImage: UIImageView!

  /// aligns the favorite icon with the track number (centered on the title line), otherwise it is
  /// centered in the row
  @IBOutlet
  weak var favoriteTitleAlignConstraint: NSLayoutConstraint!
  @IBOutlet
  weak var labelTrailingCellConstraint: NSLayoutConstraint!
  @IBOutlet
  weak var optionsButton: UIButton!
  @IBOutlet
  weak var deleteButton: UIButton!
  @IBOutlet
  weak var playOverButton: UIButton!
  @IBOutlet
  weak var playOverButtonLeadingConstraint: NSLayoutConstraint!

  private var ratingStackView: UIStackView?
  private var ratingStarViews: [UIImageView] = []

  static let rowHeight: CGFloat = 48 + margin.bottom + margin.top
  private static let touchAnimation = 0.4

  private var style = PlayableTableCellStyle.none
  private var playerIndexCb: GetPlayerIndexFromTableCellCallback?
  private var playContextCb: GetPlayContextFromTableCellCallback?
  private var playable: AbstractPlayable?
  private var download: Download?
  private var rootView: UIViewController?
  private var playIndicator: PlayIndicator?
  private var isDislayAlbumTrackNumberStyle: Bool = false
  private var displayMode: DisplayMode = .normal
  #if targetEnvironment(macCatalyst) // ok
    private var hoverGestureRecognizer: UIHoverGestureRecognizer!
    private var doubleTapGestureRecognizer: UITapGestureRecognizer!
    private var isHovered = false
    private let hoverBackgroundView: UIView = {
      let view = UIView()
      view.translatesAutoresizingMaskIntoConstraints = false
      view.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.6)
      view.layer.cornerRadius = CornerRadius.medium.asCGFloat
      view.isUserInteractionEnabled = false
      view.isHidden = true
      return view
    }()
    private var isNotificationRegistered = false
  #else
    private var singleTapGestureRecognizer: UITapGestureRecognizer!
  #endif

  public var isMarked = false
  private var isDeleteButtonAllowedToBeVisible: Bool {
    (traitCollection.userInterfaceIdiom == .mac) && (playerIndexCb != nil)
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    // This must be called in Main thread
    MainActor.assumeIsolated {
      registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (self: Self, _) in
        // duration, cache icon and label spacing depend on the size class, e.g. after resizing a window
        self.refreshCacheAndDuration()
      }
      registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
        self.playIndicator?.applyStyle()
      }
      playContextCb = nil
      #if targetEnvironment(macCatalyst) // ok
        hoverGestureRecognizer = UIHoverGestureRecognizer(
          target: self,
          action: #selector(hovering(_:))
        )
        self.addGestureRecognizer(hoverGestureRecognizer)
        isHovered = false
        doubleTapGestureRecognizer = UITapGestureRecognizer(
          target: self,
          action: #selector(doubleTap)
        )
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        self.addGestureRecognizer(doubleTapGestureRecognizer)
      #else
        singleTapGestureRecognizer = UITapGestureRecognizer(
          target: self,
          action: #selector(singleTap)
        )
        singleTapGestureRecognizer.numberOfTapsRequired = 1
        // to handle double and single tap recognizer in parallel:
        // singleTapGestureRecognizer.require(toFail: doubleTapGestureRecognizer)
        self.addGestureRecognizer(singleTapGestureRecognizer)
      #endif

      style = PlayableTableCellStyle.none
      deleteButton.tintColor = .red
      playOverButton.layer.cornerRadius = CornerRadius.small.asCGFloat
      selectionStyle = .none
      setupRatingStars()
      resetForReuse()
    }
  }

  private func setupRatingStars() {
    let stackView = UIStackView()
    stackView.axis = .horizontal
    stackView.spacing = -2 // Negative spacing to put stars closer together
    stackView.alignment = .center
    stackView.distribution = .fill
    stackView.translatesAutoresizingMaskIntoConstraints = false

    // Create 5 star image views
    for _ in 0 ..< 5 {
      let starView = UIImageView()
      starView.contentMode = .scaleAspectFit
      starView.translatesAutoresizingMaskIntoConstraints = false
      starView.image = .starEmpty
      starView.tintColor = UIColor(red: 0.882, green: 0.686, blue: 0.255, alpha: 1.0) // #e1af41
      let starSize: CGFloat = 10
      NSLayoutConstraint.activate([
        starView.widthAnchor.constraint(equalToConstant: starSize),
        starView.heightAnchor.constraint(equalToConstant: starSize),
      ])
      ratingStarViews.append(starView)
      stackView.addArrangedSubview(starView)
    }

    contentView.addSubview(stackView)

    NSLayoutConstraint.activate([
      stackView.trailingAnchor.constraint(equalTo: optionsButton.trailingAnchor, constant: -8),
      stackView.topAnchor.constraint(equalTo: optionsButton.bottomAnchor, constant: -8),
    ])

    ratingStackView = stackView
  }

  private func updateRatingDisplay(rating: Int) {
    // Show the LAST N stars (right-aligned) instead of first N
    // This keeps stars right-justified regardless of rating
    let startIndex = 5 - rating
    for (index, starView) in ratingStarViews.enumerated() {
      starView.isHidden = index < startIndex
      starView.image = .starFill
    }

    // Only show rating if song has a rating > 0
    ratingStackView?.isHidden = (rating == 0)
  }

  func resetForReuse() {
    playIndicator?.reset()
    deleteButton.isHidden = true
    playOverButton.isHidden = true
    trackNumberLabel.isHidden = false
    ratingStackView?.isHidden = true
    // Reset all stars for next use
    for starView in ratingStarViews {
      starView.isHidden = false
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    resetForReuse()
  }

  #if targetEnvironment(macCatalyst) // ok
    private func register() {
      guard !isNotificationRegistered else { return }
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(playerPlay(notification:)),
        name: .playerPlay,
        object: nil
      )
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(playerPause(notification:)),
        name: .playerPause,
        object: nil
      )
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(playerStop(notification:)),
        name: .playerStop,
        object: nil
      )
      isNotificationRegistered = true
    }
  #endif

  /// Black or white color for secondary texts (track number, artist, duration) on custom backgrounds.
  var contentColorOverride: UIColor? {
    didSet {
      playIndicator?.colorOverride = contentColorOverride
      playIndicator?.applyStyle()
    }
  }

  func display(
    playable: AbstractPlayable,
    displayMode: DisplayMode = .normal,
    playContextCb: GetPlayContextFromTableCellCallback?,
    rootView: UIViewController,
    playerIndexCb: GetPlayerIndexFromTableCellCallback? = nil,
    isDislayAlbumTrackNumberStyle: Bool = false,
    download: Download? = nil,
    isMarked: Bool = false
  ) {
    if playIndicator?.rootViewTypeName != rootView.typeName {
      playIndicator = PlayIndicator(rootViewTypeName: rootView.typeName)
      playIndicator?.colorOverride = contentColorOverride
    }

    self.playable = playable
    self.displayMode = displayMode
    self.playContextCb = playContextCb
    self.playerIndexCb = playerIndexCb
    self.rootView = rootView
    self.isDislayAlbumTrackNumberStyle = isDislayAlbumTrackNumberStyle
    self.download = download
    self.isMarked = isMarked

    #if targetEnvironment(macCatalyst) // ok
      hoverGestureRecognizer.isEnabled = (displayMode == .normal)
      isHovered = false
      doubleTapGestureRecognizer.isEnabled = (displayMode == .normal)
      register()
    #else
      singleTapGestureRecognizer.isEnabled = (displayMode == .normal)
    #endif
    backgroundColor = .clear
    refresh()
  }

  private func configureStyle(playable: AbstractPlayable, newStyle: PlayableTableCellStyle) {
    // adjust style only if it has changed
    guard newStyle != style else { return }

    switch newStyle {
    case .trackNumber:
      configureTrackNumberLabel()
      playIndicator?.willDisplayIndicatorCB = { [weak self] () in
        guard let self = self else { return }
        trackNumberLabel.text = ""
      }
      playIndicator?.willHideIndicatorCB = { [weak self] () in
        guard let self = self else { return }
        configureTrackNumberLabel()
      }
      trackNumberContainer.isHidden = false
      entityImage.isHidden = true
      favoriteTitleAlignConstraint.priority = UILayoutPriority(999)
    case .artwork:
      playIndicator?.willDisplayIndicatorCB = nil
      playIndicator?.willHideIndicatorCB = nil
      trackNumberContainer.isHidden = true
      entityImage.isHidden = false
      favoriteTitleAlignConstraint.priority = UILayoutPriority(1)
    case .none:
      break // do nothing
    }
  }

  override var usesSystemHorizontalMargins: Bool { true }

  /// separator starts at the title/artist text instead of the track number
  override var separatorLeadingView: UIView? { isDislayAlbumTrackNumberStyle ? titleLabel : nil }

  private func configurePlayIndicator(playable: AbstractPlayable?) {
    guard let playable = playable else {
      playIndicator?.reset()
      return
    }

    if isDislayAlbumTrackNumberStyle {
      playIndicator?.display(playable: playable, rootView: trackNumberLabel)
    } else {
      if playerIndexCb == nil {
        playIndicator?.display(playable: playable, rootView: entityImage, isOnImage: true)
      } else {
        // don't show play indicator on PopupPlayer
        playIndicator?.reset()
      }
    }
  }

  func refresh() {
    guard let playable = playable else { return }
    titleLabel.text = playable.title
    artistLabel.text = playable.creatorName

    configureStyle(
      playable: playable,
      newStyle: isDislayAlbumTrackNumberStyle ? .trackNumber : .artwork
    )
    entityImage.display(
      theme: appDelegate.storage.settings.accounts.getSetting(playable.account?.info).read
        .themePreference,
      container: playable
    )
    configurePlayIndicator(playable: playable)

    if displayMode == .selection {
      let img = UIImageView(image: isMarked ? .checkmark : .circle)
      img.tintColor = isMarked ? appDelegate.storage.settings.accounts
        .getSetting(playable.account?.info).read
        .themePreference
        .asColor : .secondaryLabelColor
      accessoryView = img
    } else if displayMode == .add {
      let img = UIImageView(image: isMarked ? .checkmark : .plusCircle)
      img.tintColor = appDelegate.storage.settings.accounts.getSetting(playable.account?.info).read
        .themePreference
        .asColor
      accessoryView = img
    } else if displayMode == .reorder || playerIndexCb != nil {
      let img = UIImageView(image: .bars)
      img.tintColor = .labelColor
      accessoryView = img
    } else if let download = download {
      if download.error != nil {
        let img = UIImageView(image: .exclamation)
        img.tintColor = .labelColor
        accessoryView = img
      } else if download.isFinishedSuccessfully {
        let img = UIImageView(image: .check)
        img.tintColor = .labelColor
        accessoryView = img
      } else if download.isDownloading {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.tintColor = .labelColor
        accessoryView = spinner
      } else {
        accessoryView = nil
      }
    } else {
      accessoryView = nil
    }

    refreshSubtitleColor()
    refreshCacheAndDuration()

    // Update rating display for songs (only if setting is enabled)
    if appDelegate.storage.settings.user.isShowRating, let song = playable.asSong {
      updateRatingDisplay(rating: song.rating)
    } else {
      ratingStackView?.isHidden = true
    }
  }

  private func configureTrackNumberLabel() {
    guard let playable = playable else { return }
    trackNumberLabel.text = playable.track > 0 ? "\(playable.track)" : ""
  }

  func refreshCacheAndDuration() {
    guard let playable = playable else { return }
    favoriteIconImage.isHidden = !playable.isFavorite

    // the duration is always shown in regular width, in compact width only if enabled in settings
    let isDurationVisible = !playable.isRadio &&
      (
        traitCollection.horizontalSizeClass == .regular ||
          appDelegate.storage.settings.user.isShowSongDuration
      )
    let isDisplayOptionButton = (playContextCb != nil) && (playerIndexCb == nil)
    optionsButton.isHidden = !isDisplayOptionButton
    if isDisplayOptionButton {
      optionsButton.showsMenuAsPrimaryAction = true
      optionsButton.imageView?.tintColor = .label
      if let rootView = rootView {
        let playContext = playContextCb != nil ? { self.playContextCb?(self) } : nil
        let playIndex = playerIndexCb != nil ? { self.playerIndexCb?(self) } : nil
        optionsButton.menu = UIMenu.lazyMenu {
          EntityPreviewActionBuilder(
            container: playable,
            on: rootView,
            playContextCb: playContext,
            playerIndexCb: playIndex
          ).createMenuActions()
        }
      }
    }

    // The cache icon, duration and options button are arranged in a stack view, hidden ones
    // collapse. The labels end before that stack.
    // Stars are positioned at optionsButton.trailingAnchor - 8, extending left.
    // Each star is 10pt with -2pt spacing: width = rating * 8 + 2
    // Without the duration the stack is only as wide as the options button (34pt), so the title
    // needs more space if the stars are wider than that.
    let labelToAccessoriesGap = 8.0
    let songRating = playable.asSong?.rating ?? 0
    let isRatingVisible = appDelegate.storage.settings.user.isShowRating && songRating > 0
    let starWidth = CGFloat(songRating * 8 + 2)
    let ratingExtraSpace: CGFloat = (isRatingVisible && !isDurationVisible) ?
      max(0, starWidth - 30) : 0.0
    labelTrailingCellConstraint.constant = labelToAccessoriesGap + ratingExtraSpace

    cacheIconImage.isHidden = !playable.isCached
    durationLabel.isHidden = !isDurationVisible
    if isDurationVisible {
      durationLabel.text = playable.duration.asColonDurationString
    }
  }

  private func refreshSubtitleColor() {
    // follows the title's font color
    favoriteIconImage.tintColor = contentColorOverride ?? UIColor.labelColor
    if let contentColor = contentColorOverride {
      // screens with a custom background color need explicit, readable text colors
      let secondaryColor = contentColor.withAlphaComponent(0.7)
      cacheIconImage.tintColor = secondaryColor
      artistLabel.textColor = secondaryColor
      durationLabel.textColor = secondaryColor
      trackNumberLabel.textColor = secondaryColor
    } else if playerIndexCb != nil {
      cacheIconImage.tintColor = UIColor.labelColor
      artistLabel.textColor = UIColor.labelColor
      durationLabel.textColor = UIColor.labelColor
    } else {
      cacheIconImage.tintColor = UIColor.secondaryLabelColor
      artistLabel.textColor = UIColor.secondaryLabelColor
      durationLabel.textColor = UIColor.secondaryLabelColor
    }
  }

  func playThisSong() {
    guard let playable = playable else { return }
    if let playerIndex = playerIndexCb?(self) {
      appDelegate.player.play(playerIndex: playerIndex)
    } else if let context = playContextCb?(self),
              playable.isCached || appDelegate.storage.settings.user.isOnlineMode {
      animateActivation()
      hideSearchBarKeyboardInRootView()
      Haptics.success.vibrate(isHapticsEnabled: appDelegate.storage.settings.user.isHapticsEnabled)
      appDelegate.player.play(context: context)
    }
  }

  private func hideSearchBarKeyboardInRootView() {
    if let basicRootView = rootView as? BasicTableViewController {
      basicRootView.searchController.searchBar.endEditing(true)
    }
  }

  #if targetEnvironment(macCatalyst) // ok
    @IBAction
    func deleteButtonPressed(_ sender: Any) {
      if let playerIndexCb = playerIndexCb,
         let playerIndex = playerIndexCb(self),
         let queueVC = rootView as? QueueVC,
         let tableView = queueVC.tableView {
        queueVC.tableView(tableView, commit: .delete, forRowAt: playerIndex.asIndexPath)
      }
      if let playerIndexCb = playerIndexCb,
         let playerIndex = playerIndexCb(self),
         let popupPlayerVC = rootView as? PopupPlayerVC,
         let tableView = popupPlayerVC.tableView {
        popupPlayerVC.tableView(tableView, commit: .delete, forRowAt: playerIndex.asIndexPath)
      }
    }

    @IBAction
    func playButtonPressed(_ sender: Any) {
      if appDelegate.player.currentlyPlaying == playable,
         appDelegate.player.isPlaying {
        appDelegate.player.pause()
      } else if appDelegate.player.currentlyPlaying == playable {
        appDelegate.player.play()
      } else {
        playThisSong()
      }
      refreshHoverStyle()
    }

    /// 1.0 keeps the table's background color, smaller values make the hover darker.
    private static let hoverBrightnessFactor: CGFloat = 0.8

    /// The hover uses the background color of the table view the cell is displayed in, darkened.
    private var tableBackgroundColor: UIColor {
      (enclosingTableView?.backgroundColor ?? .secondarySystemGroupedBackground)
        .darkened(brightnessFactor: Self.hoverBrightnessFactor)
    }

    private func installHoverBackgroundIfNeeded() {
      guard hoverBackgroundView.superview == nil else { return }
      contentView.insertSubview(hoverBackgroundView, at: 0)
      let guide = contentView.layoutMarginsGuide
      NSLayoutConstraint.activate([
        hoverBackgroundView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
        hoverBackgroundView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: 10),
        hoverBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
        hoverBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      ])
    }

    func refreshHoverStyle() {
      if isHovered {
        playIndicator?.reset()
        if isDeleteButtonAllowedToBeVisible {
          deleteButton.isHidden = false
        } else {
          var buttonImg = UIImage()
          if appDelegate.player.currentlyPlaying == playable,
             appDelegate.player.isPlaying {
            if appDelegate.player.isStopInsteadOfPause {
              buttonImg = UIImage.stop
            } else {
              buttonImg = UIImage.pause
            }
          } else {
            buttonImg = UIImage.play
          }
          // the button is inset in the track number slot, but covers the whole cover
          playOverButtonLeadingConstraint.constant = isDislayAlbumTrackNumberStyle ? 12 : 0
          if isDislayAlbumTrackNumberStyle {
            trackNumberLabel.isHidden = true
            playOverButton.layer.backgroundColor = nil
            playOverButton.imageView?.tintColor = appDelegate.storage.settings.accounts
              .getSetting(playable?.account?.info).read.themePreference
              .asColor
          } else {
            playOverButton.layer.backgroundColor = UIColor.imageOverlayBackground.cgColor
            playOverButton.imageView?.tintColor = .white
          }
          playOverButton.setImage(buttonImg, for: UIControl.State.normal)
          playOverButton.isHidden = false
        }
        cacheIconImage.tintColor = appDelegate.storage.settings.accounts
          .getSetting(playable?.account?.info).read.themePreference.asColor
        optionsButton.imageView?.tintColor = appDelegate.storage.settings.accounts
          .getSetting(playable?.account?.info).read.themePreference.asColor
        if isDislayAlbumTrackNumberStyle {
          // translucent hover limited to the content margins instead of the full cell width
          installHoverBackgroundIfNeeded()
          hoverBackgroundView.backgroundColor = tableBackgroundColor.withAlphaComponent(0.6)
          hoverBackgroundView.isHidden = false
        } else {
          backgroundColor = (rootView is PopupPlayerVC) ?
            tableBackgroundColor.withAlphaComponent(0.2) :
            tableBackgroundColor
        }
      } else {
        playOverButton.isHidden = true
        if isDislayAlbumTrackNumberStyle {
          trackNumberLabel.isHidden = false
        }
        configurePlayIndicator(playable: playable)
        deleteButton.isHidden = true
        refreshSubtitleColor()
        optionsButton.imageView?.tintColor = .label
        backgroundColor = .clear
        hoverBackgroundView.isHidden = true
      }
    }

    @objc
    func hovering(_ recognizer: UIHoverGestureRecognizer) {
      switch recognizer.state {
      case .began:
        isHovered = true
        refreshHoverStyle()
      case .ended:
        isHovered = false
        refreshHoverStyle()
      default:
        if !isHovered {
          isHovered = true
          refreshHoverStyle()
        }
      }
    }

    @objc
    func doubleTap(sender: UITapGestureRecognizer) {
      switch sender.state {
      case .ended:
        if displayMode == .normal {
          playThisSong()
        }
      default:
        break
      }
    }

    @objc
    private func playerPlay(notification: Notification) {
      guard isHovered else { return }
      refreshHoverStyle()
    }

    @objc
    private func playerPause(notification: Notification) {
      guard isHovered else { return }
      refreshHoverStyle()
    }

    @objc
    private func playerStop(notification: Notification) {
      guard isHovered else { return }
      refreshHoverStyle()
    }

  #else

    @objc
    func singleTap(sender: UITapGestureRecognizer) {
      switch sender.state {
      case .ended:
        if displayMode == .normal {
          playThisSong()
        }
      default:
        break
      }
    }
  #endif
}
