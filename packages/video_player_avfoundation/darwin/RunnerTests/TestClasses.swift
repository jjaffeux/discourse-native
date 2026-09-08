// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import AVFoundation
import Testing
import video_player_avfoundation_objc

@testable import video_player_avfoundation

#if os(iOS)
  import Flutter
  import UIKit
#else
  import FlutterMacOS
#endif

/// An AVPlayer subclass that records method call parameters for inspection.
// TODO(stuartmorgan): Replace with a protocol like the other classes.
@MainActor final class InspectableAVPlayer: AVPlayer {
  private(set) nonisolated(unsafe) var beforeTolerance: NSNumber?
  private(set) nonisolated(unsafe) var afterTolerance: NSNumber?
  private(set) nonisolated(unsafe) var lastSeekTime: CMTime = .invalid

  override func seek(
    to time: CMTime,
    toleranceBefore: CMTime,
    toleranceAfter: CMTime,
    completionHandler: @escaping @Sendable (Bool) -> Void
  ) {
    beforeTolerance = NSNumber(value: toleranceBefore.value)
    afterTolerance = NSNumber(value: toleranceAfter.value)
    lastSeekTime = time
    super.seek(
      to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter,
      completionHandler: completionHandler)
  }
}

final class TestAsset: NSObject, FVPAVAsset {
  let duration: CMTime
  let tracks: [AVAssetTrack]?

  var loadedTracksAsynchronously = false

  init(duration: CMTime = CMTime.zero, tracks: [AVAssetTrack]? = nil) {
    self.duration = duration
    self.tracks = tracks
    super.init()
  }

  func statusOfValue(forKey key: String, error outError: NSErrorPointer) -> AVKeyValueStatus {
    return tracks == nil ? .loading : .loaded
  }

  func loadValuesAsynchronously(forKeys keys: [String], completionHandler handler: (() -> Void)?) {
    handler?()
  }

  @available(macOS 12.0, iOS 15.0, *)
  func loadTracks(
    withMediaType mediaType: AVMediaType,
    completionHandler: @escaping ([AVAssetTrack]?, Error?) -> Void
  ) {
    loadedTracksAsynchronously = true
    completionHandler(tracks, nil)
  }

  func tracks(withMediaType mediaType: AVMediaType) -> [AVAssetTrack] {
    return tracks ?? []
  }
}

final class StubPlayerItem: NSObject, FVPAVPlayerItem {
  let asset: FVPAVAsset
  var videoComposition: AVVideoComposition? {
    didSet {
      videoCompositionUpdateCount += 1
      videoCompositionUpdatedOnMainThread = Thread.isMainThread
    }
  }
  private(set) var videoCompositionUpdateCount = 0
  private(set) var videoCompositionUpdatedOnMainThread = false

  init(asset: FVPAVAsset = TestAsset()) {
    self.asset = asset
    super.init()
  }
}

/// Explicit gates for the two asset requests made during player initialization.
/// Taking a completion removes it before invocation, matching AVFoundation's one-shot contract.
final class DeferredAsset: NSObject, FVPAVAsset {
  let duration = CMTime(value: 2, timescale: 1)
  private var status: AVKeyValueStatus = .loading
  private var valuesCompletion: (@Sendable () -> Void)?
  private var tracksCompletion: (@Sendable ([AVAssetTrack]?, Error?) -> Void)?
  private(set) var trackLoadCount = 0
  private(set) var tracksRequestedOnMainThread = false

  func statusOfValue(forKey key: String, error outError: NSErrorPointer) -> AVKeyValueStatus {
    return status
  }

  func loadValuesAsynchronously(
    forKeys keys: [String], completionHandler handler: (@Sendable () -> Void)?
  ) {
    #expect(keys == ["tracks"])
    #expect(valuesCompletion == nil)
    valuesCompletion = handler
  }

  @available(macOS 12.0, iOS 15.0, *)
  func loadTracks(
    withMediaType mediaType: AVMediaType,
    completionHandler: @escaping @Sendable ([AVAssetTrack]?, Error?) -> Void
  ) {
    #expect(mediaType == .video)
    #expect(tracksCompletion == nil)
    trackLoadCount += 1
    tracksRequestedOnMainThread = Thread.isMainThread
    tracksCompletion = completionHandler
  }

  func tracks(withMediaType mediaType: AVMediaType) -> [AVAssetTrack] {
    Issue.record("Deferred metadata tests require the asynchronous track API")
    return []
  }

