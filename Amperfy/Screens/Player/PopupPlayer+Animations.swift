//
//  PopupPlayer+Animations.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 12.02.24.
//  Copyright (c) 2024 Maximilian Bauer. All rights reserved.
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

extension PopupPlayerVC {
  static let displaStyleAnimationDuration = TimeInterval(0.2)

  func switchDisplayStyleOptionPersistent() {
    appDelegate.userStatistics.usedAction(.changePlayerDisplayStyle)
    var displayStyle = appDelegate.storage.settings.user.playerDisplayStyle
    displayStyle.switchToNextStyle()
    appDelegate.storage.settings.user.playerDisplayStyle = displayStyle
    changeDisplayStyleVisually(to: displayStyle, animated: true)
  }

  func changeDisplayStyleVisually(to displayStyle: PlayerDisplayStyle, animated: Bool = true) {
    var viewToDisapper: UIView?
    var artworkToDisapper: UIView?
    var containerToDisapper: UIView?
    var favoriteToDisapper: UIView?
    var optionsToDisapper: UIView?

    var viewToApper: UIView?
    var artworkToApper: UIView?
    var containerToApper: UIView?
    var favoriteToApper: UIView?
    var optionsToApper: UIView?

    switch displayStyle {
    case .compact:
      viewToDisapper = largePlayerPlaceholderView
      artworkToDisapper = largeCurrentlyPlayingView?.artworkImage
      containerToDisapper = largeCurrentlyPlayingView
      favoriteToDisapper = largeCurrentlyPlayingView?.favoriteButton
      optionsToDisapper = largeCurrentlyPlayingView?.optionsButton
      viewToApper = tableView
      artworkToApper = currentlyPlayingTableCell?.artworkImage
      containerToApper = currentlyPlayingTableCell
      favoriteToApper = currentlyPlayingTableCell?.favoriteButton
      optionsToApper = currentlyPlayingTableCell?.optionsButton
      scrollToCurrentlyPlayingRow()
      currentlyPlayingTableCell?.refresh()
    case .large:
      viewToDisapper = tableView
      artworkToDisapper = currentlyPlayingTableCell?.artworkImage
      containerToDisapper = currentlyPlayingTableCell
      favoriteToDisapper = currentlyPlayingTableCell?.favoriteButton
      optionsToDisapper = currentlyPlayingTableCell?.optionsButton
      viewToApper = largePlayerPlaceholderView
      artworkToApper = largeCurrentlyPlayingView?.artworkImage
      containerToApper = largeCurrentlyPlayingView
      favoriteToApper = largeCurrentlyPlayingView?.favoriteButton
      optionsToApper = largeCurrentlyPlayingView?.optionsButton
      largeCurrentlyPlayingView?.refresh()
    }

    guard let viewToDisapper = viewToDisapper,
          let viewToApper = viewToApper
    else { return }

    if animated {
      guard let artworkToDisapper = artworkToDisapper,
            let artworkToApper = artworkToApper,
            let favoriteToDisapper = favoriteToDisapper,
            let favoriteToApper = favoriteToApper,
            let optionsToDisapper = optionsToDisapper,
            let optionsToApper = optionsToApper
      else { return }

      // 1. Force autolayout to layout
      // the containers, not only the artwork: their margins decide where the artwork ends up
      containerToDisapper?.layoutIfNeeded()
      containerToApper?.layoutIfNeeded()
      artworkToApper.layoutIfNeeded()
      // 2. Calculate source and target frames
      let artworkSourceFrame = frameInsideThePlaceholder(of: artworkToDisapper)
      let artworkTargetFrame = frameInsideThePlaceholder(of: artworkToApper)
      // 3. Create fake image and animate it
      animateArtwork(
        image: largeCurrentlyPlayingView?.artworkImage.image,
        sourceView: artworkToDisapper,
        targetView: artworkToApper,
        sourceFrame: artworkSourceFrame,
        targetFrame: artworkTargetFrame
      )

      favoriteToApper.layoutIfNeeded()
      let favoriteSourceFrame = frameInsideThePlaceholder(of: favoriteToDisapper)
      let favoriteTargetFrame = frameInsideThePlaceholder(of: favoriteToApper)
      animateFavorite(
        sourceView: favoriteToDisapper,
        targetView: favoriteToApper,
        sourceFrame: favoriteSourceFrame,
        targetFrame: favoriteTargetFrame
      )

      optionsToApper.layoutIfNeeded()
      let optionsSourceFrame = frameInsideThePlaceholder(of: optionsToDisapper)
      let optionsTargetFrame = frameInsideThePlaceholder(of: optionsToApper)
      animateOptions(
        sourceView: optionsToDisapper,
        targetView: optionsToApper,
        sourceFrame: optionsSourceFrame,
        targetFrame: optionsTargetFrame
      )

      viewToDisapper.isHidden = false
      viewToApper.isHidden = false
      UIView.animate(
        withDuration: Self.displaStyleAnimationDuration * 2 / 3,
        delay: 0,
        animations: ({
          viewToDisapper.alpha = 0.0
        }),
        completion: nil
      )
      UIView.animate(
        withDuration: Self.displaStyleAnimationDuration * 2 / 3,
        delay: Self.displaStyleAnimationDuration / 3,
        animations: ({
          viewToApper.alpha = 1.0
        }),
        completion: nil
      )

    } else {
      viewToDisapper.alpha = 0.0
      viewToApper.alpha = 1.0
      viewToDisapper.isHidden = true
      viewToApper.isHidden = false
    }
  }

