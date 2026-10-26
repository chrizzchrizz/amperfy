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
import UIKit

// MARK: - ToastView

/// Compact capsule that scales in below the status bar and disappears on its own.
@MainActor
final class ToastView: UIView {
  static let maxWidth: CGFloat = 200
  static let height: CGFloat = 50
  /// Vertical center of the standard navigation bar content below the top safe area.
  static let navigationBarCenterOffset: CGFloat = 22
  static let displayDuration: Duration = .seconds(3)

  private static weak var current: ToastView?
  static var isVisible: Bool { current != nil }

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

    let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    stack.axis = .vertical
    stack.alignment = .fill
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
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
    transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
    UIView.animate(
      withDuration: 0.2,
      delay: 0,
      usingSpringWithDamping: 0.75,
      initialSpringVelocity: 0.5,
      options: [.allowUserInteraction]
    ) {
      self.alpha = 1
      self.transform = .identity
    }

    dismissTask = Task { [weak self] in
      try? await Task.sleep(for: Self.displayDuration)
      guard !Task.isCancelled else { return }
      self?.dismiss()
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