  func takeValuesCompletion(status: AVKeyValueStatus = .loaded) throws -> @Sendable () -> Void {
    let completion = try #require(valuesCompletion)
    valuesCompletion = nil
    self.status = status
    return completion
  }

  func takeTracksCompletion() throws -> @Sendable ([AVAssetTrack]?, Error?) -> Void {
    let completion = try #require(tracksCompletion)
    tracksCompletion = nil
    return completion
  }

  func finishPendingLoads() {
    let values = valuesCompletion
    valuesCompletion = nil
    values?()
    let tracks = tracksCompletion
    tracksCompletion = nil
    tracks?([], nil)
  }
}

/// A local track with controllable transform loading; it never opens a media URL.
@objcMembers final class DeferredVideoTrack: NSObject, @unchecked Sendable {
  let transform: CGAffineTransform
  private var status: AVKeyValueStatus = .loading
  private var transformCompletion: (@Sendable () -> Void)?
  private(set) var transformLoadCount = 0
  private(set) var transformRequestedOnMainThread = false

  init(rotation: Int = 90) {
    switch rotation {
    case 90: transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
    case 180: transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
    case 270: transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
    default: transform = .identity
    }
    super.init()
  }

  // AVAssetTrack has no public initializer. The native pipeline uses Objective-C dispatch, so
  // this fake supplies its metadata selectors without constructing an AVFoundation track.
  var assetTrack: AVAssetTrack { unsafeBitCast(self, to: AVAssetTrack.self) }
  var preferredTransform: CGAffineTransform { transform }
  var naturalSize: CGSize { CGSize(width: 800, height: 600) }
  var trackID: CMPersistentTrackID { 1 }
  var minFrameDuration: CMTime { CMTime(value: 1, timescale: 24) }

  func statusOfValue(forKey key: String, error outError: NSErrorPointer)
    -> AVKeyValueStatus
  {
    return status
  }

  func loadValuesAsynchronously(
    forKeys keys: [String], completionHandler handler: (@Sendable () -> Void)?
  ) {
    #expect(keys == ["preferredTransform"])
    #expect(transformCompletion == nil)
    transformLoadCount += 1
    transformRequestedOnMainThread = Thread.isMainThread
    transformCompletion = handler
  }

  func takeTransformCompletion(status: AVKeyValueStatus = .loaded) throws -> @Sendable () -> Void {
    let completion = try #require(transformCompletion)
    transformCompletion = nil
    self.status = status
    return completion
  }

  func finishPendingLoad() {
    let completion = transformCompletion
    transformCompletion = nil
    completion?()
  }
}

final class StubBinaryMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}
  func send(
    onChannel channel: String,
    message: Data?,
    binaryReply callback: FlutterBinaryReply? = nil
  ) {}
  func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler? = nil
  ) -> FlutterBinaryMessengerConnection {
    return 0
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

final class TestTextureRegistry: NSObject, FlutterTextureRegistry {
  private(set) var registeredTexture = false
  private(set) var unregisteredTexture = false
  private(set) var textureFrameAvailableCount = 0

  func register(_ texture: FlutterTexture) -> Int64 {
    registeredTexture = true
    return 1
  }

  func unregisterTexture(_ textureId: Int64) {
    if textureId != 1 {
      Issue.record("Unregistering texture with wrong ID")
    }
    unregisteredTexture = true
  }

  func textureFrameAvailable(_ textureId: Int64) {
    if textureId != 1 {
      Issue.record("Texture frame available with wrong ID")
    }
    textureFrameAvailableCount += 1
  }
}

final class StubViewProvider: NSObject, FVPViewProvider {
  #if os(iOS)
    var viewController: UIViewController?
    init(viewController: UIViewController? = nil) {
      self.viewController = viewController
      super.init()
    }
  #else
    var view: NSView?
    init(view: NSView? = nil) {
      self.view = view
      super.init()
    }
  #endif
}

final class StubAssetProvider: NSObject, FVPAssetProvider {
  func lookupKey(forAsset asset: String) -> String? {
    return asset
  }

  func lookupKey(forAsset asset: String, fromPackage package: String) -> String? {
    return asset
  }
}

final class TestPixelBufferSource: NSObject, FVPPixelBufferSource {
  var pixelBuffer: CVPixelBuffer?
  let videoOutput: AVPlayerItemVideoOutput

  override init() {
    videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: String],
    ])
    super.init()
  }

  func itemTime(forHostTime hostTimeInSeconds: CFTimeInterval) -> CMTime {
    return CMTimeMakeWithSeconds(hostTimeInSeconds, preferredTimescale: 1000)
  }

  func hasNewPixelBuffer(forItemTime itemTime: CMTime) -> Bool {
    return pixelBuffer != nil
  }

  func copyPixelBuffer(
    forItemTime itemTime: CMTime,
    itemTimeForDisplay: UnsafeMutablePointer<CMTime>?
  ) -> CVPixelBuffer? {
    let buffer = pixelBuffer
    // Ownership is transferred to the caller.
    pixelBuffer = nil
    return buffer
  }
}

