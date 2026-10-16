import AVFoundation
import AVKit
import CoreImage
import Flutter
import UIKit
import WebRTC
import flutter_webrtc

/// Native PiP observes the same WebRTC track as Flutter. It owns only a renderer;
/// closing or tucking the system window must never end the call or stop a track.
final class VoicePictureInPicture: NSObject, AVPictureInPictureControllerDelegate {
  private let channel: FlutterMethodChannel
  private let sourceView: () -> UIView?
  private var sessionID: String?
  private var controller: AVPictureInPictureController?
  private var content: AVPictureInPictureVideoCallViewController?
  private let videoView = VoicePictureInPictureVideoView()
  private let caption = UILabel()
  private var track: RTCVideoTrack?
  private var foregroundObserver: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger, sourceView: @escaping () -> UIView?) {
    channel = FlutterMethodChannel(name: "org.discourse.native/voice_pip", binaryMessenger: messenger)
    self.sourceView = sourceView
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "configure":
        result(self.configure(call.arguments as? [String: Any] ?? [:]))
      case "clear":
        self.clear()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      // Flutter resumes either the full room or its own movable preview.
      self?.controller?.stopPictureInPicture()
    }
  }

  private func configure(_ arguments: [String: Any]) -> Bool {
    guard let id = arguments["sessionId"] as? String else { return false }
    if sessionID != id { clear(); sessionID = id }
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return false }
    if controller == nil {
      guard let source = sourceView(), source.window != nil else { return false }
      let content = AVPictureInPictureVideoCallViewController()
      content.preferredContentSize = CGSize(width: 4, height: 3)
      content.view.backgroundColor = .black
      videoView.translatesAutoresizingMaskIntoConstraints = false
      content.view.addSubview(videoView)
      caption.translatesAutoresizingMaskIntoConstraints = false
      caption.textColor = .white
      caption.font = .preferredFont(forTextStyle: .caption1)
      caption.numberOfLines = 2
      caption.backgroundColor = UIColor.black.withAlphaComponent(0.55)
      content.view.addSubview(caption)
      NSLayoutConstraint.activate([
        videoView.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
        videoView.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
        videoView.topAnchor.constraint(equalTo: content.view.topAnchor),
        videoView.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
        caption.leadingAnchor.constraint(equalTo: content.view.leadingAnchor, constant: 8),
        caption.trailingAnchor.constraint(lessThanOrEqualTo: content.view.trailingAnchor, constant: -8),
        caption.bottomAnchor.constraint(equalTo: content.view.bottomAnchor, constant: -8),
      ])
      let contentSource = AVPictureInPictureController.ContentSource(
        activeVideoCallSourceView: source, contentViewController: content
      )
      let controller = AVPictureInPictureController(contentSource: contentSource)
      controller.delegate = self
      controller.canStartPictureInPictureAutomaticallyFromInline = true
      self.content = content
      self.controller = controller
    }
    let roomName = arguments["roomName"] as? String ?? ""
    let recording = arguments["recording"] as? Bool == true
    let recordingLabel = arguments["recordingLabel"] as? String ?? ""
    caption.text = recording ? "● \(recordingLabel) · \(roomName)" : roomName

    let plugin = FlutterWebRTCPlugin.sharedSingleton()
    let trackID = arguments["trackId"] as? String
    let peerID = arguments["peerConnectionId"] as? String
    let next = trackID.flatMap {
      plugin?.track(forId: $0, peerConnectionId: peerID?.isEmpty == false ? peerID : nil) as? RTCVideoTrack
    }
    if track !== next {
      track?.remove(videoView)
      videoView.reset()
      track = next
      track?.add(videoView)
    }
    // iOS 18+ VoIP apps can keep capture running without an extra entitlement.
    // Older/unsupported devices retain audio and incoming video gracefully.
    if #available(iOS 16.0, *), arguments["cameraEnabled"] as? Bool == true,
      let session = plugin?.videoCapturer?.captureSession,
      session.isMultitaskingCameraAccessSupported {
      session.isMultitaskingCameraAccessEnabled = true
    }
    return true
  }

  private func clear() {
    controller?.canStartPictureInPictureAutomaticallyFromInline = false
    controller?.delegate = nil
    controller?.stopPictureInPicture()
    controller?.contentSource = nil
    controller = nil
    content = nil
    track?.remove(videoView)
    track = nil
    videoView.reset()
    videoView.setLive(false)
    videoView.removeFromSuperview()
    caption.removeFromSuperview()
    if let sessionID { emitActive(false, session: sessionID) }
    sessionID = nil
  }

  private func emitActive(_ active: Bool, session: String) {
    channel.invokeMethod("activeChanged", arguments: ["sessionId": session, "active": active])
  }

  func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    guard pictureInPictureController === controller, let sessionID else { return }
    videoView.setLive(true)
    emitActive(true, session: sessionID)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    guard pictureInPictureController === controller, let sessionID else { return }
    videoView.setLive(false)
    emitActive(false, session: sessionID)
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error) {
    guard pictureInPictureController === controller, let sessionID else { return }
    videoView.setLive(false)
    emitActive(false, session: sessionID)
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
    guard pictureInPictureController === controller, let sessionID else {
      completionHandler(false)
      return
    }
    channel.invokeMethod("restore", arguments: ["sessionId": sessionID]) { _ in completionHandler(true) }
  }

  deinit {
    if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
    track?.remove(videoView)
    controller?.delegate = nil
    controller?.canStartPictureInPictureAutomaticallyFromInline = false
    controller?.stopPictureInPicture()
    controller?.contentSource = nil
  }
}

