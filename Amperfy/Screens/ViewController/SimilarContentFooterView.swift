//
//  SimilarContentFooterView.swift
//  Amperfy
//
//  Created by Chrizz Gelbach on 15.10.26.
//  Copyright (c) 2025 Chrizz Gelbach. All rights reserved.
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

  init(container: PlayableContainable, theme: ThemePreference, onTap: @escaping () -> ()) {
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
    imageView.isUserInteractionEnabled = false

    let titleLabel = UILabel()
    titleLabel.font = .preferredFont(forTextStyle: .footnote)
    titleLabel.textColor = .label
    titleLabel.text = container.name
    let subtitleLabel = UILabel()
    subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.text = container.subtitle
    subtitleLabel.isHidden = container.subtitle == nil

    let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, subtitleLabel])
    stack.axis = .vertical
    stack.spacing = 2
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
class SimilarContentFooterView: UIView {
  private let theme: ThemePreference
  private let stack = UIStackView()
  private let artistsRow = UIStackView()
  private let albumsRow = UIStackView()
  private let artistsSection: UIView
  private let albumsSection: UIView

  var onArtistSelected: ((Artist) -> ())?
  var onAlbumSelected: ((Album) -> ())?

  init(theme: ThemePreference) {
    self.theme = theme
    self.artistsSection = Self.createSection(
      title: NSLocalizedString("Similar Artists", comment: ""),
      row: artistsRow
    )
    self.albumsSection = Self.createSection(
      title: NSLocalizedString("You might also like", comment: ""),
      row: albumsRow
    )
    super.init(frame: .zero)

    stack.axis = .vertical
    stack.spacing = 32
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.isLayoutMarginsRelativeArrangement = true
    stack.layoutMargins = UIEdgeInsets(top: 32, left: 0, bottom: 16, right: 0)
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

  var hasContent: Bool { !artistsSection.isHidden || !albumsSection.isHidden }

  func display(artists: [Artist]) {
    fill(row: artistsRow, section: artistsSection, containers: artists) { [weak self] artist in
      self?.onArtistSelected?(artist)
    }
  }

  func display(albums: [Album]) {
    fill(row: albumsRow, section: albumsSection, containers: albums) { [weak self] album in
      self?.onAlbumSelected?(album)
    }
  }

  private func fill<T: PlayableContainable>(
    row: UIStackView,
    section: UIView,
    containers: [T],
    onSelect: @escaping (T) -> ()
  ) {
    row.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for container in containers {
      row.addArrangedSubview(SimilarContentTile(container: container, theme: theme) {
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
