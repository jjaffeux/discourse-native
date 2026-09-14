import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Extracts one bounded still without creating an AVPlayer or an audio session.
/// All ownership and completion changes happen on the main queue.
final class VideoThumbnailGenerator {
  private var generator: AVAssetImageGenerator?
  private var timeout: DispatchWorkItem?
  private var completion: ((Data?) -> Void)?

  func start(url: URL, completion: @escaping (Data?) -> Void) {
    precondition(Thread.isMainThread)
    precondition(self.completion == nil)
    self.completion = completion
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 1024, height: 1024)
    self.generator = generator

    let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
    self.timeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)

    generator.generateCGImagesAsynchronously(
      forTimes: [NSValue(time: CMTime(seconds: 0.1, preferredTimescale: 600))]
    ) { [weak self] _, image, _, status, _ in
      let data = status == .succeeded ? image.flatMap(Self.jpeg) : nil
      DispatchQueue.main.async { [weak self] in self?.finish(data) }
    }
  }

  func cancel() {
    precondition(Thread.isMainThread)
    finish(nil)
  }

  private func finish(_ data: Data?) {
    guard let completion else { return }
    self.completion = nil
    timeout?.cancel()
    timeout = nil
    generator?.cancelAllCGImageGeneration()
    generator = nil
    completion(data)
  }

  private static func jpeg(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      data, UTType.jpeg.identifier as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(destination, image, [
      kCGImageDestinationLossyCompressionQuality: 0.8
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination), data.length <= 2 * 1024 * 1024 else {
      return nil
    }
    return data as Data
  }
}
