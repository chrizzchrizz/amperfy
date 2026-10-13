//
//  UtilitiesExtensions.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 06.06.22.
//  Copyright (c) 2022 Maximilian Bauer. All rights reserved.
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
import DominantColors
import Foundation
import MarqueeLabel
import os.log
import SwiftUI
import UIKit

extension MarqueeLabel {
  func applyAmperfyStyle() {
    if trailingBuffer != 30.0 {
      trailingBuffer = 30.0
    }
    if leadingBuffer != 0.0 {
      leadingBuffer = 0.0
    }
    if animationDelay != 2.0 {
      animationDelay = 2.0
    }
    if type != .continuous {
      type = .continuous
    }
    speed = .rate(30.0)
    if fadeLength != 10.0 {
      fadeLength = 10.0
    }
  }
}

extension UIColor {
  static let hardLabelColor = UIColor(named: "hardLabelColor")
}

extension Color {
  static let error = Color.red
  static let success = Color.green

  // MARK: - Text Colors

  static let lightText = Color(UIColor.lightText)
  static let darkText = Color(UIColor.darkText)
  static let placeholderText = Color(UIColor.placeholderText)

  // MARK: - Label Colors

  static let label = Color(UIColor.label)
  static let secondaryLabel = Color(UIColor.secondaryLabel)
  static let tertiaryLabel = Color(UIColor.tertiaryLabel)
  static let quaternaryLabel = Color(UIColor.quaternaryLabel)

  // MARK: - Background Colors

  static let systemBackground = Color(UIColor.systemBackground)
  static let secondarySystemBackground = Color(UIColor.secondarySystemBackground)
  static let tertiarySystemBackground = Color(UIColor.tertiarySystemBackground)

  // MARK: - Fill Colors

  static let systemFill = Color(UIColor.systemFill)
  static let secondarySystemFill = Color(UIColor.secondarySystemFill)
  static let tertiarySystemFill = Color(UIColor.tertiarySystemFill)
  static let quaternarySystemFill = Color(UIColor.quaternarySystemFill)

  // MARK: - Grouped Background Colors

  static let systemGroupedBackground = Color(UIColor.systemGroupedBackground)
  static let secondarySystemGroupedBackground = Color(UIColor.secondarySystemGroupedBackground)
  static let tertiarySystemGroupedBackground = Color(UIColor.tertiarySystemGroupedBackground)

  // MARK: - Gray Colors

  static let systemGray = Color(UIColor.systemGray)
  static let systemGray2 = Color(UIColor.systemGray2)
  static let systemGray3 = Color(UIColor.systemGray3)
  static let systemGray4 = Color(UIColor.systemGray4)
  static let systemGray5 = Color(UIColor.systemGray5)
  static let systemGray6 = Color(UIColor.systemGray6)

  // MARK: - Other Colors

  static let separator = Color(UIColor.separator)
  static let opaqueSeparator = Color(UIColor.opaqueSeparator)
  static let link = Color(UIColor.link)

  // MARK: System Colors

  static let systemBlue = Color(UIColor.systemBlue)
  static let systemPurple = Color(UIColor.systemPurple)
  static let systemGreen = Color(UIColor.systemGreen)
  static let systemYellow = Color(UIColor.systemYellow)
  static let systemOrange = Color(UIColor.systemOrange)
  static let systemPink = Color(UIColor.systemPink)
  static let systemRed = Color(UIColor.systemRed)
  static let systemTeal = Color(UIColor.systemTeal)
  static let systemIndigo = Color(UIColor.systemIndigo)
}

public func withPopupAnimation<Result>(_ body: () throws -> Result) rethrows -> Result {
  try withAnimation(.easeInOut(duration: 0.2)) {
    try body()
  }
}

extension View {
  var appDelegate: AppDelegate {
    (UIApplication.shared.delegate as! AppDelegate)
  }
}

