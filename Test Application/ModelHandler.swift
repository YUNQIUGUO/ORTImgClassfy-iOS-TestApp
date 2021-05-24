//
//  ModelHandler.swift
//  TestApplication
//
//  Created by rachguo on 5/20/21.
//
import AVFoundation
import CoreImage
import UIKit
import Accelerate

/**Result struct*/
struct Result {
    var detectedIndices = [Int]()
    var detectedScore = [Float]()
    let processTimeMs: Double
}

/// Information about a model file or labels file.
typealias FileInfo = (name: String, extension: String)

enum OrtModelError : Error {
    case error(_ message: String)
}

/// Information about the MobileNet model.
enum MobileNet {
    static let modelInfo: FileInfo = (name: "mobilenet_v2_float", extension: "ort")
    static let labelsInfo: FileInfo = (name: "labels", extension: "txt")
}

class ModelHandler {
    
    // MARK: - Inference Properties
    let threadCount: Int32
    let resultCount = 3
    let threadCountLimit = 10
    
    
    // MARK: - Model Parameters
    let batchSize = 1
    let inputChannels = 3
    let inputWidth = 224
    let inputHeight = 224
    
    /// `ORTSession` object for performin inference on a given model
    private let session: ORTSession

    // MARK: - Initialization
    init?(modelFileInfo: FileInfo, threadCount: Int32 = 1) throws {
        let modelFilename = modelFileInfo.name
        
        guard let modelPath = Bundle.main.path(
            forResource: modelFilename,
            ofType: modelFileInfo.extension
        ) else {
            print("Failed to get model file path with name: \(modelFilename).")
            return nil
        }
        
        let env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let options = try ORTSessionOptions()
        try options.setLogSeverityLevel(ORTLoggingLevel.verbose)
        self.threadCount = threadCount
        try options.setIntraOpNumThreads(threadCount) // TODO: check if calling the right methods
        
        do {
            session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
        } catch let error {
            print("Failed to create an ORTSession. error: \(error.localizedDescription)")
            return nil
        }
        
    }
    
    /**
     This methods preprocess the image,  runs the ort inferencesession and processes the result
     */
    func runModel(onFrame pixelBuffer: CVPixelBuffer) throws -> Result? {
        
        let sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        assert(sourcePixelFormat == kCVPixelFormatType_32ARGB ||
                sourcePixelFormat == kCVPixelFormatType_32BGRA ||
                sourcePixelFormat == kCVPixelFormatType_32RGBA)

        let imageChannels = 4
        assert(imageChannels >= inputChannels)

        ///preprocess the image
        let scaledSize = CGSize(width: inputWidth, height: inputHeight)
        guard let croppedPixelBuffer = preprocess(ofSize: scaledSize, pixelBuffer, imageChannels: imageChannels) else {
            return nil
        }

        let interval: TimeInterval
        var detectedIndices = [Int]()
        var detectedScore = [Float]()

        let inputName = "input"

        // Remove the alpha component from the image buffer to get the RGB data.
        guard let rgbData = rgbDataFromBuffer(
            croppedPixelBuffer,
            byteCount: batchSize * inputWidth * inputHeight * inputChannels
        ) else {
            print("Failed to convert the image buffer to RGB data.")
            return nil
        }

        let inputTensor = try ORTValue(tensorData: NSMutableData(data: rgbData),
                                       elementType: ORTTensorElementDataType.float,
                                       shape: [1, 3, 224, 224])
//        // Run the ORT InferenceSession
//        let startDate = Date()
//        let outputs = try session.run(withInputs:[inputName: inputTensor],
//                                      outputNames: ["output"],
//                                      runOptions: try ORTRunOptions())
//        interval = Date().timeIntervalSince(startDate) * 1000
//
//        guard let rawOutputValue = outputs["output"] else {
//           throw OrtModelError.error("failed to get model output")
//        }
//        let rawOutputData = try rawOutputValue.tensorData() as Data
//
//
//        guard let outputArr: [Float32] = arrayCopiedFromData(rawOutputData) else {
//            throw OrtModelError.error("failed to copy output data")
//        }
//
//        //Process the result(TopN), probabilities, etc.
//        let probabilities = softMax(modelResult: outputArr)
//        detectedIndices = getTop3(probabilities: probabilities)!
//        for idx in detectedIndices {
//            detectedScore.append(probabilities[idx])
//        }
//
//        //Return ORT SessionRun result
//        return Result(detectedIndices: detectedIndices, detectedScore: detectedScore, processTimeMs: interval)
        return Result(detectedIndices: [0], detectedScore: [0.66], processTimeMs: 55)
    }
    
    
    // MARK: - Helper Methods
    private func preprocess(
        ofSize scaledSize: CGSize,
        _ buffer: CVPixelBuffer,
        imageChannels: Int
    ) -> CVPixelBuffer? {
        
        let imageWidth = CVPixelBufferGetWidth(buffer)
        let imageHeight = CVPixelBufferGetHeight(buffer)
        let pixelBufferType = CVPixelBufferGetPixelFormatType(buffer)
        
        assert(pixelBufferType == kCVPixelFormatType_32BGRA)
        
        let inputImageRowBytes = CVPixelBufferGetBytesPerRow(buffer)
        
        let croppedSize = min(imageWidth, imageHeight)  // reduced-size versions of images for better recognizing
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        var originX = 0
        var originY = 0
        if imageWidth > imageHeight {
            originX = (imageWidth - imageHeight) / 2
        }
        else {
            originY = (imageHeight - imageWidth) / 2
        }
        
        // Find the biggest square in the pixel buffer and advance rows based on it.
        guard let inputBaseAddress = CVPixelBufferGetBaseAddress(buffer)?.advanced(
                by: originY * inputImageRowBytes + originX * imageChannels) else {
            return nil
        }
        
        // Get vImage_buffer
        var inputVImageBuffer = vImage_Buffer(
            data: inputBaseAddress, height: UInt(croppedSize), width: UInt(croppedSize),
            rowBytes: inputImageRowBytes)
        
        let croppedRowBytes = Int(scaledSize.width) * imageChannels
        guard  let croppedBytes = malloc(Int(scaledSize.height) * croppedRowBytes) else {
            return nil
        }
        var croppedVImageBuffer = vImage_Buffer(data: croppedBytes, height: UInt(scaledSize.height), width: UInt(scaledSize.width),
                                                rowBytes: croppedRowBytes)
        
        // Perform the scale operation on input image buffer and store it in cropped vImage buffer.
        let scaleError = vImageScale_ARGB8888(&inputVImageBuffer, &croppedVImageBuffer, nil, vImage_Flags(0))
        
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        guard scaleError == kvImageNoError else {
            return nil
        }
        
        let releaseCallBack: CVPixelBufferReleaseBytesCallback = {mutablePointer, pointer in
            
            if let pointer = pointer {
                free(UnsafeMutableRawPointer(mutating: pointer))
            }
        }
        
        var croppedPixelBuffer: CVPixelBuffer?
        
        // Converts the thumbnail vImage buffer to CVPixelBuffer
        let conversionStatus = CVPixelBufferCreateWithBytes(
            nil, Int(scaledSize.width), Int(scaledSize.height), pixelBufferType, croppedBytes,
            croppedRowBytes, releaseCallBack, nil, nil, &croppedPixelBuffer)
        
        guard conversionStatus == kCVReturnSuccess else {
            free(croppedBytes)
            return nil
        }
        
        return croppedPixelBuffer
    }
    
}