  /// Frame of the view in the coordinate space of the player, limited to the placeholder.
  private func frameInsideThePlaceholder(of view: UIView) -> CGRect {
    limitSizeToInsideThePlaceholder(
      targetFrame: self.view.convert(view.bounds, from: view),
      placeholderFrame: largePlayerPlaceholderView.frame
    )
  }

  private func limitSizeToInsideThePlaceholder(
    targetFrame: CGRect,
    placeholderFrame: CGRect
  )
    -> CGRect {
    if targetFrame.origin.y < placeholderFrame.origin.y - targetFrame.height {
      return CGRect(
        x: targetFrame.origin.x,
        y: placeholderFrame.origin.y - targetFrame.height,
        width: targetFrame.width,
        height: targetFrame.height
      )
    } else if targetFrame.origin.y > placeholderFrame.origin.y + placeholderFrame.height {
      return CGRect(
        x: targetFrame.origin.x,
        y: placeholderFrame.origin.y + placeholderFrame.height,
        width: targetFrame.width,
        height: targetFrame.height
      )
    } else {
      return targetFrame
    }
  }

  private func animateArtwork(
    image: UIImage?,
    sourceView: UIView,
    targetView: UIView,
    sourceFrame: CGRect,
    targetFrame: CGRect
  ) {
    // 3. Create a replica of the artwork
    let fakeImageView = RoundedImage(frame: sourceFrame)
    fakeImageView.backgroundColor = .clear
    fakeImageView.image = image
    fakeImageView.contentMode = .scaleAspectFill
    fakeImageView.clipsToBounds = true
    fakeImageView.alpha = sourceView.alpha
    fakeImageView.layer.cornerRadius = sourceView.layer.cornerRadius

    // animate alpha for active lyrics view
    UIView.animate(withDuration: Self.displaStyleAnimationDuration, delay: 0, animations: {
      fakeImageView.alpha = targetView.alpha
      fakeImageView.layer.cornerRadius = targetView.layer.cornerRadius
    }, completion: { _ in
      fakeImageView.alpha = targetView.alpha
    })

    animatePlayStyleObject(
      object: fakeImageView,
      sourceView: sourceView,
      targetView: targetView,
      sourceFrame: sourceFrame,
      targetFrame: targetFrame
    )
  }

  private func animateFavorite(
    sourceView: UIView,
    targetView: UIView,
    sourceFrame: CGRect,
    targetFrame: CGRect
  ) {
    let fakeButton = UIButton(frame: sourceFrame)
    refreshFavoriteButton(button: fakeButton)
    animatePlayStyleObject(
      object: fakeButton,
      sourceView: sourceView,
      targetView: targetView,
      sourceFrame: sourceFrame,
      targetFrame: targetFrame
    )
  }

  private func animateOptions(
    sourceView: UIView,
    targetView: UIView,
    sourceFrame: CGRect,
    targetFrame: CGRect
  ) {
    let fakeButton = UIButton(frame: sourceFrame)
    refreshOptionButton(button: fakeButton, rootView: self)
    animatePlayStyleObject(
      object: fakeButton,
      sourceView: sourceView,
      targetView: targetView,
      sourceFrame: sourceFrame,
      targetFrame: targetFrame
    )
  }

  private func animatePlayStyleObject(
    object: UIView,
    sourceView: UIView,
    targetView: UIView,
    sourceFrame: CGRect,
    targetFrame: CGRect
  ) {
    sourceView.isHidden = true
    targetView.isHidden = true

    view.addSubview(object)

    UIView.animate(withDuration: Self.displaStyleAnimationDuration, delay: 0, animations: {
      object.frame = targetFrame
    }, completion: { _ in
      sourceView.isHidden = false
      targetView.isHidden = false
      object.removeFromSuperview()
    })
  }
}