extension UIColor {
  static let slideOverBackgroundColor: UIColor = .systemBackground.withAlphaComponent(0.5)
  static let hoveredBackgroundColor: UIColor = .systemGray2.withAlphaComponent(0.2)
}

extension UIButton.Configuration {
  static func player(isSelected: Bool) -> UIButton.Configuration {
    var config = UIButton.Configuration.tinted()
    if isSelected {
      config.background.strokeColor = .label
      config.background.strokeWidth = 1.0
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .medium)
    }
    config.buttonSize = .small
    #if targetEnvironment(macCatalyst)
      config.baseForegroundColor = .label
      config.baseBackgroundColor = .clear
    #else
      config.baseForegroundColor = !isSelected ? .label : .systemBackground
      config.baseBackgroundColor = !isSelected ? .clear : .label
    #endif
    config.cornerStyle = .medium
    return config
  }

  static func playerRound() -> UIButton.Configuration {
    var config = UIButton.Configuration.gray()
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .medium)
    config.buttonSize = .small
    return config
  }
}

extension UIView {
  static let forceTouchClickLimit: Float = 1.0

  func normalizedForce(touches: Set<UITouch>) -> Float? {
    guard is3DTouchAvailable, let touch = touches.first else { return nil }
    let maximumForce = touch.maximumPossibleForce
    let force = touch.force
    let normalizedForce = (force / maximumForce)
    return Float(normalizedForce)
  }

  func isForceClicked(_ touches: Set<UITouch>) -> Bool {
    guard let force = normalizedForce(touches: touches) else { return false }
    if force < UIView.forceTouchClickLimit {
      return false
    } else {
      return true
    }
  }

  var is3DTouchAvailable: Bool {
    forceTouchCapability() == .available
  }

  func forceTouchCapability() -> UIForceTouchCapability {
    UIApplication.shared.mainWindow?.rootViewController?.traitCollection
      .forceTouchCapability ?? .unknown
  }

  public func setBackgroundBlur(style: UIBlurEffect.Style, alpha: CGFloat = 1.0) {
    backgroundColor = UIColor.clear
    let blurEffect = UIBlurEffect(style: style)
    let blurEffectView = UIVisualEffectView(effect: blurEffect)
    blurEffectView.alpha = alpha
    blurEffectView.frame = bounds
    blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    insertSubview(blurEffectView, at: 0)
  }

  func addLeftSideBorder() {
    let separator = UIView()
    separator.backgroundColor = .separator
    addSubview(separator)
    separator.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      separator.widthAnchor.constraint(equalToConstant: 1),
      separator.leadingAnchor.constraint(equalTo: leadingAnchor),
      separator.topAnchor.constraint(equalTo: topAnchor),
      separator.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  func addTopSideBorder() {
    let separator = UIView()
    separator.backgroundColor = .separator
    addSubview(separator)
    separator.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      separator.heightAnchor.constraint(equalToConstant: 1),
      separator.leadingAnchor.constraint(equalTo: leadingAnchor),
      separator.topAnchor.constraint(equalTo: topAnchor),
      separator.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }
}

extension UINavigationController {
  func replaceCurrentlyActiveVC(with vc: UIViewController, animated: Bool) {
    var vcs = viewControllers
    vcs = vcs.dropLast()
    vcs.append(vc)
    setViewControllers(vcs, animated: animated)
  }
}

extension UITableView {
  func register(nibName: String) {
    register(UINib(nibName: nibName, bundle: nil), forCellReuseIdentifier: nibName)
  }

  func dequeueCell<CellType: UITableViewCell>(
    for tableView: UITableView,
    at indexPath: IndexPath
  )
    -> CellType {
    guard let cell = dequeueReusableCell(
      withIdentifier: CellType.typeName,
      for: indexPath
    ) as? CellType else {
      os_log(.error, "The dequeued cell is not an instance of %s", CellType.typeName)
      return CellType()
    }
    return cell
  }

