import AVFoundation
import CoreVideo
import XCTest
@testable import VideoOptimization

@MainActor
final class VideoOptimizationTests: XCTestCase {
  func testDownscalesFourKWithoutChangingAspectRatio() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = try await makeVideo(in: directory, width: 3840, height: 2160, frames: 2)
    let output = directory.appendingPathComponent("small.mp4")
    let job = VideoOptimizationJob()
    let success = await withCheckedContinuation { continuation in
      job.start(input: input, output: output) { continuation.resume(returning: $0) }
    }
    XCTAssertTrue(success)
    let asset = AVURLAsset(url: output)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
    XCTAssertEqual(size.width, 1920)
    XCTAssertEqual(size.height, 1080)
    let audio = try await asset.loadTracks(withMediaType: .audio)
    XCTAssertTrue(audio.isEmpty)
  }

  func testExportsSmallerH264WithRotationAndAudioPreserved() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for rotated in [false, true] {
      let video = try await makeVideo(in: directory, rotated: rotated)
      let input = try await addAudio(to: video, in: directory)
      let output = directory.appendingPathComponent(UUID().uuidString + ".mp4")
      let job = VideoOptimizationJob()
      let success = await withCheckedContinuation { continuation in
        job.start(input: input, output: output) { continuation.resume(returning: $0) }
      }
      XCTAssertTrue(success)
      let asset = AVURLAsset(url: output)
      let tracks = try await asset.loadTracks(withMediaType: .video)
      let track = try XCTUnwrap(tracks.first)
      let size = try await track.load(.naturalSize)
      let transform = try await track.load(.preferredTransform)
      let display = CGRect(origin: .zero, size: size).applying(transform)
      XCTAssertEqual(abs(display.width), rotated ? 160 : 288, accuracy: 2)
      XCTAssertEqual(abs(display.height), rotated ? 288 : 160, accuracy: 2)
      let formats = try await track.load(.formatDescriptions)
      XCTAssertEqual(CMFormatDescriptionGetMediaSubType(try XCTUnwrap(formats.first)), kCMVideoCodecType_H264)
      let audio = try await asset.loadTracks(withMediaType: .audio)
      XCTAssertEqual(audio.count, 1)
      let duration = try await asset.load(.duration).seconds
      XCTAssertEqual(duration, 1, accuracy: 0.1)
      let inputSize = try input.resourceValues(forKeys: [.fileSizeKey]).fileSize!
      let outputSize = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize!
      XCTAssertLessThan(outputSize, inputSize)
      XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }
  }

  func testCancellationBeforeLoadingCompletesOnlyOnce() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = try await makeVideo(in: directory)
    let output = directory.appendingPathComponent("cancelled.mp4")
    let job = VideoOptimizationJob()
    var completions = 0
    var cancellations = 0
    job.start(input: input, output: output) { success in
      completions += 1
      XCTAssertFalse(success)
    }
    job.cancel { cancellations += 1 }
    job.cancel { cancellations += 1 }
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(completions, 1)
    XCTAssertEqual(cancellations, 2)
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
  }

  func testCancellationDuringExportClosesAndRemovesOutput() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = try await makeVideo(in: directory, width: 1920, height: 1080, frames: 48)
    let output = directory.appendingPathComponent("cancelled.mp4")
    let job = VideoOptimizationJob()
    let completed = expectation(description: "export cancelled")
    job.start(input: input, output: output) { success in
      XCTAssertFalse(success)
      completed.fulfill()
    }
    // Give asynchronous loading/export a chance to begin, then await the native
    // cancellation acknowledgement before examining temporary-file ownership.
    try await Task.sleep(nanoseconds: 20_000_000)
    await withCheckedContinuation { continuation in job.cancel { continuation.resume() } }
    await fulfillment(of: [completed], timeout: 5)
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
  }

  func testUnavailableInputReturnsFalseWithoutOutput() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("output.mp4")
    let job = VideoOptimizationJob()
    let result = await withCheckedContinuation { continuation in
      job.start(input: directory.appendingPathComponent("missing.mov"), output: output) {
        continuation.resume(returning: $0)
      }
    }
    XCTAssertFalse(result)
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func makeVideo(in directory: URL, rotated: Bool = false,
      width: Int = 288, height: Int = 160, frames: Int = 24) async throws -> URL {
    let url = directory.appendingPathComponent(UUID().uuidString + ".mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.proRes422,
      AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    if rotated {
      input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0)
    }
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ])
    writer.add(input)
    XCTAssertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<frames {
      while !input.isReadyForMoreMediaData {
        if writer.status == .failed { throw try XCTUnwrap(writer.error) }
        try await Task.sleep(nanoseconds: 1_000_000)
      }
      var buffer: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
      let pixels = try XCTUnwrap(buffer)
      CVPixelBufferLockBaseAddress(pixels, [])
      let pointer = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
      let stride = CVPixelBufferGetBytesPerRow(pixels)
      for y in 0..<height {
        for x in 0..<width {
          let offset = y * stride + x * 4
          pointer[offset] = UInt8((x + frame * 3) % 256)
          pointer[offset + 1] = UInt8((y + frame) % 256)
          pointer[offset + 2] = UInt8((x + y) % 256)
          pointer[offset + 3] = 255
        }
      }
      CVPixelBufferUnlockBaseAddress(pixels, [])
      XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)))
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: Int64(frames), timescale: 24))
    await writer.finishWriting()
    XCTAssertEqual(writer.status, .completed)
    return url
  }

  private func addAudio(to video: URL, in directory: URL) async throws -> URL {
    // One second of PCM provides an independent audio track to detect accidental
    // silent exports and exercises the native AAC conversion.
    var wav = Data()
    func text(_ value: String) { wav.append(contentsOf: value.utf8) }
    func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
    func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
    text("RIFF"); u32(36 + 96000); text("WAVEfmt "); u32(16)
    u16(1); u16(1); u32(48000); u32(96000); u16(2); u16(16)
    text("data"); u32(96000); wav.append(Data(repeating: 0, count: 96000))
    let audioURL = directory.appendingPathComponent(UUID().uuidString + ".wav")
    try wav.write(to: audioURL)
    let composition = AVMutableComposition()
    let videoAsset = AVURLAsset(url: video)
    let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
    let videoTrack = try XCTUnwrap(videoTracks.first)
    let destination = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
    let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 48000))
    try destination.insertTimeRange(range, of: videoTrack, at: .zero)
    destination.preferredTransform = try await videoTrack.load(.preferredTransform)
    let audioAsset = AVURLAsset(url: audioURL)
    let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
    let audioDestination = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
    try withExtendedLifetime(audioAsset) {
      try audioDestination.insertTimeRange(range, of: try XCTUnwrap(audioTracks.first), at: .zero)
    }
    let result = directory.appendingPathComponent(UUID().uuidString + ".mov")
    let export = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
    export.outputURL = result
    export.outputFileType = .mov
    await export.export()
    XCTAssertEqual(export.status, .completed)
    return result
  }
}
