//
//  SimilarContentFooterView.swift
//  Amperfy
//
//  Created by Chrizz Gelbach on 15.10.26.
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

import AmperfyKit
import UIKit

// MARK: - SimilarContentTile

private class SimilarContentTile: UIControl {
  static let imageSize: CGFloat = 120.0

  private let container: PlayableContainable
  private let onTap: () -> ()

  init(
    container: PlayableContainable,
    theme: ThemePreference,
    isImageCircular: Bool,
    onTap: @escaping () -> ()
  ) {
    self.container = container
    self.onTap = onTap
    super.init(frame: .zero)

    let imageView = EntityImageView(frame: CGRect(
      x: 0,
      y: 0,
      width: Self.imageSize,
      height: Self.imageSize
    ))
    imageView.display(theme: theme, container: container, cornerRadius: .medium)
    // circular image across the whole tile without a colored frame, as the footer itself
    // already sits on the artwork color of the detail screen
    if isImageCircular {
      imageView.setCircularImage(frameColor: { _ in .clear }, inset: 0, isPlaceholderCircular: true)
    }
    imageView.isUserInteractionEnabled = false

    let titleLabel = UILabel()
    titleLabel.font = .preferredFont(forTextStyle: .footnote)
    titleLabel.textColor = .label
    titleLabel.text = container.name
    titleLabel.textAlignment = isImageCircular ? .center : .natural
    let subtitleLabel = UILabel()
    subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.text = container.subtitle
    subtitleLabel.isHidden = container.subtitle == nil
    subtitleLabel.textAlignment = titleLabel.textAlignment

    let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, subtitleLabel])
    stack.axis = .vertical
    stack.spacing = 2
    // gap between the image and the title, like the tiles on Home
    stack.setCustomSpacing(8, after: imageView)
    stack.isUserInteractionEnabled = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      imageView.widthAnchor.constraint(equalToConstant: Self.imageSize),
      imageView.heightAnchor.constraint(equalToConstant: Self.imageSize),
    ])
    addTarget(self, action: #selector(tapped), for: .touchUpInside)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc
  private func tapped() {
    onTap()
  }
}

// MARK: - SimilarContentFooterView

/// Table footer showing horizontally scrollable rows of similar artists and albums.
/// Rows without content are hidden; the whole view is hidden if nothing is left.
/// Selecting an item pushes its detail screen onto the navigation controller of the owner.
class SimilarContentFooterView: UIView {
  private let account: Account
  private weak var owner: UIViewController?
  private let stack = UIStackView()
  private let artistsRow = UIStackView()
  private let albumsRow = UIStackView()
  private let artistsSection: UIView
  private let albumsSection: UIView
  private let backgroundView = UIView()
  /// Padding between the top of the darker background and the first title,
  /// also used as the gap between the content above and the background.
  private static let topPadding: CGFloat = 32