  func hasRowAt(indexPath: IndexPath) -> Bool {
    indexPath.section < numberOfSections && indexPath
      .row < numberOfRows(inSection: indexPath.section)
  }
}

extension UICollectionView {
  func hasItemAt(indexPath: IndexPath) -> Bool {
    indexPath.section < numberOfSections && indexPath
      .row < numberOfItems(inSection: indexPath.section)
  }
}

@MainActor
extension UITableViewController {
  func dequeueCell<CellType: UITableViewCell>(
    for tableView: UITableView,
    at indexPath: IndexPath
  )
    -> CellType {
    self.tableView.dequeueCell(for: tableView, at: indexPath)
  }

  func refreshAllVisibleCells() {
    let visibleIndexPaths = tableView.visibleCells.compactMap { tableView.indexPath(for: $0) }
    tableView.reconfigureRows(at: visibleIndexPaths)
  }

  func exectueAfterAnimation(body: @escaping () -> ()) {
    Task { @MainActor in
      body()
    }
  }
}

extension UIViewController {
  var typeName: String {
    Self.typeName
  }
}

extension NSObject {
  @MainActor
  var appDelegate: AppDelegate {
    (UIApplication.shared.delegate as! AppDelegate)
  }
}

extension UIApplication {
  var mainWindow: UIWindow? {
    let scenes = UIApplication.shared.connectedScenes
    for uiScene in scenes {
      if let windowScene = uiScene as? UIWindowScene {
        for window in windowScene.windows {
          if window.isKeyWindow {
            return window
          }
        }
      }
    }
    return nil
  }
}

extension UITraitCollection {
  static let maxDisplayScale = UITraitCollection(displayScale: 3.0)
}

extension UITableViewCell {
  func animateActivation() {
    UIView.animate(withDuration: 0.2, animations: {
      self.markAsFocused()
    }, completion: { _ in
      self.markAsFocused()
      UIView.animate(withDuration: 0.2, animations: {
        self.markAsUnfocused()
      }, completion: { _ in
        self.markAsUnfocused()
      })
    })
  }

  func markAsFocused() {
    backgroundColor = .systemGray4
  }

  func markAsUnfocused() {
    backgroundColor = .clear
  }
}

extension UICollectionViewCell {
  func animateActivation() {
    UIView.animate(withDuration: 0.2, animations: {
      self.markAsFocused()
    }, completion: { _ in
      self.markAsFocused()
      UIView.animate(withDuration: 0.2, animations: {
        self.markAsUnfocused()
      }, completion: { _ in
        self.markAsUnfocused()
      })
    })
  }

  func markAsFocused() {
    let focuseBackground = UIView(frame: bounds)
    focuseBackground.backgroundColor = .systemGray4
    backgroundView = focuseBackground
  }

  func markAsUnfocused() {
    backgroundView = nil
  }
}

extension UIMenu {
  /// rebuilds menu on every access
  static func lazyMenu(
    title: String = "",
    builder: @escaping () -> [UIMenuElement]
  )
    -> UIMenu {
    UIMenu(title: title, children: [
      UIDeferredMenuElement.uncached { completion in
        let actions = builder()
        completion(actions)
      },
    ])
  }
}

extension UIImage {
  func carPlayImage(carTraitCollection traits: UITraitCollection) -> UIImage {
    let imageAsset = UIImageAsset()
    imageAsset.register(self, with: traits)
    return imageAsset.image(with: traits)
  }
}

extension UICollectionViewLayout {
  static var verticalLayout: UICollectionViewFlowLayout {
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .vertical
    return layout
  }
}

extension UIDevice.BatteryState {
  public var description: String {
    switch self {
    case .unknown:
      return "unknown"
    case .unplugged:
      return "unplugged"
    case .charging:
      return "charging"
    case .full:
      return "full"
    @unknown default:
      return "@unknown default"
    }
  }
}

/// This fixes in swiftui mutliple picker views side by side to overlapp their touch areas
/// This is effective in addition to use .clipped() which only fixes the overlapping area visually
extension UIPickerView {
  open override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: 150)
  }
}

