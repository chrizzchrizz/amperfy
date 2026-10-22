//
//  LibraryEntityImage.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 10.06.21.
//  Copyright (c) 2021 Maximilian Bauer. All rights reserved.
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

import CoreData
import ImageIO
import UIKit

extension LibraryEntityImage {
  // Cache should not be used between different instances -> iOS and Carplay
  static public func getImageToDisplayImmediately(
    libraryEntity: AbstractLibraryEntity,
    themePreference: ThemePreference,
    artworkDisplayPreference: ArtworkDisplayPreference,
    useCache: Bool
  )
    -> UIImage {
    if let artworkImagePath = libraryEntity.imagePath(
      setting: artworkDisplayPreference
    ) {
      if useCache, let cachedImg = Self.cachedImage(
        imagePath: artworkImagePath,
        minPixelSize: 0
      )?.image {
        return cachedImg
      } else if let directlyLoadedImage = UIImage(named: artworkImagePath) {
        return directlyLoadedImage
      }
    }
    return UIImage.getGeneratedArtwork(
      theme: themePreference,
      artworkType: libraryEntity.getDefaultArtworkType()
    )
  }
}

// MARK: - LibraryEntityImage

@MainActor
public class LibraryEntityImage: RoundedImage {
  /// Decoded artworks, keyed by image path and pixel size; a decoded bitmap takes 4 bytes per pixel.
  static private let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.totalCostLimit = 100 * 1024 * 1024
    return cache
  }()

  /// Maximum pixel sizes an artwork is decoded with, so a small tile does not keep the
  /// full resolution artwork in memory.
  static private let pixelSizes = [256, 512, 1024, 2048]

  private let appDelegate: AmperKit

  private var entity: AbstractLibraryEntity?
  private var standaloneArtwork: Artwork?
  private var backupArtworkType: ArtworkType?
  private var accountNotificationHandler: AccountNotificationHandler?
  /// Pixel size of the shown artwork, 0 while the placeholder is shown
  private var shownPixelSize = 0
  /// Image path and pixel size of the artwork that is being loaded
  private var loadingCacheKey: String?

  /// True if the generated placeholder is shown because there is no artwork
  /// (false while an existing artwork is still loading).
  public private(set) var isShowingPlaceholder = false

  /// Called whenever the shown image changes, e.g. when the loaded artwork replaces the placeholder.
  public var imageDidChange: ((UIImage?) -> ())?

  override public var image: UIImage? {
    didSet { imageDidChange?(image) }
  }

  required public init?(coder: NSCoder) {
    self.appDelegate = AmperKit.shared
    super.init(coder: coder)
    self.accountNotificationHandler = AccountNotificationHandler(
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
  }

  override public init(frame: CGRect) {
    self.appDelegate = AmperKit.shared
    super.init(frame: .zero)
    self.accountNotificationHandler = AccountNotificationHandler(
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
  }

  public func display(entity: AbstractLibraryEntity) {
    self.entity = entity
    standaloneArtwork = nil
    backupArtworkType = entity.getDefaultArtworkType()
    refresh()
  }

  public func displayAndUpdate(entity: AbstractLibraryEntity) {
    guard self.entity != entity else { return }

    display(entity: entity)
    if let artwork = entity.artwork, let accountInfo = entity.account?.info {
      appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
    }
  }

  /// Displays an artwork that is not owned by an AbstractLibraryEntity (e.g. playlist server cover)
  public func displayAndUpdate(artwork: Artwork, artworkType: ArtworkType) {
    guard standaloneArtwork != artwork else { return }

    entity = nil
    standaloneArtwork = artwork
    backupArtworkType = artworkType
    refresh()
    if let accountInfo = artwork.account?.info {
      appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
    }
  }

  internal func display(image: UIImage) {
    isShowingPlaceholder = false
    shownPixelSize = 0
    self.image = image
    entity = nil
    standaloneArtwork = nil
  }

  public func display(artworkType: ArtworkType) {
    backupArtworkType = artworkType
    entity = nil
    standaloneArtwork = nil
    refresh()
  }

  private var placeholderImage: UIImage {
    var theme = appDelegate.storage.settings.accounts.activeSetting.read.themePreference
    if let accountInfo = entity?.account?.info ?? standaloneArtwork?.account?.info {
      theme = appDelegate.storage.settings.accounts.getSetting(accountInfo).read.themePreference
    }
    return UIImage.getGeneratedArtwork(
      theme: theme,
      artworkType: backupArtworkType ?? .song
    )
  }

  private var entityImagePathToDisplay: String? {
    var artworkDisplayPreference = appDelegate.storage.settings.accounts.activeSetting.read
      .artworkDisplayPreference
    if let accountInfo = entity?.account?.info ?? standaloneArtwork?.account?.info {
      artworkDisplayPreference = appDelegate.storage.settings.accounts.getSetting(accountInfo).read
        .artworkDisplayPreference
    }
    if let entity {
      return entity.imagePath(setting: artworkDisplayPreference)
    }
    return standaloneArtwork?.imagePath
  }

  override public func layoutSubviews() {
    super.layoutSubviews()
    // the view can get larger after the artwork was shown, e.g. when it is laid out the first time
    if shownPixelSize > 0, loadingCacheKey == nil, requiredPixelSize > shownPixelSize {
      refresh()
    }
  }

  /// Smallest pixel size that covers the view on the screen
  private var requiredPixelSize: Int {
    let pixels = max(bounds.width, bounds.height) * traitCollection.displayScale
    return Self.pixelSizes.first { CGFloat($0) >= pixels } ?? Self.pixelSizes.last!
  }

  private static func cacheKey(imagePath: String, pixelSize: Int) -> String {
    "\(imagePath)|\(pixelSize)"
  }

  /// The smallest cached artwork with at least `minPixelSize`
  private static func cachedImage(
    imagePath: String,
    minPixelSize: Int
  )
    -> (image: UIImage, pixelSize: Int)? {
    for pixelSize in pixelSizes where pixelSize >= minPixelSize {
      if let image = cache.object(forKey: cacheKey(
        imagePath: imagePath,
        pixelSize: pixelSize
      ) as NSString) {
        return (image, pixelSize)
      }
    }
    return nil
  }

  private func refresh() {
    let imagePathToDisplay = entityImagePathToDisplay
    let pixelSize = requiredPixelSize

    if let imagePathToDisplay,
       let cached = Self.cachedImage(imagePath: imagePathToDisplay, minPixelSize: pixelSize) {
      isShowingPlaceholder = false
      shownPixelSize = cached.pixelSize
      image = cached.image
      return
    }

    // a smaller artwork is shown until the required size is loaded
    if let imagePathToDisplay,
       let smaller = Self.cachedImage(imagePath: imagePathToDisplay, minPixelSize: 0) {
      isShowingPlaceholder = false
      shownPixelSize = smaller.pixelSize
      image = smaller.image
    } else {
      isShowingPlaceholder = imagePathToDisplay == nil
      shownPixelSize = 0
      image = placeholderImage
    }
    guard let imagePathToDisplay else { return }
    loadImage(imagePath: imagePathToDisplay)
  }

  private func loadImage(imagePath: String, pixelSize: Int? = nil) {
    let pixelSize = pixelSize ?? requiredPixelSize
    let cacheKey = Self.cacheKey(imagePath: imagePath, pixelSize: pixelSize)
    guard loadingCacheKey != cacheKey else { return }
    loadingCacheKey = cacheKey
    Task.detached(priority: .high) { [weak self] in
      let readyImage = await Self.decodeImage(imagePath: imagePath, maxPixelSize: pixelSize)
      guard !Task.isCancelled else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        if loadingCacheKey == cacheKey { loadingCacheKey = nil }
        guard let readyImage else { return }
        Self.cache.setObject(
          readyImage,
          forKey: cacheKey as NSString,
          cost: Self.byteCount(of: readyImage)
        )
        refresh()
      }
    }
  }

  /// Decodes the artwork, scaled down to `maxPixelSize` if it is larger
  @concurrent
  private static func decodeImage(imagePath: String, maxPixelSize: Int) async -> UIImage? {
    let url = URL(fileURLWithPath: imagePath) as CFURL
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    if let source = CGImageSourceCreateWithURL(
      url,
      [kCGImageSourceShouldCache: false] as CFDictionary
    ),
      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
      return UIImage(cgImage: cgImage)
    }
    // formats ImageIO can not scale
    return await UIImage(contentsOfFile: imagePath)?.byPreparingForDisplay()
  }

  private static func byteCount(of image: UIImage) -> Int {
    guard let cgImage = image.cgImage else {
      return Int(image.size.width * image.scale * image.size.height * image.scale) * 4
    }
    return cgImage.bytesPerRow * cgImage.height
  }

  @objc
  private func downloadFinishedSuccessful(notification: Notification) {
    guard let downloadNotification = DownloadNotification.fromNotification(notification)
    else { return }
    if entity == nil, let artwork = standaloneArtwork,
       artwork.uniqueID == downloadNotification.id {
      Task { @MainActor in
        guard let imagePath = artwork.imagePath else { return }
        self.loadImage(imagePath: imagePath)
      }
      return
    }
    guard let entity else { return }
    if let playable = entity as? AbstractPlayable,
       playable.uniqueID == downloadNotification.id, let accountInfo = playable.account?.info {
      Task { @MainActor in
        guard let imagePath = entity.imagePath(
          setting: appDelegate.storage.settings.accounts.getSetting(accountInfo).read
            .artworkDisplayPreference
        ) else { return }
        self.loadImage(imagePath: imagePath)
      }
    }
    if let artwork = entity.artwork,
       artwork.uniqueID == downloadNotification.id, let accountInfo = artwork.account?.info {
      Task { @MainActor in
        guard let imagePath = entity.imagePath(
          setting: appDelegate.storage.settings.accounts.getSetting(accountInfo).read
            .artworkDisplayPreference
        ) else { return }
        self.loadImage(imagePath: imagePath)
      }
    }
  }
}