  init(account: Account, owner: UIViewController) {
    self.account = account
    self.owner = owner
    self.artistsSection = Self.createSection(
      title: NSLocalizedString("Similar Artists", comment: ""),
      row: artistsRow
    )
    self.albumsSection = Self.createSection(
      title: NSLocalizedString("You might also like", comment: ""),
      row: albumsRow
    )
    super.init(frame: .zero)
    // darkens whatever background the screen shows, also the artwork color of the detail screens
    backgroundView.backgroundColor = .black.withAlphaComponent(0.15)
    addSubview(backgroundView)

    stack.axis = .vertical
    stack.spacing = 32
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.isLayoutMarginsRelativeArrangement = true
    stack.layoutMargins = UIEdgeInsets(top: 2 * Self.topPadding, left: 0, bottom: 16, right: 0)
    stack.addArrangedSubview(artistsSection)
    stack.addArrangedSubview(albumsSection)
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    artistsSection.isHidden = true
    albumsSection.isHidden = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private var theme: ThemePreference {
    appDelegate.storage.settings.accounts.getSetting(account.info).read.themePreference
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // the footer is the last content of the table, so its background continues below it to the
    // end of the page: into the bottom inset behind the tab bar and the bounce area
    let extensionHeight = max(superview?.bounds.height ?? 0, 1000)
    backgroundView.frame = CGRect(
      x: 0,
      y: Self.topPadding,
      width: bounds.width,
      height: bounds.height - Self.topPadding + extensionHeight
    )
  }

  var hasContent: Bool { !artistsSection.isHidden || !albumsSection.isHidden }

  /// Requests the artists similar to `artist` and the albums similar to `album`.
  /// Similar content is optional, so a failing server agent is only logged and never shown.
  func load(similarTo artist: Artist?, album: Album? = nil) async {
    let librarySyncer = appDelegate.getMeta(account.info).librarySyncer
    if let artist {
      do {
        display(artists: try await librarySyncer.requestSimilarArtists(artist: artist, count: 15))
      } catch {
        appDelegate.eventLogger.report(topic: "Similar Artists", error: error, displayPopup: false)
      }
    }
    if let album {
      do {
        let albums = try await librarySyncer.requestSimilarAlbums(album: album, count: 40)
        display(albums: Array(albums.prefix(12)))
      } catch {
        appDelegate.eventLogger.report(topic: "Similar Albums", error: error, displayPopup: false)
      }
    }
  }

  /// Sizes the footer to fit the width of the table view; the table view only picks up
  /// a changed footer height when the footer is assigned again.
  func layout(in tableView: UITableView) {
    guard tableView.tableFooterView === self, tableView.bounds.width > 0 else { return }
    setNeedsLayout() // the background below the footer follows the height of the table view
    let height = systemLayoutSizeFitting(
      CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    guard frame.size != CGSize(width: tableView.bounds.width, height: height) else { return }
    frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: height)
    tableView.tableFooterView = self
  }

  private func display(artists: [Artist]) {
    fill(
      row: artistsRow,
      section: artistsSection,
      containers: artists,
      isImageCircular: true
    ) { [weak self] artist in
      guard let self else { return }
      owner?.navigationController?.pushViewController(
        AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist),
        animated: true
      )
    }
  }

  private func display(albums: [Album]) {
    fill(row: albumsRow, section: albumsSection, containers: albums) { [weak self] album in
      guard let self else { return }
      owner?.navigationController?.pushViewController(
        AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
        animated: true
      )
    }
  }

  private func fill<T: PlayableContainable>(
    row: UIStackView,
    section: UIView,
    containers: [T],
    isImageCircular: Bool = false,
    onSelect: @escaping (T) -> ()
  ) {
    row.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for container in containers {
      row.addArrangedSubview(SimilarContentTile(
        container: container,
        theme: theme,
        isImageCircular: isImageCircular
      ) {
        onSelect(container)
      })
    }
    section.isHidden = containers.isEmpty
  }

  private static func createSection(title: String, row: UIStackView) -> UIView {
    let titleLabel = UILabel()
    titleLabel.font = .preferredFont(forTextStyle: .title3).bold
    titleLabel.text = title

    row.axis = .horizontal
    row.spacing = 12
    row.alignment = .top
    row.translatesAutoresizingMaskIntoConstraints = false

    let scrollView = UIScrollView()
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.addSubview(row)
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      row.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      row.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      row.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      // the scroll view takes exactly the height of its tiles, so no blank space is left below them
      scrollView.heightAnchor.constraint(equalTo: row.heightAnchor),
    ])
    scrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

    let titleContainer = UIStackView(arrangedSubviews: [titleLabel])
    titleContainer.isLayoutMarginsRelativeArrangement = true
    titleContainer.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

    let section = UIStackView(arrangedSubviews: [titleContainer, scrollView])
    section.axis = .vertical
    section.spacing = 8
    return section
  }
}

extension UIFont {
  fileprivate var bold: UIFont {
    guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
    return UIFont(descriptor: descriptor, size: 0)
  }
}
