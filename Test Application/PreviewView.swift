// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  PreviewView.swift
//  TestApplication
//


import UIKit
import AVFoundation

class PreviewView: UIView {
    
    var shouldUseClipboardImage: Bool = false {
      didSet {
        if shouldUseClipboardImage {
          if imageView.superview == nil {
            addSubview(imageView)
          }
        } else {
          imageView.removeFromSuperview()
        }
      }
    }
    
    lazy private var imageView: UIImageView = {
      let imageView = UIImageView()
      imageView.contentMode = .scaleAspectFill
      imageView.translatesAutoresizingMaskIntoConstraints = false
      return imageView
    }()

    var image: UIImage? {
      get {
        return imageView.image
      }
      set {
        imageView.image = newValue
      }
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
      guard let layer = layer as? AVCaptureVideoPreviewLayer else {
        fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. ")
      }
      return layer
    }

    var session: AVCaptureSession? {
      get {
        return previewLayer.session
      }
      set {
        previewLayer.session = newValue
      }
    }

    override class var layerClass: AnyClass {
      return AVCaptureVideoPreviewLayer.self
    }
}
