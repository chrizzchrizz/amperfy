//
//  ToastView.swift
//  Amperfy
//
//  Created by Chrizz Gelbach on 26.10.26.
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
//

import AmperfyKit
import CoreImage
import UIKit

// MARK: - ToastView

/// Compact capsule that springs open below the status bar, reveals its text out of a blur
/// and disappears on its own.
@MainActor
final class ToastView: UIView {
  static let maxWidth: CGFloat = 200
  static let height: CGFloat = 50
  /// Vertical center of the standard navigation bar content below the top safe area.
  static let navigationBarCenterOffset: CGFloat = 22
  static let displayDuration: Duration = .seconds(3)
  private static let openDuration: TimeInterval = 0.3
  private static let textRevealDelay: TimeInterval = 0.00
  private static let textRevealDuration: TimeInterval = 0.20
  private static let textBlurPadding: CGFloat = 12
  /// Blur radii in points, from the blurriest to the sharp text.
  private static let textBlurRadii: [CGFloat] = [10, 6, 3, 1.5, 0]

  private static weak var current: ToastView?
  static var isVisible: Bool { current != nil }

  private let textStack = UIStackView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private var onTap: (() -> Void)?
  private var dismissTask: Task<Void, Never>?
  private var isDismissing = false

  static func show(
    title: String,
    subtitle: String,
    style: LogEntryType,
    in window: UIWindow,
    onTap: (() -> Void)? = nil
  ) {
    guard current == nil else { return }
    let toast = ToastView(title: title, subtitle: subtitle, color: style.toastColor)
    toast.onTap = onTap
    current = toast
    toast.present(in: window)
  }

  private init(title: String, subtitle: String, color: UIColor) {
    super.init(frame: .zero)
    backgroundColor = color
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.2
    layer.shadowRadius = 6
    layer.shadowOffset = CGSize(width: 0, height: 2)

    titleLabel.text = title
    titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    subtitleLabel.text = subtitle
    subtitleLabel.font = .systemFont(ofSize: 12)
    for label in [titleLabel, subtitleLabel] {
      label.textColor = .white
      label.textAlignment = .center
      label.numberOfLines = 1
      label.lineBreakMode = .byTruncatingTail
    }

    for label in [titleLabel, subtitleLabel] {
      textStack.addArrangedSubview(label)
    }
    textStack.axis = .vertical
    textStack.alignment = .fill
    textStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(textStack)
    NSLayoutConstraint.activate([
      textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    isAccessibilityElement = true
    accessibilityLabel = "\(title), \(subtitle)"
    accessibilityTraits = .staticText
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.height / 2
  }

  private func present(in window: UIWindow) {
    translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(self)
    let widthFill = widthAnchor.constraint(equalToConstant: Self.maxWidth)
    widthFill.priority = .defaultHigh
    NSLayoutConstraint.activate([
      centerXAnchor.constraint(equalTo: window.centerXAnchor),
      centerYAnchor.constraint(
        equalTo: window.safeAreaLayoutGuide.topAnchor,
        constant: Self.navigationBarCenterOffset
      ),
      heightAnchor.constraint(equalToConstant: Self.height),
      widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth),
      widthFill,
    ])
    window.layoutIfNeeded()

    alpha = 0
    transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
    let textReveal = prepareTextReveal()
    UIView.animate(
      withDuration: Self.openDuration,
      delay: 0,
      usingSpringWithDamping: 0.6,
      initialSpringVelocity: 0.9,
      options: [.allowUserInteraction]
    ) {
      self.alpha = 1
      self.transform = .identity
    }
    textReveal?()

    dismissTask = Task { [weak self] in
      try? await Task.sleep(for: Self.displayDuration)
      guard !Task.isCancelled else { return }
      self?.dismiss()
    }
  }

  /// Hides the text and returns a closure that reveals it from blurred to sharp.
  private func prepareTextReveal() -> (() -> Void)? {
    let padding = Self.textBlurPadding
    let size = CGSize(
      width: textStack.bounds.width + 2 * padding,
      height: textStack.bounds.height + 2 * padding
    )
    // the stack is rendered on its own, so the transparent toast does not affect the image
    let image = UIGraphicsImageRenderer(size: size).image { context in
      context.cgContext.translateBy(x: padding, y: padding)
      textStack.layer.render(in: context.cgContext)
    }
    guard let sharp = image.cgImage else { return nil }
    let source = CIImage(cgImage: sharp)
    let ciContext = CIContext()
    let frames = Self.textBlurRadii.compactMap { radius -> CGImage? in
      guard radius > 0 else { return sharp }
      return ciContext.createCGImage(
        source.clampedToExtent()
          .applyingGaussianBlur(sigma: Double(radius * image.scale))
          .cropped(to: source.extent),
        from: source.extent
      )
    }
    guard let first = frames.first else { return nil }

    let blurredText = UIView(frame: textStack.frame.insetBy(dx: -padding, dy: -padding))
    blurredText.isUserInteractionEnabled = false
    blurredText.layer.contentsScale = image.scale
    blurredText.layer.contents = first
    blurredText.alpha = 0
    addSubview(blurredText)
    textStack.alpha = 0

    return { [weak self, weak blurredText] in
      guard let blurredText else { return }
      let animation = CAKeyframeAnimation(keyPath: "contents")
      animation.values = frames
      animation.calculationMode = .discrete
      animation.duration = Self.textRevealDuration
      animation.beginTime = CACurrentMediaTime() + Self.textRevealDelay
      animation.fillMode = .backwards
      CATransaction.begin()
      CATransaction.setCompletionBlock {
        self?.textStack.alpha = 1
        blurredText.removeFromSuperview()
      }
      blurredText.layer.contents = frames.last
      blurredText.layer.add(animation, forKey: "unblur")
      CATransaction.commit()
      UIView.animate(
        withDuration: Self.textRevealDuration,
        delay: Self.textRevealDelay,
        options: [.curveEaseOut]
      ) {
        blurredText.alpha = 1
      }
    }
  }

  private func dismiss(completion: (() -> Void)? = nil) {
    guard !isDismissing else { return }
    isDismissing = true
    dismissTask?.cancel()
    UIView.animate(
      withDuration: 0.05,
      delay: 0,
      options: [.curveEaseIn],
      animations: {
        self.alpha = 0
      },
      completion: { _ in
        self.removeFromSuperview()
        if Self.current === self {
          Self.current = nil
        }
        completion?()
      }
    )
  }

  @objc
  private func handleTap() {
    // runs even while the automatic fade out is already in progress
    let action = onTap
    onTap = nil
    dismiss()
    action?()
  }
}

extension LogEntryType {
  fileprivate var toastColor: UIColor {
    switch self {
    case .apiError, .error: return UIColor(red: 0.75, green: 0.22, blue: 0.17, alpha: 0.92)
    case .info, .debug: return UIColor(red: 0.18, green: 0.44, blue: 0.71, alpha: 0.92)
    }
  }
}
