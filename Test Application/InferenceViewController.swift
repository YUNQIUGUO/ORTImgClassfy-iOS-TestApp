// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  InferenceViewController.swift
//  TestApplication
//

import UIKit

// MARK: InferenceViewControllerDelegate Method Declarations
protocol InferenceViewControllerDelegate {
  /**
   This method is called when the user changes the stepper value to update number of threads used for inference.
   */
  func didChangeThreadCount(to count: Int32)

}

class InferenceViewController: UIViewController {
    
    // MARK: Storyboard Outlets
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var threadStepper: UIStepper!
    @IBOutlet weak var stepperValueLabel: UILabel!
    
    // MARK: Inference related display results and info
    private enum InferenceResults: Int, CaseIterable {
      case Results
      case InferenceInfo
    }
    
    private enum InferenceInfo: Int, CaseIterable {
      case Resolution
      case Crop
      case InferenceTime

      func displayString() -> String {

        var toReturn = ""

        switch self {
        case .Resolution:
          toReturn = "Resolution"
        case .Crop:
          toReturn = "Crop"
        case .InferenceTime:
          toReturn = "Inference Time"

        }
        return toReturn
      }
    }
    
    //MARK: Labels file
    private var labelData = loadLabels(fileInfo: (name: "labels", extension: "txt"))
    
    var inferenceResult: Result? = nil
    var wantedInputWidth: Int = 0
    var wantedInputHeight: Int = 0
    var resolution: CGSize = CGSize.zero
    var maxResults: Int = 0
    var threadCountLimit: Int = 0
    private let minThreadCount = 1
    private var currentThreadCount: Int32 = 0
    
    var delegate: InferenceViewControllerDelegate?

    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up stepper
        threadStepper.isUserInteractionEnabled = true
        threadStepper.maximumValue = Double(threadCountLimit)
        threadStepper.minimumValue = Double(minThreadCount)
        threadStepper.value = Double(currentThreadCount)
        
    }
    
    // MARK: Buttion Actions
    /**
     Delegate the change of number of threads to View Controller and change the stepper display.
     */
    @IBAction func onClickThreadStepper(_ sender: Any) {

      delegate?.didChangeThreadCount(to: Int32(threadStepper.value))
      currentThreadCount = Int32(threadStepper.value)
      stepperValueLabel.text = "\(currentThreadCount)"
    }
}

    /// Loads the labels from the labels file and stores them in the `labelData`.
    private func loadLabels(fileInfo: FileInfo) -> [String] {
      var labelData: [String] = []
      let filename = fileInfo.name
      let fileExtension = fileInfo.extension
      guard let fileURL = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
        fatalError("Labels file not found in bundle. Please add a labels file with name " +
                     "\(filename).\(fileExtension)")
      }
      do {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        labelData = contents.components(separatedBy: .newlines)
      } catch {
        fatalError("Labels file named \(filename).\(fileExtension) cannot be read.")
      }
      return labelData
    }


// MARK: UITableView Data Source
extension InferenceViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {

      return InferenceResults.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

      guard let inferenceResults = InferenceResults(rawValue: section) else {
        return 0
      }

      var rowCount = 0
      switch inferenceResults {
      case .Results:
        rowCount = maxResults
      case .InferenceInfo:
        rowCount = InferenceInfo.allCases.count
      }
      return rowCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "INFO_CELL") as! InfoCell

        guard let inferenceResults = InferenceResults(rawValue: indexPath.section) else {
          return cell
        }

        var fieldName = ""
        var info = ""
        var font = UIFont.systemFont(ofSize: 14.0, weight: .regular)
        var color = UIColor.black

        switch inferenceResults {
        case .Results:

          let tuple = displayStringsForResults(atRow: indexPath.row)
          fieldName = tuple.0
          info = tuple.1

          if indexPath.row == 0 {
            font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
            color = UIColor.black
          }
          else {
            font = UIFont.systemFont(ofSize: 14.0, weight: .regular)
            color = UIColor(displayP3Red: 117.0/255.0, green: 117.0/255.0, blue: 117.0/255.0, alpha: 1.0)
          }

        case .InferenceInfo:
          let tuple = displayStringsForInferenceInfo(atRow: indexPath.row)
          fieldName = tuple.0
          info = tuple.1

        }
        cell.fieldNameLabel.font = font
        cell.fieldNameLabel.textColor = color
        cell.fieldNameLabel.text = fieldName
        cell.infoLabel.text = info
        
        return cell
    }
    
    /**
     This method formats the display of the inferences for the current frame.
     */
    func displayStringsForResults(atRow row: Int) -> (String, String) {

        var fieldName: String = ""
        var info: String = ""

        guard let tempResult = inferenceResult, tempResult.detectedIndices.count > 0 else {

          if row == 1 {
            fieldName = "No Results"
            info = ""
          }
          else {
            fieldName = ""
            info = ""
          }
          return (fieldName, info)
        }

        if row < tempResult.detectedIndices.count {
          fieldName = labelData[tempResult.detectedIndices[row]]
          info =  String(format: "%.2f", tempResult.detectedScore[row] * 100.0) + "%"
        }
        else {
          fieldName = ""
          info = ""
        }

        return (fieldName, info)
    }
    
    
    /**
     This method formats the display of additional information relating to the inferences.
     */
    func displayStringsForInferenceInfo(atRow row: Int) -> (String, String) {

      var fieldName: String = ""
      var info: String = ""

      guard let inferenceInfo = InferenceInfo(rawValue: row) else {
        return (fieldName, info)
      }

      fieldName = inferenceInfo.displayString()

      switch inferenceInfo {
      case .Resolution:
        info = "\(Int(resolution.width))x\(Int(resolution.height))"
      case .Crop:
        info = "\(wantedInputWidth)x\(wantedInputHeight)"
      case .InferenceTime:
        guard let finalResults = inferenceResult else {
          info = "0ms"
          break
        }
        info = String(format: "%.2fms", finalResults.processTimeMs)
      }

      return(fieldName, info)
    }
}