/// AVKit cannot display Flutter textures in another app. Feed decoded frames
/// to a sample-buffer layer instead.
final class VoicePictureInPictureVideoView: UIView, RTCVideoRenderer {
  override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
  private var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
  private let frameRenderer = VoicePictureInPictureFrameRenderer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    displayLayer.videoGravity = .resizeAspectFill
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func setSize(_ size: CGSize) {}

  func setLive(_ enabled: Bool) {
    frameRenderer.setLive(enabled)
  }

  func reset() {
    frameRenderer.reset()
    displayLayer.flushAndRemoveImage()
  }

  func renderFrame(_ frame: RTCVideoFrame?) {
    frameRenderer.renderFrame(frame, isReady: { [weak self] in
      guard let self else { return false }
      if self.displayLayer.status == .failed { self.displayLayer.flush() }
      return self.displayLayer.isReadyForMoreMediaData
    }, present: { [weak self] output in
      self?.display(output)
    })
  }

  private func display(_ output: CVPixelBuffer) {
    var format: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
      imageBuffer: output, formatDescriptionOut: &format) == noErr, let format else { return }
    var timing = CMSampleTimingInfo(duration: .invalid,
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
      imageBuffer: output, formatDescription: format, sampleTiming: &timing,
      sampleBufferOut: &sample) == noErr, let sample else { return }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
      let entry = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(entry, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
    displayLayer.enqueue(sample)
  }
}

final class VoicePictureInPictureFrameRenderer {
  private let frameLock = NSLock()
  private var pending = false
  private var live = false
  private var hasFrame = false
  private var generation = 0
  private let conversionQueue = DispatchQueue(label: "org.discourse.native.voice-pip-conversion",
    qos: .userInitiated, autoreleaseFrequency: .workItem)
  private let convert: (RTCVideoFrame) -> CVPixelBuffer?

  init(convert: @escaping (RTCVideoFrame) -> CVPixelBuffer? =
    VoicePictureInPictureFrameConverter().presentationBuffer) {
    self.convert = convert
  }

  func setLive(_ enabled: Bool) {
    frameLock.lock()
    live = enabled
    frameLock.unlock()
  }

  func reset() {
    frameLock.lock()
    generation += 1
    hasFrame = false
    frameLock.unlock()
  }

  func renderFrame(_ frame: RTCVideoFrame?, isReady: @escaping () -> Bool,
    present: @escaping (CVPixelBuffer) -> Void, completion: (() -> Void)? = nil) {
    guard let frame else { return }
    frameLock.lock()
    // Prime AVKit with one frame inline, then render continuously only in PiP.
    if pending || (!live && hasFrame) { frameLock.unlock(); return }
    pending = true
    hasFrame = true
    let revision = generation
    frameLock.unlock()
    DispatchQueue.main.async { [self] in
      guard isCurrent(revision), isReady() else { finish(); completion?(); return }
      conversionQueue.async { [self] in
        let output = isCurrent(revision) ? convert(frame) : nil
        DispatchQueue.main.async { [self] in
          defer { finish(); completion?() }
          guard isCurrent(revision), let output, isReady() else { return }
          present(output)
        }
      }
    }
  }

