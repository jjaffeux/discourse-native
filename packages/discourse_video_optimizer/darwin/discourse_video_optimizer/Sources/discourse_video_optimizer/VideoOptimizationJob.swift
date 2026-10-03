import AVFoundation
import Foundation

/// One export. Main-actor ownership keeps cancellation and completion atomic.
@MainActor
final class VideoOptimizationJob {
  private var task: Task<Void, Never>?
  private var exporter: AVAssetExportSession?
  private var exporting = false
  private var completion: ((Bool) -> Void)?
  private var cancellationCompletions: [() -> Void] = []
  private var timeout: DispatchWorkItem?
  private var outputURL: URL?
  private var cancelled = false

  func start(input: URL, output: URL, completion: @escaping (Bool) -> Void) {
    precondition(self.completion == nil)
    self.completion = completion
    outputURL = output
    let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
    self.timeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 600, execute: timeout)
    task = Task { [weak self] in
      guard let self else { return }
      do {
        let asset = AVURLAsset(url: input)
        let source = try await VideoInfo.read(asset)
        guard !cancelled, self.completion != nil else { return }
        guard source.width > 0, source.height > 0,
          max(source.width, source.height) <= 8192,
          let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080),
          session.supportedFileTypes.contains(.mp4)
        else { finish(false); return }

        // Apple's H.264/AAC preset caps dimensions without upscaling, preserves
        // the track transform/timing, and converts HDR to SDR for H.264 output.
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.metadata = []
        exporter = session
        exporting = true
        session.exportAsynchronously { [weak self] in
          Task { @MainActor in
            guard let self else { return }
            self.exporting = false
            guard !self.cancelled, self.exporter?.status == .completed else {
              self.finish(false)
              return
            }
            self.task = Task {
              do {
                let result = try await VideoInfo.read(AVURLAsset(url: output))
                let inputBytes = try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                let outputBytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                self.finish(!self.cancelled && result.isValidOutput(for: source)
                  && outputBytes > 0 && outputBytes < inputBytes)
              } catch { self.finish(false) }
            }
          }
        }
      } catch { finish(false) }
    }
  }

  func cancel(completion: (() -> Void)? = nil) {
    if let completion { cancellationCompletions.append(completion) }
    cancelled = true
    task?.cancel()
    if exporting {
      // Wait for exportAsynchronously to acknowledge cancellation before the
      // caller can delete the output or start another hardware encode.
      exporter?.cancelExport()
    } else {
      finish(false)
    }
  }

  private func finish(_ success: Bool) {
    timeout?.cancel()
    timeout = nil
    task = nil
    exporter = nil
    if !success, let outputURL { try? FileManager.default.removeItem(at: outputURL) }
    let reply = completion
    completion = nil
    reply?(success)
    let waiters = cancellationCompletions
    cancellationCompletions.removeAll()
    waiters.forEach { $0() }
  }
}

private struct VideoInfo {
  let width: Double
  let height: Double
  let duration: Double
  let audioTracks: Int
  let h264: Bool
  let aac: Bool

  static func read(_ asset: AVAsset) async throws -> VideoInfo {
    let video = try await asset.loadTracks(withMediaType: .video)
    let audio = try await asset.loadTracks(withMediaType: .audio)
    guard video.count == 1, audio.count <= 1 else { throw InvalidVideo() }
    let size = try await video[0].load(.naturalSize)
    let transform = try await video[0].load(.preferredTransform)
    let display = CGRect(origin: .zero, size: size).applying(transform)
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite, duration > 0 else { throw InvalidVideo() }
    let formats = try await video[0].load(.formatDescriptions)
    let audioFormats = try await audio.first?.load(.formatDescriptions) ?? []
    return VideoInfo(
      width: abs(display.width), height: abs(display.height), duration: duration,
      audioTracks: audio.count,
      h264: formats.allSatisfy { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 },
      aac: audioFormats.allSatisfy { CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC }
    )
  }

  func isValidOutput(for source: VideoInfo) -> Bool {
    width > 0 && height > 0 && h264 && aac && audioTracks == source.audioTracks
      && abs(duration - source.duration) <= 0.25
      && width <= source.width + 2 && height <= source.height + 2
      && max(width, height) <= 1920 && min(width, height) <= 1080
      && abs(width / height - source.width / source.height) < 0.02
  }

  private struct InvalidVideo: Error {}
}
