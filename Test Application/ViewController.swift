// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  ViewController.swift
//  TestApplication
//

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet weak var previewView: PreviewView!
    @IBOutlet weak var bottomSheetView: UIView!
    
    private var result: Result?
    private var previousInferenceTimeMs: TimeInterval = Date.distantPast.timeIntervalSince1970 * 1000
    private let delayBetweenInferencesMs: Double = 1000
    
    // Handles all the camera related functionality
    private lazy var cameraCapture = CameraManager(previewView: previewView)
    
    // Handles the presenting of results on the screen
    private var inferenceViewController: InferenceViewController?
    
    // Handles all model data preprocessing and makes calls to run inference
    private var modelHandler: ModelHandler? = ModelHandler()
    
    // MARK: View Controller Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
    
        guard modelHandler != nil else {
          fatalError("Model set up failed")
        }
        
        cameraCapture.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)

  #if !targetEnvironment(simulator)
      cameraCapture.checkCameraConfigurationAndStartSession()
  #endif
    }
    
  #if !targetEnvironment(simulator)
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraCapture.stopSession()
    }
  #endif
    
    // MARK: Storyboard Segue Handlers
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
      super.prepare(for: segue, sender: sender)

      if segue.identifier == "EMBED" {

        guard let tempModelHandler = modelHandler else {
          return
        }
        inferenceViewController = segue.destination as? InferenceViewController
        inferenceViewController?.wantedInputHeight = tempModelHandler.inputHeight
        inferenceViewController?.wantedInputWidth = tempModelHandler.inputWidth
        inferenceViewController?.maxResults = tempModelHandler.resultCount
        inferenceViewController?.threadCountLimit = tempModelHandler.threadCountLimit
        inferenceViewController?.delegate = self

      }
    }
    
}
    
// MARK: InferenceViewControllerDelegate Methods
extension ViewController: InferenceViewControllerDelegate {

      func didChangeThreadCount(to count: Int32) {
        if modelHandler?.threadCount == count { return }
        modelHandler = ModelHandler(threadCount: count)
      }
}

// MARK: CameraFeedManagerDelegate Methods
extension ViewController: CameraManagerDelegate {
    
    // MARK: Session Handling Alerts
    func presentCameraPermissionsDeniedAlert() {
      let alertController = UIAlertController(title: "Camera Permissions Denied", message: "Camera permissions have been denied for this app. You can change this by going to Settings", preferredStyle: .alert)

      let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
      let settingsAction = UIAlertAction(title: "Settings", style: .default) { (action) in
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
      }
      alertController.addAction(cancelAction)
      alertController.addAction(settingsAction)

      present(alertController, animated: true, completion: nil)

      previewView.shouldUseClipboardImage = true
    }

    func presentVideoConfigurationErrorAlert() {
      let alert = UIAlertController(title: "Camera Configuration Failed", message: "There was an error while configuring camera.", preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

      self.present(alert, animated: true)
        
      previewView.shouldUseClipboardImage = true
    }
    
    func didOutput(pixelBuffer: CVPixelBuffer) {
        let currentTimeMs = Date().timeIntervalSince1970 * 1000
        guard (currentTimeMs - previousInferenceTimeMs) >= delayBetweenInferencesMs
        else { return }
        previousInferenceTimeMs = currentTimeMs

        // Pass the pixel buffer to TensorFlow Lite to perform inference.
        result = try! modelHandler?.runModel(onFrame: pixelBuffer, modelFileInfo: (name: "mobilenet_v2_float", extension: "ort"))

        // Display results by handing off to the InferenceViewController.
        DispatchQueue.main.async {
          let resolution = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
          self.inferenceViewController?.inferenceResult = self.result
          self.inferenceViewController?.resolution = resolution
          self.inferenceViewController?.tableView.reloadData()
       }
    }
    
}
