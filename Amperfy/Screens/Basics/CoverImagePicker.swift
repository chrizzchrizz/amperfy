//
//  CoverImagePicker.swift
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
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - CoverImagePicker

/// Picks an image from the photo library or the files, lets the user crop it and returns it.
@MainActor
class CoverImagePicker: NSObject {
  private weak var presenter: UIViewController?
  private var onImagePicked: ((UIImage) -> ())?

  init(presenter: UIViewController) {
    self.presenter = presenter
  }

  func pickFromPhotoLibrary(onImagePicked: @escaping (UIImage) -> ()) {
    self.onImagePicked = onImagePicked
    var config = PHPickerConfiguration(photoLibrary: .shared())
    config.filter = .images
    config.selectionLimit = 1
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    presenter?.present(picker, animated: true)
  }

  func pickFromFiles(onImagePicked: @escaping (UIImage) -> ()) {
    self.onImagePicked = onImagePicked
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    presenter?.present(picker, animated: true)
  }

  private func crop(_ image: UIImage) {
    let cropVC = ImageCropViewController(image: image)
    let nav = UINavigationController(rootViewController: cropVC)
    nav.modalPresentationStyle = .fullScreen
    cropVC.onCancel = { [weak nav] in nav?.dismiss(animated: true) }
    cropVC.onCropped = { [weak self, weak nav] croppedImage in
      nav?.dismiss(animated: true)
      self?.onImagePicked?(croppedImage)
    }
    presenter?.present(nav, animated: true)
  }
}

// MARK: PHPickerViewControllerDelegate

extension CoverImagePicker: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider,
          provider.canLoadObject(ofClass: UIImage.self) else { return }
    provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
      guard let image = object as? UIImage else { return }
      Task { @MainActor in
        self?.crop(image)
      }
    }
  }
}

// MARK: UIDocumentPickerDelegate

extension CoverImagePicker: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let url = urls.first, let data = try? Data(contentsOf: url),
          let image = UIImage(data: data) else { return }
    crop(image)
  }
}