  private func isCurrent(_ revision: Int) -> Bool {
    frameLock.lock()
    defer { frameLock.unlock() }
    return revision == generation
  }

  private func finish() {
    frameLock.lock()
    pending = false
    frameLock.unlock()
  }
}

final class VoicePictureInPictureFrameConverter {
  private lazy var imageContext = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
  private var pool: CVPixelBufferPool?
  private var poolSize = CGSize.zero

  func presentationBuffer(_ frame: RTCVideoFrame) -> CVPixelBuffer? {
    guard let source = pixelBuffer(frame.buffer) else { return nil }
    let cropped = (frame.buffer as? RTCCVPixelBuffer)?.requiresCropping() ?? false
    // Decoded upright frames can go directly to AVKit with no pixel copy.
    if frame.rotation == ._0 && !cropped { return source }
    // Background video calls cannot rely on app-owned GPU rendering.
    let rotation: CGImagePropertyOrientation
    switch frame.rotation {
    case ._90: rotation = .right
    case ._180: rotation = .down
    case ._270: rotation = .left
    default: rotation = .up
    }
    var image = CIImage(cvPixelBuffer: source)
    if let native = frame.buffer as? RTCCVPixelBuffer, native.requiresCropping() {
      // RTC crop coordinates start at the top; Core Image starts at the bottom.
      image = image.cropped(to: CGRect(x: Int(native.cropX),
        y: CVPixelBufferGetHeight(source) - Int(native.cropY) - Int(native.cropHeight),
        width: Int(native.cropWidth), height: Int(native.cropHeight)))
      image = image.transformed(by: CGAffineTransform(
        translationX: -image.extent.minX, y: -image.extent.minY))
    }
    image = image.oriented(rotation)
    let size = image.extent.size
    if pool == nil || size != poolSize {
      poolSize = size
      pool = nil
      CVPixelBufferPoolCreate(nil, nil, [
        kCVPixelBufferWidthKey: Int(size.width),
        kCVPixelBufferHeightKey: Int(size.height),
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey: [:],
      ] as CFDictionary, &pool)
    }
    guard let pool else { return nil }
    var output: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess,
      let output else { return nil }
    imageContext.render(image, to: output)
    return output
  }

  private func pixelBuffer(_ buffer: RTCVideoFrameBuffer) -> CVPixelBuffer? {
    if let native = buffer as? RTCCVPixelBuffer { return native.pixelBuffer }
    let planar = buffer.toI420()
    let width = Int(planar.width), height = Int(planar.height)
    var output: CVPixelBuffer?
    guard CVPixelBufferCreate(nil, width, height,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &output) == kCVReturnSuccess,
      let output else { return nil }
    CVPixelBufferLockBaseAddress(output, [])
    defer { CVPixelBufferUnlockBaseAddress(output, []) }
    guard let y = CVPixelBufferGetBaseAddressOfPlane(output, 0),
      let uv = CVPixelBufferGetBaseAddressOfPlane(output, 1) else { return nil }
    let yStride = CVPixelBufferGetBytesPerRowOfPlane(output, 0)
    let uvStride = CVPixelBufferGetBytesPerRowOfPlane(output, 1)
    for row in 0..<height {
      memcpy(y.advanced(by: row * yStride), planar.dataY.advanced(by: row * Int(planar.strideY)), width)
    }
    for row in 0..<Int(planar.chromaHeight) {
      let destination = uv.advanced(by: row * uvStride).assumingMemoryBound(to: UInt8.self)
      let u = planar.dataU.advanced(by: row * Int(planar.strideU))
      let v = planar.dataV.advanced(by: row * Int(planar.strideV))
      for column in 0..<Int(planar.chromaWidth) {
        destination[column * 2] = u[column]
        destination[column * 2 + 1] = v[column]
      }
    }
    return output
  }
}