#if os(iOS)
  final class TestAudioSession: NSObject, FVPAVAudioSession {
    var category: AVAudioSession.Category = .ambient
    var categoryOptions: AVAudioSession.CategoryOptions = []
    private(set) var setCategoryCalled = false

    func setCategory(
      _ category: AVAudioSession.Category,
      with options: AVAudioSession.CategoryOptions
    ) throws {
      setCategoryCalled = true
      self.category = category
      self.categoryOptions = options
    }
  }
#endif

final class StubFVPAVFactory: NSObject, FVPAVFactory {
  let player: AVPlayer
  let playerItem: FVPAVPlayerItem
  let pixelBufferSource: FVPPixelBufferSource?
  private(set) var lastOutputSettings: [String: Any]?
  #if os(iOS)
    var audioSession: FVPAVAudioSession
  #endif

  init(
    player: AVPlayer? = nil,
    playerItem: FVPAVPlayerItem? = nil,
    pixelBufferSource: FVPPixelBufferSource? = nil
  ) {
    let dummyURL = URL(string: "https://flutter.dev")!
    self.player =
      player
      ?? AVPlayer(playerItem: AVPlayerItem(url: dummyURL))
    self.playerItem = playerItem ?? StubPlayerItem()
    self.pixelBufferSource = pixelBufferSource
    #if os(iOS)
      self.audioSession = TestAudioSession()
    #endif
    super.init()
  }

  func urlAsset(with url: URL, options: [String: Any]?) -> FVPAVAsset {
    return playerItem.asset
  }

  func playerItem(with asset: FVPAVAsset) -> FVPAVPlayerItem {
    return playerItem
  }

  func player(with playerItem: FVPAVPlayerItem) -> AVPlayer {
    return self.player
  }

  func videoOutput(outputSettings: [String: Any]) -> FVPPixelBufferSource {
    lastOutputSettings = outputSettings
    return pixelBufferSource ?? TestPixelBufferSource()
  }

  #if os(iOS)
    func sharedAudioSession() -> FVPAVAudioSession {
      return audioSession
    }
  #endif
}

final class StubFVPDisplayLink: NSObject, FVPDisplayLink {
  var running: Bool = false
  var duration: CFTimeInterval {
    return 1.0 / 60.0
  }
}

final class StubFVPDisplayLinkFactory: DisplayLinkFactory {
  let displayLink = StubFVPDisplayLink()
  var fireDisplayLink: (() -> Void)?

  func displayLink(
    with viewProvider: FVPViewProvider,
    callback: @escaping () -> Void
  ) -> FVPDisplayLink {
    fireDisplayLink = callback
    return displayLink
  }
}

final class StubEventListener: NSObject, FVPVideoEventListener {
  var onInitialized: (() -> Void)?
  private(set) var initializationDuration: Int64 = 0
  private(set) var initializationSize: CGSize = .zero
  private(set) var disposalCount = 0

  init(onInitialized: (() -> Void)? = nil) {
    self.onInitialized = onInitialized
    super.init()
  }

  func videoPlayerDidComplete() {}
  func videoPlayerDidEndBuffering() {}
  func videoPlayerDidError(withMessage errorMessage: String) {}
  func videoPlayerDidInitialize(withDuration duration: Int64, size: CGSize) {
    onInitialized?()
    initializationDuration = duration
    initializationSize = size
  }
  func videoPlayerDidSetPlaying(_ playing: Bool) {}
  func videoPlayerDidStartBuffering() {}
  func videoPlayerDidUpdateBufferRegions(_ regions: [[NSNumber]]!) {}
  func videoPlayerWasDisposed() {
    disposalCount += 1
  }
}

final class StubTexture: NSObject, FlutterTexture {
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    return nil
  }
}
