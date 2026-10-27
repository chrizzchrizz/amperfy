//
//  ImageCropViewController.swift
//  Amperfy
//
//  Created by Chrizz Gelbach on 27.10.26.
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

// MARK: - ImageCropViewController

/// Lets the user choose a square section of an image by moving and pinching.
class ImageCropViewController: UIViewController {
  static let outputSideLength: CGFloat = 1024
  private static let cropMargin: CGFloat = 16

  /// Called with the cropped image, the owner dismisses the controller.
  var onCropped: ((UIImage) -> ())?
  var onCancel: (() -> ())?

  private let image: UIImage
  private let scrollView = UIScrollView()
  private let imageView: UIImageView
  private let dimView = UIView()
  private let dimLayer = CAShapeLayer()
  private let cropBorderView = UIView()
  private let zoomSlider = UISlider()
  private var cropRect = CGRect.zero
  private var isInitialLayoutDone = false

  init(image: UIImage) {
    self.image = Self.normalized(image)
    self.imageView = UIImageView(image: self.image)
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Cover"
    view.backgroundColor = .black
    overrideUserInterfaceStyle = .dark

    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "Cancel",
      style: .plain,
      target: self,
      action: #selector(cancelPressed)
    )
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: .check,
      style: .done,
      target: self,
      action: #selector(donePressed)
    )

    scrollView.delegate = self
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.showsVerticalScrollIndicator = false
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.bouncesZoom = true
    scrollView.alwaysBounceVertical = true
    scrollView.alwaysBounceHorizontal = true
    scrollView.addSubview(imageView)
    scrollView.contentSize = image.size
    view.addSubview(scrollView)

    dimView.isUserInteractionEnabled = false
    dimLayer.fillRule = .evenOdd
    dimLayer.fillColor = UIColor.black.withAlphaComponent(0.6).cgColor
    dimView.layer.addSublayer(dimLayer)
    view.addSubview(dimView)

    cropBorderView.isUserInteractionEnabled = false
    cropBorderView.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
    cropBorderView.layer.borderWidth = 1
    view.addSubview(cropBorderView)

    #if targetEnvironment(macCatalyst)
      zoomSlider.addTarget(self, action: #selector(zoomSliderChanged), for: .valueChanged)
      view.addSubview(zoomSlider)
    #endif
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    scrollView.frame = view.bounds
    dimView.frame = view.bounds

    let safeArea = view.safeAreaLayoutGuide.layoutFrame
    let side = max(
      1,
      min(safeArea.width, safeArea.height) - 2 * Self.cropMargin
    )
    let newCropRect = CGRect(
      x: (view.bounds.width - side) / 2,
      y: safeArea.minY + (safeArea.height - side) / 2,
      width: side,
      height: side
    )
    guard newCropRect != cropRect else { return }
    let oldCropRect = cropRect
    cropRect = newCropRect

    dimLayer.frame = dimView.bounds
    let path = UIBezierPath(rect: dimView.bounds)
    path.append(UIBezierPath(rect: cropRect))
    dimLayer.path = path.cgPath
    cropBorderView.frame = cropRect
    scrollView.contentInset = UIEdgeInsets(
      top: cropRect.minY,
      left: cropRect.minX,
      bottom: view.bounds.height - cropRect.maxY,
      right: view.bounds.width - cropRect.maxX
    )

    let minZoom = max(side / image.size.width, side / image.size.height)
    scrollView.minimumZoomScale = minZoom
    scrollView.maximumZoomScale = max(minZoom * 6, 1)
    zoomSlider.minimumValue = Float(scrollView.minimumZoomScale)
    zoomSlider.maximumValue = Float(scrollView.maximumZoomScale)
    zoomSlider.frame = CGRect(
      x: cropRect.minX,
      y: min(view.bounds.height - 44, cropRect.maxY + 12),
      width: cropRect.width,
      height: 32
    )

    if !isInitialLayoutDone {
      isInitialLayoutDone = true
      scrollView.zoomScale = minZoom
      centerCropArea()
    } else {
      // keep the center of the section on rotation
      let center = CGPoint(
        x: scrollView.contentOffset.x + oldCropRect.midX,
        y: scrollView.contentOffset.y + oldCropRect.midY
      )
      scrollView.zoomScale = max(scrollView.zoomScale, minZoom)
      scrollView.contentOffset = clampedOffset(CGPoint(
        x: center.x - cropRect.midX,
        y: center.y - cropRect.midY
      ))
    }
    zoomSlider.value = Float(scrollView.zoomScale)
  }

  private func centerCropArea() {
    let content = scrollView.contentSize
    scrollView.contentOffset = CGPoint(
      x: (content.width - cropRect.width) / 2 - cropRect.minX,
      y: (content.height - cropRect.height) / 2 - cropRect.minY
    )
  }

  private func clampedOffset(_ offset: CGPoint) -> CGPoint {
    let inset = scrollView.contentInset
    let content = scrollView.contentSize
    let minX = -inset.left
    let maxX = max(minX, content.width - scrollView.bounds.width + inset.right)
    let minY = -inset.top
    let maxY = max(minY, content.height - scrollView.bounds.height + inset.bottom)
    return CGPoint(
      x: min(max(offset.x, minX), maxX),
      y: min(max(offset.y, minY), maxY)
    )
  }

  @objc
  private func zoomSliderChanged() {
    scrollView.setZoomScale(CGFloat(zoomSlider.value), animated: false)
  }

  @objc
  private func cancelPressed() {
    onCancel?()
  }

  @objc
  private func donePressed() {
    onCropped?(croppedImage())
  }

  /// The visible section of the image scaled to the output size.
  private func croppedImage() -> UIImage {
    let zoom = scrollView.zoomScale
    let origin = CGPoint(
      x: (scrollView.contentOffset.x + cropRect.minX) / zoom,
      y: (scrollView.contentOffset.y + cropRect.minY) / zoom
    )
    let sectionSide = cropRect.width / zoom
    let outputSide = Self.outputSideLength
    let scale = outputSide / sectionSide
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(
      size: CGSize(width: outputSide, height: outputSide),
      format: format
    )
    .image { _ in
      UIColor.black.setFill()
      UIRectFill(CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
      image.draw(in: CGRect(
        x: -origin.x * scale,
        y: -origin.y * scale,
        width: image.size.width * scale,
        height: image.size.height * scale
      ))
    }
  }

  /// Orientation up and scale 1, so points equal pixels.
  private static func normalized(_ image: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    // photos can be huge, the output is only 1024 pixels
    let maxSide: CGFloat = 4096
    let longSide = max(image.size.width, image.size.height)
    let factor = longSide > maxSide ? maxSide / longSide : 1
    let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }
}

// MARK: UIScrollViewDelegate

extension ImageCropViewController: UIScrollViewDelegate {
  func viewForZooming(in scrollView: UIScrollView) -> UIView? {
    imageView
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    zoomSlider.value = Float(scrollView.zoomScale)
  }
}