/// Returns the top 3 inference results indice sorted in descending order.
private func getTop3(probabilities: [Float32]) -> [Int]? {
    var indices : [Int]?
    for _ in 1...3 {
        var max : Float = 0.0
        var idx = 0
        for (i, prob) in probabilities.enumerated() {
            if (prob > max && indices?.contains(i) == false) {
                max = prob
                idx = i
            }
        }
        indices?.append(idx)
    }
    
    return indices
}

/// Calculates the softmax for the input array
private func softMax(modelResult: [Float32]) -> [Float32] {
    var labelVals = modelResult
    let max = labelVals.max()
    var sum : Float = 0.0
    
    for idx in labelVals.indices {
        labelVals[idx] = exp(labelVals[idx] - max!)
        sum += labelVals[idx]
    }
    if (sum != 0.0) {
        for i in labelVals.indices {
            labelVals[i] /= sum
        }
    }
    
    return labelVals
}

/// Returns the RGB data representation of the given image buffer.
func rgbDataFromBuffer(
    _ buffer: CVPixelBuffer,
    byteCount: Int,
    isModelQuantized: Bool = false
) -> Data? {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer {
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    }
    guard let sourceData = CVPixelBufferGetBaseAddress(buffer) else {
        return nil
    }
    
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let destinationChannelCount = 3
    let destinationBytesPerRow = destinationChannelCount * width
    
    var sourceBuffer = vImage_Buffer(data: sourceData,
                                     height: vImagePixelCount(height),
                                     width: vImagePixelCount(width),
                                     rowBytes: sourceBytesPerRow)
    
    guard let destinationData = malloc(height * destinationBytesPerRow) else {
        print("Error: out of memory")
        return nil
    }
    
    defer {
        free(destinationData)
    }
    
    var destinationBuffer = vImage_Buffer(data: destinationData,
                                          height: vImagePixelCount(height),
                                          width: vImagePixelCount(width),
                                          rowBytes: destinationBytesPerRow)
    
    let pixelBufferFormat = CVPixelBufferGetPixelFormatType(buffer)
    
    switch (pixelBufferFormat) {
    case kCVPixelFormatType_32BGRA:
        vImageConvert_BGRA8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
    case kCVPixelFormatType_32ARGB:
        vImageConvert_ARGB8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
    case kCVPixelFormatType_32RGBA:
        vImageConvert_RGBA8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
    default:
        // Unknown pixel format.
        return nil
    }
    
    let byteData = Data(bytes: destinationBuffer.data, count: destinationBuffer.rowBytes * height)
    //      if isModelQuantized {
    //          return byteData
    //      }
    
    // Not quantized, convert to floats
    let bytes = Array<UInt8>(unsafeData: byteData)!
    var floats = [Float]()
    for i in 0..<bytes.count {
        floats.append(Float(bytes[i]) / 255.0)
    }
    return Data(copyingBufferOf: floats)
}

func arrayCopiedFromData<T>(_ data: Data) -> [T]? {
    guard data.count % MemoryLayout<T>.stride == 0 else { return nil }
    
    return data.withUnsafeBytes {
        bytes -> [T] in
        return Array(bytes.bindMemory(to: T.self))
    }
}

// MARK: - Extensions
extension Data {
    /// Creates a new buffer by copying the buffer pointer of the given array.
    init<T>(copyingBufferOf array: [T]) {
        self = array.withUnsafeBufferPointer(Data.init)
    }
}

extension Array {
    /// Creates a new array from the bytes of the given unsafe data.
    init?(unsafeData: Data) {
        guard unsafeData.count % MemoryLayout<Element>.stride == 0 else { return nil }
        #if swift(>=5.0)
        self = unsafeData.withUnsafeBytes { .init($0.bindMemory(to: Element.self)) }
        #else
        self = unsafeData.withUnsafeBytes {
            .init(UnsafeBufferPointer<Element>(
                start: $0,
                count: unsafeData.count / MemoryLayout<Element>.stride
            ))
        }
        #endif  // swift(>=5.0)
    }
}