extension Notification.Name {
  static let LibraryItemsChanged = Notification.Name("de.familie-zimba.Amperfy.LibraryItemsChanged")
}

extension UIViewController {
  @objc
  var sceneTitle: String? { nil }

  func extendSafeAreaToAccountForMiniPlayer() {
    guard let hostVC = AppDelegate.mainWindowHostVC else { return }
    additionalSafeAreaInsets = UIEdgeInsets(
      top: 0,
      left: 0,
      bottom: hostVC.getSafeAreaExtension(),
      right: 0
    )
  }
}

extension UIImage {
  /// Most frequent color of the image; falls back to the average color.
  ///
  /// Uses a cheap histogram on a tiny thumbnail. The DominantColors package merges similar colors
  /// pairwise, which can take very long for noisy artwork and blocked the main thread.
  ///
  /// With `forDarkBackground` only darker colors of the image are considered, so the result stays
  /// a real artwork color instead of a bright color that is merely dimmed afterwards.
  func mainColor(forDarkBackground: Bool = false) -> UIColor {
    let side = 32
    guard let cgImage else { return averageColor() }
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(
        data: buffer.baseAddress,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return false }
      context.interpolationQuality = .medium
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
      return true
    }
    guard drewImage else { return averageColor() }

    // 4 bits per channel buckets
    var buckets = [Int: (count: Int, r: Int, g: Int, b: Int)]()
    for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 {
      let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
      let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
      let bucket = buckets[key] ?? (0, 0, 0, 0)
      buckets[key] = (bucket.count + 1, bucket.r + r, bucket.g + g, bucket.b + b)
    }
    typealias Bucket = (count: Int, r: Int, g: Int, b: Int)
    func average(_ bucket: Bucket) -> UIColor {
      UIColor(
        red: CGFloat(bucket.r) / CGFloat(bucket.count) / 255,
        green: CGFloat(bucket.g) / CGFloat(bucket.count) / 255,
        blue: CGFloat(bucket.b) / CGFloat(bucket.count) / 255,
        alpha: 1
      )
    }
    func hsb(_ bucket: Bucket) -> (s: CGFloat, b: CGFloat) {
      var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
      average(bucket).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
      return (saturation, brightness)
    }
    // prefer saturated, not too dark colors over large neutral or dark areas
    func score(_ bucket: Bucket) -> CGFloat {
      let value = hsb(bucket)
      return CGFloat(bucket.count) * (0.2 + value.s) * (0.3 + value.b)
    }

    if forDarkBackground {
      // dark but not black; saturation decides so neutral dark areas don't win over colors
      let darkCandidates = buckets.values.filter { 0.12 ... 0.5 ~= hsb($0).b }
      let source = darkCandidates.max(by: {
        CGFloat($0.count) * (0.2 + hsb($0).s) < CGFloat($1.count) * (0.2 + hsb($1).s)
      }) ?? buckets.values.max(by: { score($0) < score($1) })
      guard let source else { return averageColor().clampedForDarkBackground() }
      return average(source).clampedForDarkBackground()
    }

    guard let best = buckets.values.max(by: { score($0) < score($1) }) else {
      return averageColor()
    }
    return average(best)
  }
}

extension UIColor {
  /// Keeps hue, limits brightness and saturation to a range that looks good behind white content.
  func clampedForDarkBackground() -> UIColor {
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    else { return self }
    return UIColor(
      hue: hue,
      saturation: min(saturation, 0.7),
      brightness: min(max(brightness, 0.2), 0.4),
      alpha: alpha
    )
  }

  /// WCAG relative luminance (0 = black, 1 = white).
  var relativeLuminance: CGFloat {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
    func linear(_ value: CGFloat) -> CGFloat {
      value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// Whether black content is more readable than white on top of this color.
  var prefersDarkContent: Bool {
    // 0.179 would be the exact contrast tipping point,
    // the slightly higher threshold keeps mid tones on white text.
    relativeLuminance > 0.3
  }
}
