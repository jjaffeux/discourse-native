// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import AVFoundation
import Testing
import video_player_avfoundation_objc

@preconcurrency @testable import video_player_avfoundation

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

private let mp4TestURI =
  "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4"
private let hlsTestURI =
  "https://flutter.github.io/assets-for-api-docs/assets/videos/hls/bee.m3u8"
private let mp3AudioTestURI =
  "https://flutter.github.io/assets-for-api-docs/assets/audio/rooster.mp3"
private let hlsAudioTestURI =
  "https://flutter.github.io/assets-for-api-docs/assets/videos/hls/bee_audio_only.m3u8"

@MainActor struct VideoPlayerTests {

  @Test func blankVideoBugWithEncryptedVideoStreamAndInvertedAspectRatioBugForSomeVideoStream()
    throws
  {
    // This is to fix 2 bugs: 1. blank video for encrypted video streams on iOS 16
    // (https://github.com/flutter/flutter/issues/111457) and 2. swapped width and height for some
    // video streams (not just iOS 16).  (https://github.com/flutter/flutter/issues/109116). An
    // invisible AVPlayerLayer is used to overwrite the protection of pixel buffers in those streams
    // for issue #1, and restore the correct width and height for issue #2.
    #if os(iOS)
      let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
      let viewController = UIViewController()
      viewController.view = view
      let viewProvider = StubViewProvider(viewController: viewController)
    #else
      let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
      view.wantsLayer = true
      let viewProvider = StubViewProvider(view: view)
    #endif
    let videoPlayerPlugin = try createInitializedPlugin(viewProvider: viewProvider)

    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: mp4TestURI, httpHeaders: [:]))
    let player =
      videoPlayerPlugin.playersByIdentifier[identifiers.playerId] as! FVPTextureBasedVideoPlayer

    #expect(player.playerLayer.superlayer == view.layer)
  }

  @Test func playerForPlatformViewDoesNotRegisterTexture() throws {
    let textureRegistry = TestTextureRegistry()
    let stubDisplayLinkFactory = StubFVPDisplayLinkFactory()
    let videoPlayerPlugin = try createInitializedPlugin(
      displayLinkFactory: stubDisplayLinkFactory,
      textureRegistry: textureRegistry)

    _ = try videoPlayerPlugin.createPlatformViewPlayer(
      options: CreationOptions(uri: hlsTestURI, httpHeaders: [:]))

    #expect(!textureRegistry.registeredTexture)
  }

  @Test func seekToWhilePausedStartsDisplayLinkTemporarily() async throws {
    let stubDisplayLinkFactory = StubFVPDisplayLinkFactory()
    let mockVideoOutput = TestPixelBufferSource()
    // Display link and frame updater wire-up is currently done in FVPVideoPlayerPlugin, so create
    // the player via the plugin instead of directly to include that logic in the test.
    let videoPlayerPlugin = try createInitializedPlugin(
      avFactory: StubFVPAVFactory(pixelBufferSource: mockVideoOutput),
      displayLinkFactory: stubDisplayLinkFactory)

    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: hlsTestURI, httpHeaders: [:]))
    let player =
      videoPlayerPlugin.playersByIdentifier[identifiers.playerId] as! FVPTextureBasedVideoPlayer

    // Ensure that the video playback is paused before seeking.
    var error: FlutterError?
    player.pauseWithError(&error)
    #expect(error == nil)

    await asyncSeekTo(player: player, time: 1234)

    // Seeking to a new position should start the display link temporarily.
    #expect(stubDisplayLinkFactory.displayLink.running)

    // Simulate a buffer being available.
    var bufferRef: CVPixelBuffer?
    CVPixelBufferCreate(nil, 1, 1, kCVPixelFormatType_32BGRA, nil, &bufferRef)
    mockVideoOutput.pixelBuffer = bufferRef
    // Simulate a callback from the engine to request a new frame.
    stubDisplayLinkFactory.fireDisplayLink?()
    player.copyPixelBuffer()
    // Since a frame was found, and the video is paused, the display link should be paused again.
    #expect(!stubDisplayLinkFactory.displayLink.running)
  }

  @Test func initStartsDisplayLinkTemporarily() throws {
    let stubDisplayLinkFactory = StubFVPDisplayLinkFactory()
    let mockVideoOutput = TestPixelBufferSource()
    let videoPlayerPlugin = try createInitializedPlugin(
      avFactory: StubFVPAVFactory(pixelBufferSource: mockVideoOutput),
      displayLinkFactory: stubDisplayLinkFactory)

    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: hlsTestURI, httpHeaders: [:]))

    // Init should start the display link temporarily.
    #expect(stubDisplayLinkFactory.displayLink.running)

    // Simulate a buffer being available.
    var bufferRef: CVPixelBuffer?
    CVPixelBufferCreate(nil, 1, 1, kCVPixelFormatType_32BGRA, nil, &bufferRef)
    mockVideoOutput.pixelBuffer = bufferRef
    // Simulate a callback from the engine to request a new frame.
    let player =
      videoPlayerPlugin.playersByIdentifier[identifiers.playerId] as! FVPTextureBasedVideoPlayer
    stubDisplayLinkFactory.fireDisplayLink?()
    player.copyPixelBuffer()
    // Since a frame was found, and the video is paused, the display link should be paused again.
    #expect(!stubDisplayLinkFactory.displayLink.running)
  }

  @Test func seekToWhilePlayingDoesNotStopDisplayLink() async throws {
    let stubDisplayLinkFactory = StubFVPDisplayLinkFactory()
    let mockVideoOutput = TestPixelBufferSource()
    let videoPlayerPlugin = try createInitializedPlugin(
      avFactory: StubFVPAVFactory(pixelBufferSource: mockVideoOutput),
      displayLinkFactory: stubDisplayLinkFactory)

    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: hlsTestURI, httpHeaders: [:]))
    let player =
      videoPlayerPlugin.playersByIdentifier[identifiers.playerId] as! FVPTextureBasedVideoPlayer

    // Ensure that the video is playing before seeking.
    var error: FlutterError?
    player.playWithError(&error)
    #expect(error == nil)

    await asyncSeekTo(player: player, time: 1234)

    #expect(stubDisplayLinkFactory.displayLink.running)

    // Simulate a buffer being available.
    var bufferRef: CVPixelBuffer?
    CVPixelBufferCreate(nil, 1, 1, kCVPixelFormatType_32BGRA, nil, &bufferRef)
    mockVideoOutput.pixelBuffer = bufferRef
    // Simulate a callback from the engine to request a new frame.
    stubDisplayLinkFactory.fireDisplayLink?()
    // Since the video was playing, the display link should not be paused after getting a buffer.
    #expect(stubDisplayLinkFactory.displayLink.running)
  }

  @Test func pauseWhileWaitingForFrameDoesNotStopDisplayLink() throws {
    let stubDisplayLinkFactory = StubFVPDisplayLinkFactory()
    // Display link and frame updater wire-up is currently done in FVPVideoPlayerPlugin, so create
    // the player via the plugin instead of directly to include that logic in the test.
    let videoPlayerPlugin = try createInitializedPlugin(displayLinkFactory: stubDisplayLinkFactory)

    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: hlsTestURI, httpHeaders: [:]))
    let player =
      videoPlayerPlugin.playersByIdentifier[identifiers.playerId] as! FVPTextureBasedVideoPlayer

    // Run a play/pause cycle to force the pause codepath to run completely.
    var error: FlutterError?
    player.playWithError(&error)
    #expect(error == nil)
    player.pauseWithError(&error)
    #expect(error == nil)

    // Since a buffer hasn't been available yet, the pause should not have stopped the display link.
    #expect(stubDisplayLinkFactory.displayLink.running)
  }

  @Test func disposeWhilePlayingStopsDisplayLink() async throws {
    let stubDisplayLinkFactory = StubFVPDisplayLinkFactory()
    let mockVideoOutput = TestPixelBufferSource()
    let videoPlayerPlugin = try createInitializedPlugin(
      avFactory: StubFVPAVFactory(pixelBufferSource: mockVideoOutput),
      displayLinkFactory: stubDisplayLinkFactory)

    var error: FlutterError?
    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: hlsTestURI, httpHeaders: [:]))
    let player =
      videoPlayerPlugin.playersByIdentifier[identifiers.playerId] as! FVPTextureBasedVideoPlayer

    player.playWithError(&error)
    #expect(error == nil)
    player.disposeWithError(&error)
    #expect(error == nil)

    #expect(!stubDisplayLinkFactory.displayLink.running)
  }

  @Test func deregistersFromPlayer() throws {
    let videoPlayerPlugin = try createInitializedPlugin()

    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: mp4TestURI, httpHeaders: [:]))
    let player = try #require(videoPlayerPlugin.playersByIdentifier[identifiers.playerId])

    var error: FlutterError?
    player.disposeWithError(&error)
    #expect(error == nil)
    #expect(videoPlayerPlugin.playersByIdentifier.count == 0)
  }

  @Test func bufferingStateFromPlayer() async throws {
    // TODO(stuartmorgan): Rewrite this test to use stubs, instead of running for 10
    // seconds with a real player and hoping to get buffer status updates.
    let realObjectFactory = FVPDefaultAVFactory()
    let videoPlayerPlugin = try createInitializedPlugin(avFactory: realObjectFactory)

    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: mp4TestURI, httpHeaders: [:]))
    let player = try #require(videoPlayerPlugin.playersByIdentifier[identifiers.playerId])
    let avPlayer = player.player
    avPlayer.play()

    let eventSink: FlutterEventSink = { event in
      guard let event = event as? [String: Any], let eventType = event["event"] as? String else {
        return
      }
      if eventType == "bufferingEnd" {
        #expect(avPlayer.currentItem!.isPlaybackLikelyToKeepUp)
      }
      if eventType == "bufferingStart" {
        #expect(!avPlayer.currentItem!.isPlaybackLikelyToKeepUp)
      }
    }
    (player.eventListener as? FlutterStreamHandler)?.onListen(
      withArguments: nil, eventSink: eventSink)

    // Load for a while to let some buffer events happen.
    try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
  }

  private func durationApproximatelyEquals(_ actual: Int64, _ expected: Int64, tolerance: Int64)
    -> Bool
  {
    return abs(actual - expected) < tolerance
  }

  @Test func videoControls() async throws {
    let eventListener = try await sanityTestURI(mp4TestURI)
    #expect(eventListener.initializationSize.height == 720)
    #expect(eventListener.initializationSize.width == 1280)
    #expect(durationApproximatelyEquals(eventListener.initializationDuration, 4000, tolerance: 200))
  }

  @Test func audioControls() async throws {
    let eventListener = try await sanityTestURI(mp3AudioTestURI)
    #expect(eventListener.initializationSize.height == 0)
    #expect(eventListener.initializationSize.width == 0)
    #expect(durationApproximatelyEquals(eventListener.initializationDuration, 5400, tolerance: 200))
  }

  @Test func hLSControls() async throws {
    let eventListener = try await sanityTestURI(hlsTestURI)
    #expect(eventListener.initializationSize.height == 720)
    #expect(eventListener.initializationSize.width == 1280)
    #expect(durationApproximatelyEquals(eventListener.initializationDuration, 4000, tolerance: 200))
  }

  @Test(.disabled("Flaky"), .bug("https://github.com/flutter/flutter/issues/164381"))
  func audioOnlyHLSControls() async throws {
    let eventListener = try await sanityTestURI(hlsAudioTestURI)
    #expect(eventListener.initializationSize.height == 0)
    #expect(eventListener.initializationSize.width == 0)
    #expect(durationApproximatelyEquals(eventListener.initializationDuration, 4000, tolerance: 200))
  }

  #if os(iOS)
    @Test func transformFixOrientationUp() {
      let size = CGSize(width: 800, height: 600)
      let naturalTransform = CGAffineTransform.identity
      let t = FVPGetStandardizedTrackTransform(naturalTransform, size)
      #expect(t.tx == 0)
      #expect(t.ty == 0)
    }

    @Test func transformFixOrientationDown() {
      let size = CGSize(width: 800, height: 600)
      let naturalTransform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
      let t = FVPGetStandardizedTrackTransform(naturalTransform, size)
      #expect(t.tx == size.width)
      #expect(t.ty == size.height)
    }

    @Test func transformFixOrientationLeft() {
      let size = CGSize(width: 800, height: 600)
      let naturalTransform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
      let t = FVPGetStandardizedTrackTransform(naturalTransform, size)
      #expect(t.tx == 0)
      #expect(t.ty == size.width)
    }

    @Test func transformFixOrientationRight() {
      let size = CGSize(width: 800, height: 600)
      let naturalTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
      let t = FVPGetStandardizedTrackTransform(naturalTransform, size)
      #expect(t.tx == size.height)
      #expect(t.ty == 0)
    }

    @Test func transformFixOrientationUpMirrored() {
      let size = CGSize(width: 800, height: 600)
      let naturalTransform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
      let t = FVPGetStandardizedTrackTransform(naturalTransform, size)
      #expect(t.tx == size.width)
      #expect(t.ty == 0)
    }

    @Test func transformFixOrientationDownMirrored() {
      let size = CGSize(width: 800, height: 600)
      let naturalTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
      let t = FVPGetStandardizedTrackTransform(naturalTransform, size)
      #expect(t.tx == 0)
      #expect(t.ty == size.height)
    }

    @Test func transformFixOrientationLeftMirrored() {
      let size = CGSize(width: 800, height: 600)
      let naturalTransform = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 0, ty: 0)
      let t = FVPGetStandardizedTrackTransform(naturalTransform, size)
      #expect(t.tx == size.height)
      #expect(t.ty == size.width)
    }

    @Test func transformFixOrientationRightMirrored() {
      let size = CGSize(width: 800, height: 600)
      let naturalTransform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
      let t = FVPGetStandardizedTrackTransform(naturalTransform, size)
      #expect(t.tx == 0)
      #expect(t.ty == 0)
    }
  #endif

  @Test func seekToleranceWhenNotSeekingToEnd() async {
    let inspectableAVPlayer = InspectableAVPlayer()
    let stubAVFactory = StubFVPAVFactory(player: inspectableAVPlayer)
    let player = FVPVideoPlayer(
      playerItem: StubPlayerItem(),
      avFactory: stubAVFactory,
      viewProvider: StubViewProvider())
    let listener = StubEventListener()
    player.eventListener = listener

    await asyncSeekTo(player: player, time: 1234)

    #expect(inspectableAVPlayer.beforeTolerance?.intValue == 0)
    #expect(inspectableAVPlayer.afterTolerance?.intValue == 0)
  }

  @Test func seekToleranceWhenSeekingToEnd() async {
    let inspectableAVPlayer = InspectableAVPlayer()
    let stubAVFactory = StubFVPAVFactory(player: inspectableAVPlayer)
    let player = FVPVideoPlayer(
      playerItem: StubPlayerItem(),
      avFactory: stubAVFactory,
      viewProvider: StubViewProvider())
    let listener = StubEventListener()
    player.eventListener = listener

    await asyncSeekTo(player: player, time: 0)

    #expect((inspectableAVPlayer.beforeTolerance?.intValue ?? 0) > 0)
    #expect((inspectableAVPlayer.afterTolerance?.intValue ?? 0) > 0)
  }

  @Test func setPreventsDisplaySleepDuringVideoPlayback() {
    let stubAVFactory = StubFVPAVFactory(player: AVPlayer())
    let player = FVPVideoPlayer(
      playerItem: StubPlayerItem(),
      avFactory: stubAVFactory,
      viewProvider: StubViewProvider())
    let listener = StubEventListener()
    player.eventListener = listener

    var error: FlutterError?
    // The setter should update the underlying AVPlayer in both directions.
    player.setPreventsDisplaySleepDuringVideoPlayback(false, error: &error)
    #expect(error == nil)
    #expect(player.player.preventsDisplaySleepDuringVideoPlayback == false)

    player.setPreventsDisplaySleepDuringVideoPlayback(true, error: &error)
    #expect(error == nil)
    #expect(player.player.preventsDisplaySleepDuringVideoPlayback == true)
  }

  /// Sanity checks a video player playing the given URL with the actual AVPlayer. This is essentially
  /// a mini integration test of the player component.
  ///
  /// Returns the stub event listener to allow tests to inspect the call state.
  func sanityTestURI(_ testURI: String) async throws -> StubEventListener {
    let realObjectFactory = FVPDefaultAVFactory()
    let testURL = try #require(URL(string: testURI))
    let player = FVPVideoPlayer(
      playerItem: playerItem(with: testURL, factory: realObjectFactory),
      avFactory: realObjectFactory,
      viewProvider: StubViewProvider())

    let listener = StubEventListener()
    await withCheckedContinuation { continuation in
      listener.onInitialized = { continuation.resume() }
      player.eventListener = listener
    }

    // Starts paused.
    let avPlayer = player.player
    #expect(avPlayer.rate == 0)
    #expect(avPlayer.volume == 1)
    #expect(avPlayer.timeControlStatus == .paused)

    // Change playback speed.
    var error: FlutterError?
    player.setPlaybackSpeed(2, error: &error)
    #expect(error == nil)
    player.playWithError(&error)
    #expect(error == nil)
    #expect(avPlayer.rate == 2)
    #expect(avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate)

    // Volume
    player.setVolume(0.1, error: &error)
    #expect(error == nil)
    #expect(avPlayer.volume == 0.1)

    return listener
  }

  // Checks whether [AVPlayer rate] KVO observations are correctly detached.
  // - https://github.com/flutter/flutter/issues/124937
  //
  // Failing to de-register results in a crash in [AVPlayer willChangeValueForKey:].
  @Test func doesNotCrashOnRateObservationAfterDisposal() async throws {
    let realObjectFactory = FVPDefaultAVFactory()

    var avPlayer: AVPlayer? = nil
    weak var weakPlayer: FVPVideoPlayer? = nil

    // Autoreleasepool is needed to simulate conditions of FVPVideoPlayer deallocation.
    try autoreleasepool {
      let videoPlayerPlugin = try createInitializedPlugin(avFactory: realObjectFactory)

      var error: FlutterError?
      let identifiers = try videoPlayerPlugin.createTexturePlayer(
        options: CreationOptions(uri: mp4TestURI, httpHeaders: [:]))

      let player = try #require(videoPlayerPlugin.playersByIdentifier[identifiers.playerId])
      weakPlayer = player
      avPlayer = player.player

      player.disposeWithError(&error)
      #expect(error == nil)
    }

    // Wait for the weak pointer to be invalidated, indicating that the player has been deallocated.
    let checkInterval = 0.1
    let maxTries = Int64(30 / checkInterval)
    for _ in 1...maxTries {
      if weakPlayer == nil {
        break
      }
      try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
    }

    await MainActor.run {
      avPlayer?.willChangeValue(forKey: "rate")
      avPlayer?.didChangeValue(forKey: "rate")
    }
    // No assertions needed. Lack of crash is a success.
  }

  // During the hot reload:
  //  1. `[FVPVideoPlayer onTextureUnregistered:]` gets called.
  //  2. `[FVPVideoPlayerPlugin initialize:]` gets called.
  //
  // Both of these methods dispatch [FVPVideoPlayer dispose] on the main thread
  // leading to a possible crash when de-registering observers twice.
  @Test func hotReloadDoesNotCrash() async throws {
    weak var weakPlayer: FVPVideoPlayer? = nil

    // Autoreleasepool is needed to simulate conditions of FVPVideoPlayer deallocation.
    try autoreleasepool {
      let videoPlayerPlugin = try createInitializedPlugin(avFactory: StubFVPAVFactory())

      let identifiers = try videoPlayerPlugin.createTexturePlayer(
        options: CreationOptions(uri: mp4TestURI, httpHeaders: [:]))

      let player =
        videoPlayerPlugin.playersByIdentifier[identifiers.playerId] as! FVPTextureBasedVideoPlayer
      weakPlayer = player

      player.onTextureUnregistered(StubTexture())

      try videoPlayerPlugin.initialize()
    }

    // Wait for the weak pointer to be invalidated, indicating that the player has been deallocated.
    let checkInterval = 0.1
    let maxTries = Int64(30 / checkInterval)
    for _ in 1...maxTries {
      if weakPlayer == nil {
        break
      }
      try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
    }
    // No assertions needed. Lack of crash is a success.
  }

  @Test func failedToLoadVideoEventShouldBeAlwaysSent() async throws {
    // Use real objects to test a real failure flow.
    let realObjectFactory = FVPDefaultAVFactory()
    let videoPlayerPlugin = try createInitializedPlugin(avFactory: realObjectFactory)

    // Provide a URI that is a valid URI, but not a video, to trigger a failure inside AVPlayer.
    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: "https://flutter.dev", httpHeaders: [:]))
    let player = try #require(videoPlayerPlugin.playersByIdentifier[identifiers.playerId])

    await withCheckedContinuation { continuation in
      // TODO(stuartmorgan): Update this test to instead use a mock listener, and add separate unit
      // tests of FVPEventBridge.
      let eventSink: FlutterEventSink = { event in
        if event is FlutterError {
          continuation.resume()
        }
      }
      (player.eventListener as? FlutterStreamHandler)?.onListen(
        withArguments: nil, eventSink: eventSink)
    }
  }

  @Test func updatePlayingStateShouldNotResetRate() async throws {
    let realObjectFactory = FVPDefaultAVFactory()
    let testURL = try #require(URL(string: mp4TestURI))
    let player = FVPVideoPlayer(
      playerItem: playerItem(with: testURL, factory: realObjectFactory),
      avFactory: realObjectFactory,
      viewProvider: StubViewProvider())

    await withCheckedContinuation { continuation in
      let listener = StubEventListener(onInitialized: { continuation.resume() })
      player.eventListener = listener
    }

    var error: FlutterError?
    player.setPlaybackSpeed(2, error: &error)
    #expect(error == nil)
    player.playWithError(&error)
    #expect(error == nil)
    #expect(player.player.rate == 2)
  }

  @Test func playerShouldNotDropEverySecondFrame() throws {
    let textureRegistry = TestTextureRegistry()
    let stubDisplayLinkFactory = StubFVPDisplayLinkFactory()
    let mockVideoOutput = TestPixelBufferSource()
    let videoPlayerPlugin = try createInitializedPlugin(
      avFactory: StubFVPAVFactory(pixelBufferSource: mockVideoOutput),
      displayLinkFactory: stubDisplayLinkFactory,
      textureRegistry: textureRegistry)

    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: mp4TestURI, httpHeaders: [:]))
    let playerIdentifier = identifiers.playerId
    let player =
      videoPlayerPlugin.playersByIdentifier[playerIdentifier] as! FVPTextureBasedVideoPlayer

    func addFrame() {
      var bufferRef: CVPixelBuffer?
      CVPixelBufferCreate(nil, 1, 1, kCVPixelFormatType_32BGRA, nil, &bufferRef)
      mockVideoOutput.pixelBuffer = bufferRef
    }

    addFrame()
    stubDisplayLinkFactory.fireDisplayLink?()
    player.copyPixelBuffer()
    #expect(textureRegistry.textureFrameAvailableCount == 1)

    addFrame()
    stubDisplayLinkFactory.fireDisplayLink?()
    player.copyPixelBuffer()
    #expect(textureRegistry.textureFrameAvailableCount == 2)
  }

  @Test func videoOutputIsAddedWhenAVPlayerIsInitialized() async throws {
    let realObjectFactory = FVPDefaultAVFactory()
    let videoPlayerPlugin = try createInitializedPlugin(avFactory: realObjectFactory)

    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: mp4TestURI, httpHeaders: [:]))
    let player = try #require(videoPlayerPlugin.playersByIdentifier[identifiers.playerId])

    let listener = StubEventListener()
    await withCheckedContinuation { continuation in
      listener.onInitialized = { continuation.resume() }
      player.eventListener = listener
    }

    let item = try #require(player.player.currentItem)
    // Video output is added as soon as the status becomes ready to play.
    #expect(item.outputs.count == 1)
  }

  #if os(iOS)
    @Test func videoPlayerShouldNotOverwritePlayAndRecordNorDefaultToSpeaker() throws {
      let stubFactory = StubFVPAVFactory()
      let audioSession = TestAudioSession()
      stubFactory.audioSession = audioSession
      audioSession.category = .playAndRecord
      audioSession.categoryOptions = .defaultToSpeaker
      let videoPlayerPlugin = try createInitializedPlugin(avFactory: stubFactory)

      try videoPlayerPlugin.setMixWithOthers(true)
      #expect(audioSession.category == .playAndRecord)
      #expect(audioSession.categoryOptions.contains(.defaultToSpeaker))
      #expect(audioSession.categoryOptions.contains(.mixWithOthers))
    }

    @Test func setMixWithOthersShouldNoOpWhenNoChangesAreRequired() throws {
      let stubFactory = StubFVPAVFactory()
      let audioSession = TestAudioSession()
      stubFactory.audioSession = audioSession
      audioSession.category = .playAndRecord
      audioSession.categoryOptions = [.mixWithOthers, .defaultToSpeaker]
      let videoPlayerPlugin = try createInitializedPlugin(avFactory: stubFactory)

      try videoPlayerPlugin.setMixWithOthers(true)
      #expect(!audioSession.setCategoryCalled)
    }
  #endif

  // MARK: - Audio Track Tests

  // Tests getAudioTracks with a regular MP4 video file using real AVFoundation.
  // Regular MP4 files do not have media selection groups, so getAudioTracks returns an empty array.
  @Test func getAudioTracksWithRealMP4Video() async throws {
    let realObjectFactory = FVPDefaultAVFactory()
    let testURL = try #require(URL(string: mp4TestURI))
    let player = FVPVideoPlayer(
      playerItem: playerItem(with: testURL, factory: realObjectFactory),
      avFactory: realObjectFactory,
      viewProvider: StubViewProvider())

    await withCheckedContinuation { continuation in
      let listener = StubEventListener(onInitialized: { continuation.resume() })
      player.eventListener = listener
    }

    // Now test getAudioTracks
    var error: FlutterError?
    let result = try #require(player.getAudioTracks(&error))
    #expect(error == nil)

    // Regular MP4 files do not have media selection groups for audio.
    // getAudioTracks only returns selectable audio tracks from HLS streams.
    #expect(result.count == 0)

    player.disposeWithError(&error)
  }

  // Tests getAudioTracks with an HLS stream using real AVFoundation.
  // HLS streams use media selection groups for audio track selection.
  @Test func getAudioTracksWithRealHLSStream() async throws {
    let realObjectFactory = FVPDefaultAVFactory()
    let hlsURL = try #require(URL(string: hlsTestURI))

    let player = FVPVideoPlayer(
      playerItem: playerItem(with: hlsURL, factory: realObjectFactory),
      avFactory: realObjectFactory,
      viewProvider: StubViewProvider())

    await withCheckedContinuation { continuation in
      let listener = StubEventListener(onInitialized: { continuation.resume() })
      player.eventListener = listener
    }

    // Now test getAudioTracks
    var error: FlutterError?
    let result = try #require(player.getAudioTracks(&error))
    #expect(error == nil)

    // For HLS streams with multiple audio options, we get media selection tracks.
    // The bee.m3u8 stream may or may not have multiple audio tracks.
    // We verify the method returns valid data without crashing.
    for track in result {
      #expect(track.displayName != nil)
      #expect(track.index >= 0)
    }

    player.disposeWithError(&error)
  }

  // Tests that getAudioTracks returns valid data for audio-only files.
  // Regular audio files do not have media selection groups, so getAudioTracks returns an empty array.
  @Test func getAudioTracksWithRealAudioFile() async throws {
    // TODO(stuartmorgan): Add more use of protocols in FVPVideoPlayer so that this test
    // can use a fake item/asset instead of loading an actual remote asset.
    let realObjectFactory = FVPDefaultAVFactory()
    let audioURL = try #require(URL(string: mp3AudioTestURI))

    let player = FVPVideoPlayer(
      playerItem: playerItem(with: audioURL, factory: realObjectFactory),
      avFactory: realObjectFactory,
      viewProvider: StubViewProvider())

    await withCheckedContinuation { continuation in
      let listener = StubEventListener(onInitialized: { continuation.resume() })
      player.eventListener = listener
    }

    // Now test getAudioTracks
    var error: FlutterError?
    let result = try #require(player.getAudioTracks(&error))
    #expect(error == nil)

    // Regular audio files do not have media selection groups.
    // getAudioTracks only returns selectable audio tracks from HLS streams.
    #expect(result.count == 0)

    player.disposeWithError(&error)
  }

  // Tests that getAudioTracks works correctly through the plugin API with a real video.
  // Regular MP4 files do not have media selection groups, so getAudioTracks returns an empty array.
  @Test func getAudioTracksViaPluginWithRealVideo() async throws {
    // TODO(stuartmorgan): Add more use of protocols in FVPVideoPlayer so that this test
    // can use a fake item/asset instead of loading an actual remote asset.
    let realObjectFactory = FVPDefaultAVFactory()
    let testURL = try #require(URL(string: mp4TestURI))
    let player = FVPVideoPlayer(
      playerItem: playerItem(with: testURL, factory: realObjectFactory),
      avFactory: realObjectFactory,
      viewProvider: StubViewProvider())

    // Wait for player to become ready
    let listener = StubEventListener()
    await withCheckedContinuation { continuation in
      listener.onInitialized = { continuation.resume() }
      player.eventListener = listener
    }

    // Now test getAudioTracks
    var error: FlutterError?
    let result = try #require(player.getAudioTracks(&error))
    #expect(error == nil)

    // Regular MP4 files do not have media selection groups.
    // getAudioTracks only returns selectable audio tracks from HLS streams.
    #expect(result.count == 0)

    player.disposeWithError(&error)
  }

  @Test func loadTracksWithMediaTypeIsCalledOnNewerOS() {
    if #available(iOS 15.0, macOS 12.0, *) {
      let mockAsset = TestAsset(duration: CMTimeMake(value: 1, timescale: 1), tracks: [])
      let item = StubPlayerItem(asset: mockAsset)

      let stubAVFactory = StubFVPAVFactory(player: AVPlayer(), playerItem: item)
      let stubViewProvider = StubViewProvider()
      let _ = FVPVideoPlayer(
        playerItem: item, avFactory: stubAVFactory, viewProvider: stubViewProvider)
      #expect(mockAsset.loadedTracksAsynchronously)
    }
  }

  @Test func videoOutputIsConfiguredWithBT709ColorProperties() throws {
    let item = StubPlayerItem()
    let stubAVFactory = StubFVPAVFactory(player: AVPlayer(), playerItem: item)
    let stubViewProvider = StubViewProvider()
    let _ = FVPVideoPlayer(
      playerItem: item, avFactory: stubAVFactory, viewProvider: stubViewProvider)

    // BT.709 color properties are required so AVFoundation tone-maps HDR sources
    // into the Flutter texture. Without them HDR samples arrive unconverted and
    // render washed out. See flutter/flutter#91241.
    let settings = try #require(stubAVFactory.lastOutputSettings)
    let colorProperties = try #require(
      settings[AVVideoColorPropertiesKey] as? [String: Any])
    #expect(
      colorProperties[AVVideoColorPrimariesKey] as? String == AVVideoColorPrimaries_ITU_R_709_2)
    #expect(
      colorProperties[AVVideoTransferFunctionKey] as? String
        == AVVideoTransferFunction_ITU_R_709_2)
    #expect(
      colorProperties[AVVideoYCbCrMatrixKey] as? String == AVVideoYCbCrMatrix_ITU_R_709_2)
  }

  // MARK: - Video Track Tests

  // Integration test for getVideoTracks with a non-HLS MP4 video over a live network request.
  // Non-HLS MP4 files don't have adaptive bitrate variants, so we expect empty media selection
  // tracks.
  @Test func getVideoTracksWithRealMP4Video() async throws {
    // TODO(stuartmorgan): Add more use of protocols in FVPVideoPlayer so that this test
    // can use a fake item/asset instead of loading an actual remote asset.
    let realObjectFactory = FVPDefaultAVFactory()
    let testURL = try #require(URL(string: mp4TestURI))

    let player = FVPVideoPlayer(
      playerItem: playerItem(with: testURL, factory: realObjectFactory),
      avFactory: realObjectFactory,
      viewProvider: StubViewProvider())

    await withCheckedContinuation { continuation in
      let listener = StubEventListener(onInitialized: { continuation.resume() })
      player.eventListener = listener
    }

    // Now test getVideoTracks
    await withCheckedContinuation { continuation in
      player.getVideoTracks { result, error in
        #expect(error == nil)
        #expect(result != nil)
        // For regular MP4 files, media selection tracks should be nil (no HLS variants)
        // The method returns empty data for non-HLS content
        continuation.resume()
      }
    }

    var disposeError: FlutterError?
    player.disposeWithError(&disposeError)
  }

  // Integration test for getVideoTracks with an HLS stream over a live network request.
  // HLS streams use AVAssetVariant API (iOS 15+) to enumerate available quality variants.
  @Test func getVideoTracksWithRealHLSStream() async throws {
    // TODO(stuartmorgan): Add more use of protocols in FVPVideoPlayer so that this test
    // can use a fake item/asset instead of loading an actual remote asset.
    let realObjectFactory = FVPDefaultAVFactory()
    let hlsURL = try #require(URL(string: hlsTestURI))

    let player = FVPVideoPlayer(
      playerItem: playerItem(with: hlsURL, factory: realObjectFactory),
      avFactory: realObjectFactory,
      viewProvider: StubViewProvider())

    await withCheckedContinuation { continuation in
      let listener = StubEventListener(onInitialized: { continuation.resume() })
      player.eventListener = listener
    }

    // Now test getVideoTracks
    await withCheckedContinuation { continuation in
      player.getVideoTracks { result, error in
        #expect(error == nil)
        #expect(result != nil)

        // For HLS streams on iOS 15+, we may have media selection tracks (variants)
        if #available(iOS 15.0, macOS 12.0, *) {
          // The bee.m3u8 stream may or may not have multiple video variants.
          // We verify the method returns valid data without crashing.
          if let mediaSelectionTracks = result?.mediaSelectionTracks {
            // If media selection tracks exist, they should have valid structure
            for track in mediaSelectionTracks {
              #expect(track.variantIndex >= 0)
              // Bitrate should be positive if present
              if let bitrate = track.bitrate {
                #expect(bitrate.intValue > 0)
              }
            }
          }
        }
        continuation.resume()
      }
    }

    var disposeError: FlutterError?
    player.disposeWithError(&disposeError)
  }

  // Tests selectVideoTrack sets preferredPeakBitRate correctly.
  @Test func selectVideoTrackSetsBitrate() async throws {
    // TODO(stuartmorgan): Add more use of protocols in FVPVideoPlayer so that this test
    // can use a fake item/asset instead of loading an actual remote asset.
    let realObjectFactory = FVPDefaultAVFactory()
    let testURL = try #require(URL(string: mp4TestURI))

    let player = FVPVideoPlayer(
      playerItem: playerItem(with: testURL, factory: realObjectFactory),
      avFactory: realObjectFactory,
      viewProvider: StubViewProvider())

    await withCheckedContinuation { continuation in
      let listener = StubEventListener(onInitialized: { continuation.resume() })
      player.eventListener = listener
    }

    var error: FlutterError?
    // Set a specific bitrate
    player.selectVideoTrack(withBitrate: 5_000_000, error: &error)
    #expect(error == nil)
    #expect(player.player.currentItem?.preferredPeakBitRate == 5_000_000)

    player.disposeWithError(&error)
  }

  // Tests selectVideoTrack with 0 bitrate enables auto quality selection.
  @Test func selectVideoTrackAutoQuality() async throws {
    // TODO(stuartmorgan): Add more use of protocols in FVPVideoPlayer so that this test
    // can use a fake item/asset instead of loading an actual remote asset.
    let realObjectFactory = FVPDefaultAVFactory()
    let testURL = try #require(URL(string: mp4TestURI))

    let player = FVPVideoPlayer(
      playerItem: playerItem(with: testURL, factory: realObjectFactory),
      avFactory: realObjectFactory,
      viewProvider: StubViewProvider())

    await withCheckedContinuation { continuation in
      let listener = StubEventListener(onInitialized: { continuation.resume() })
      player.eventListener = listener
    }

    var error: FlutterError?
    // First set a specific bitrate
    player.selectVideoTrack(withBitrate: 5_000_000, error: &error)
    #expect(error == nil)
    #expect(player.player.currentItem?.preferredPeakBitRate == 5_000_000)

    // Then set to auto quality (0)
    player.selectVideoTrack(withBitrate: 0, error: &error)
    #expect(error == nil)
    #expect(player.player.currentItem?.preferredPeakBitRate == 0)

    player.disposeWithError(&error)
  }

  // Tests that getVideoTracks works correctly through the plugin API with a real video.
  @Test func getVideoTracksViaPluginWithRealVideo() async throws {
    // TODO(stuartmorgan): Add more use of protocols in FVPVideoPlayer so that this test
    // can use a fake item/asset instead of loading an actual remote asset.
    let realObjectFactory = FVPDefaultAVFactory()
    let videoPlayerPlugin = try createInitializedPlugin(avFactory: realObjectFactory)

    var error: FlutterError?
    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: mp4TestURI, httpHeaders: [:]))

    let player = videoPlayerPlugin.playersByIdentifier[identifiers.playerId] as! FVPVideoPlayer
    #expect(player != nil)

    // Wait for player item to become ready
    let item = try #require(player.player.currentItem)
    try await waitForPlayerItemStatus(item, state: .readyToPlay)

    // Now test getVideoTracks
    await withCheckedContinuation { continuation in
      player.getVideoTracks { result, error in
        #expect(error == nil)
        #expect(result != nil)
        continuation.resume()
      }
    }

    player.disposeWithError(&error)
  }

  // Tests selectVideoTrack via plugin API with HLS stream.
  @Test func selectVideoTrackViaPluginWithHLSStream() async throws {
    // TODO(stuartmorgan): Add more use of protocols in FVPVideoPlayer so that this test
    // can use a fake item/asset instead of loading an actual remote asset.
    let realObjectFactory = FVPDefaultAVFactory()
    let videoPlayerPlugin = try createInitializedPlugin(avFactory: realObjectFactory)

    var error: FlutterError?
    // Use HLS stream which supports adaptive bitrate
    let identifiers = try videoPlayerPlugin.createTexturePlayer(
      options: CreationOptions(uri: hlsTestURI, httpHeaders: [:]))

    let player = videoPlayerPlugin.playersByIdentifier[identifiers.playerId] as! FVPVideoPlayer
    #expect(player != nil)

    // Wait for player item to become ready
    let item = try #require(player.player.currentItem)
    try await waitForPlayerItemStatus(item, state: .readyToPlay)

    // Test setting a specific bitrate
    player.selectVideoTrack(withBitrate: 1_000_000, error: &error)
    #expect(error == nil)
    #expect(player.player.currentItem?.preferredPeakBitRate == 1_000_000)

    // Test setting auto quality
    player.selectVideoTrack(withBitrate: 0, error: &error)
    #expect(error == nil)
    #expect(player.player.currentItem?.preferredPeakBitRate == 0)

    player.disposeWithError(&error)
  }

  // MARK: - Helper Methods

  /// Creates a plugin with the given dependencies, and default stubs for any that aren't provided,
  /// then initializes it.
  private func createInitializedPlugin(
    avFactory: FVPAVFactory = StubFVPAVFactory(),
    displayLinkFactory: DisplayLinkFactory = StubFVPDisplayLinkFactory(),
    binaryMessenger: FlutterBinaryMessenger = StubBinaryMessenger(),
    textureRegistry: FlutterTextureRegistry = TestTextureRegistry(),
    viewProvider: FVPViewProvider = StubViewProvider(),
    assetProvider: FVPAssetProvider = StubAssetProvider()
  ) throws -> VideoPlayerPlugin {
    let plugin = VideoPlayerPlugin(
      avFactory: avFactory,
      displayLinkFactory: displayLinkFactory,
      binaryMessenger: binaryMessenger,
      textureRegistry: textureRegistry,
      viewProvider: viewProvider,
      assetProvider: assetProvider)
    try plugin.initialize()
    return plugin
  }

  private func playerItem(with url: URL, factory: FVPAVFactory) -> FVPAVPlayerItem {
    let asset = factory.urlAsset(with: url, options: nil)
    return factory.playerItem(with: asset)
  }

  private func waitForPlayerItemStatus(_ item: AVPlayerItem, state: AVPlayerItem.Status)
    async
    throws
  {
    try await withCheckedThrowingContinuation { continuation in
      // Check whether it already has the desired status.
      if item.status == state {
        continuation.resume()
        return
      }

      if item.status == .failed {
        continuation.resume(throwing: item.error ?? NSError(domain: "VideoPlayerTests", code: 1))
        return
      }

      // If not, wait for that status. The observation token must be retained until the callback
      // fires; otherwise KVO unregisters immediately and the continuation is never resumed.
      var observation: NSKeyValueObservation?
      observation = item.observe(\.status, options: [.initial, .new]) { observedItem, _ in
        if observedItem.status == state {
          observation?.invalidate()
          observation = nil
          continuation.resume()
        } else if observedItem.status == .failed {
          observation?.invalidate()
          observation = nil
          continuation.resume(
            throwing: observedItem.error ?? NSError(domain: "VideoPlayerTests", code: 1))
        }
      }
    }
  }

  // TODO(stuartmorgan): Remove this in favor of just `await player.seek(...)` once
  // Pigeon is generating Swift 6-friendly output. Currently using the automatic async
  // conversion generates warnings due to the lack of concurrency annotations
  // ("non-sendable type 'FlutterError?' returned by implicitly asynchronous call to
  // nonisolated function cannot cross actor boundary").
  private func asyncSeekTo(player: FVPVideoPlayer, time: Int) async {
    await withCheckedContinuation { continuation in
      player.seek(to: time) { error in
        #expect(error == nil)
        continuation.resume()
      }
    }
  }
}

/// These tests use only deferred fakes and empty local AVPlayers. Keep them independently
/// selectable: VideoPlayerTests also contains integration tests that fetch remote media.
@Suite(
  .enabled(
    if: {
      if #available(iOS 15.0, macOS 12.0, *) { return true }
      return false
    }(), "Deferred metadata tests require the asynchronous track API"))
@MainActor struct VideoPlayerMetadataTests {
  enum Stage: Int, CaseIterable {
    case assetKeys, videoTracks, preferredTransform
  }

  @Test(arguments: Stage.allCases, [false, true])
  func pendingMetadataDoesNotRetainPlayer(stage: Stage, dispose: Bool) async throws {
    let asset = DeferredAsset()
    let track = DeferredVideoTrack()
    defer {
      asset.finishPendingLoads()
      track.finishPendingLoad()
    }
    weak var weakPlayer: FVPVideoPlayer?
    weak var weakItem: StubPlayerItem?
    try autoreleasepool {
      let item = StubPlayerItem(asset: asset)
      let player = makePlayer(item: item)
      weakPlayer = player
      weakItem = item
      try advance(to: stage, asset: asset, track: track)
      if dispose {
        var error: FlutterError?
        player.disposeWithError(&error)
        #expect(error == nil)
      }
    }

    // The requested callback is still stored by the asset/track at this point.
    #expect(weakPlayer == nil)
    #expect(weakItem == nil)
    try completion(for: stage, asset: asset, track: track)()
    await drainMainQueue()
    expectNoFollowUpWork(after: stage, asset: asset, track: track)
  }

  @Test(arguments: Stage.allCases, [false, true])
  func disposedMetadataDoesNotAdmitWork(stage: Stage, background: Bool) async throws {
    let asset = DeferredAsset()
    let track = DeferredVideoTrack()
    defer {
      asset.finishPendingLoads()
      track.finishPendingLoad()
    }
    let item = StubPlayerItem(asset: asset)
    let player = makePlayer(item: item)
    try advance(to: stage, asset: asset, track: track)
    var disposalCount = 0
    player.onDisposed = { disposalCount += 1 }
    var error: FlutterError?
    player.disposeWithError(&error)
    #expect(error == nil)
    #expect(player.player.currentItem == nil)

    let callback = try completion(for: stage, asset: asset, track: track)
    if background {
      completeOnBackgroundQueue(callback)
    } else {
      callback()
    }
    await drainMainQueue()
    expectNoFollowUpWork(after: stage, asset: asset, track: track)
    #expect(item.videoCompositionUpdateCount == 0)
    player.disposeWithError(&error)
    #expect(error == nil)
    #expect(disposalCount == 1)
  }

  @Test(arguments: Stage.allCases)
  func queuedMetadataRechecksDisposal(stage: Stage) async throws {
    let asset = DeferredAsset()
    let track = DeferredVideoTrack()
    defer {
      asset.finishPendingLoads()
      track.finishPendingLoad()
    }
    let item = StubPlayerItem(asset: asset)
    let player = makePlayer(item: item)
    try advance(to: stage, asset: asset, track: track)

    // The native callback returns before disposal, but its main-queue work has not run yet.
    completeOnBackgroundQueue(try completion(for: stage, asset: asset, track: track))
    var error: FlutterError?
    player.disposeWithError(&error)
    #expect(error == nil)
    await drainMainQueue()

    expectNoFollowUpWork(after: stage, asset: asset, track: track)
    #expect(item.videoCompositionUpdateCount == 0)
  }

  @Test(arguments: Stage.allCases)
  func queuedMetadataDoesNotRetainPlayer(stage: Stage) async throws {
    let asset = DeferredAsset()
    let track = DeferredVideoTrack()
    defer {
      asset.finishPendingLoads()
      track.finishPendingLoad()
    }
    weak var weakPlayer: FVPVideoPlayer?
    weak var weakItem: StubPlayerItem?
    try autoreleasepool {
      let item = StubPlayerItem(asset: asset)
      let player = makePlayer(item: item)
      weakPlayer = player
      weakItem = item
      try advance(to: stage, asset: asset, track: track)
      completeOnBackgroundQueue(try completion(for: stage, asset: asset, track: track))
      var error: FlutterError?
      player.disposeWithError(&error)
      #expect(error == nil)
    }
    #expect(weakPlayer == nil)
    #expect(weakItem == nil)
    await drainMainQueue()
    expectNoFollowUpWork(after: stage, asset: asset, track: track)
  }

  @Test(arguments: [0, 90, 180, 270])
  func activeMetadataPreservesRotationOnMainThread(rotation: Int) async throws {
    let asset = DeferredAsset()
    let track = DeferredVideoTrack(rotation: rotation)
    let item = StubPlayerItem(asset: asset)
    let player = makePlayer(item: item)
    defer {
      var error: FlutterError?
      player.disposeWithError(&error)
    }

    for stage in Stage.allCases {
      completeOnBackgroundQueue(try completion(for: stage, asset: asset, track: track))
      await drainMainQueue()
    }
    #expect(asset.trackLoadCount == 1)
    #expect(asset.tracksRequestedOnMainThread)
    #expect(track.transformLoadCount == 1)
    #expect(track.transformRequestedOnMainThread)
    if rotation == 0 {
      #expect(item.videoComposition == nil)
      #expect(item.videoCompositionUpdateCount == 0)
    } else {
      let composition = try #require(item.videoComposition)
      #expect(item.videoCompositionUpdateCount == 1)
      #expect(item.videoCompositionUpdatedOnMainThread)
      #expect(
        composition.renderSize
          == (rotation == 180 ? CGSize(width: 800, height: 600) : CGSize(width: 600, height: 800)))
      #expect(composition.frameDuration == track.minFrameDuration)
      #expect(composition.sourceTrackIDForFrameTiming == track.trackID)
      let instruction = try #require(
        composition.instructions.first as? AVVideoCompositionInstruction)
      #expect(instruction.timeRange == CMTimeRange(start: .zero, duration: asset.duration))
      let layer = try #require(instruction.layerInstructions.first)
      var transform = CGAffineTransform.identity
      #expect(layer.getTransformRamp(for: .zero, start: &transform, end: nil, timeRange: nil))
      let expected: CGAffineTransform
      switch rotation {
      case 90: expected = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 600, ty: 0)
      case 180: expected = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 800, ty: 600)
      default: expected = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 800)
      }
      for (actual, wanted) in zip(
        [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty],
        [expected.a, expected.b, expected.c, expected.d, expected.tx, expected.ty])
      {
        #expect(abs(actual - wanted) < 0.00001)
      }
    }
  }

  @Test(arguments: Stage.allCases, [AVKeyValueStatus.failed, .cancelled])
  func unsuccessfulMetadataReleasesItem(stage: Stage, status: AVKeyValueStatus) throws {
    let asset = DeferredAsset()
    let track = DeferredVideoTrack()
    weak var weakItem: StubPlayerItem?
    let player = try autoreleasepool {
      let item = StubPlayerItem(asset: asset)
      weakItem = item
      let player = makePlayer(item: item)
      try advance(to: stage, asset: asset, track: track)
      return player
    }
    #expect(weakItem != nil)
    try autoreleasepool {
      switch stage {
      case .assetKeys:
        try asset.takeValuesCompletion(status: status)()
      case .videoTracks:
        let error = NSError(
          domain: NSURLErrorDomain,
          code: status == .failed ? NSURLErrorCannotDecodeContentData : NSURLErrorCancelled)
        try asset.takeTracksCompletion()(nil, error)
      case .preferredTransform:
        try track.takeTransformCompletion(status: status)()
      }
    }
    #expect(weakItem == nil)
    #expect(!player.disposed)
    var error: FlutterError?
    player.disposeWithError(&error)
    #expect(error == nil)
  }

  @Test func emptyMetadataTracksReleaseItem() throws {
    let asset = DeferredAsset()
    weak var weakItem: StubPlayerItem?
    let player = try autoreleasepool {
      let item = StubPlayerItem(asset: asset)
      weakItem = item
      let player = makePlayer(item: item)
      try asset.takeValuesCompletion()()
      return player
    }
    try autoreleasepool {
      try asset.takeTracksCompletion()([], nil)
    }
    #expect(weakItem == nil)
    var error: FlutterError?
    player.disposeWithError(&error)
    #expect(error == nil)
  }

  @Test(arguments: [0, 90])
  func completedMetadataReleasesInputs(rotation: Int) throws {
    let asset = DeferredAsset()
    weak var weakItem: StubPlayerItem?
    weak var weakTrack: DeferredVideoTrack?
    let player = try autoreleasepool {
      let item = StubPlayerItem(asset: asset)
      let track = DeferredVideoTrack(rotation: rotation)
      weakItem = item
      weakTrack = track
      let player = makePlayer(item: item)
      try advance(to: .preferredTransform, asset: asset, track: track)
      try track.takeTransformCompletion()()
      return player
    }
    #expect(weakItem == nil)
    #expect(weakTrack == nil)
    #expect(!player.disposed)
    var error: FlutterError?
    player.disposeWithError(&error)
    #expect(error == nil)
  }

  @Test func metadataDisposalRemovesObserversAndNotifiesOnce() throws {
    let asset = DeferredAsset()
    let listener = StubEventListener()
    weak var weakPlayer: FVPVideoPlayer?
    let avPlayer = try autoreleasepool {
      let player = makePlayer(item: StubPlayerItem(asset: asset))
      weakPlayer = player
      player.eventListener = listener
      var error: FlutterError?
      player.disposeWithError(&error)
      player.disposeWithError(&error)
      #expect(error == nil)
      try asset.takeValuesCompletion()()
      return player.player
    }
    #expect(weakPlayer == nil)
    #expect(listener.disposalCount == 1)
    #expect(avPlayer.currentItem == nil)
    #expect(asset.trackLoadCount == 0)
    // KVO must no longer try to notify the released FVPVideoPlayer.
    avPlayer.willChangeValue(forKey: "rate")
    avPlayer.didChangeValue(forKey: "rate")
  }

  private func makePlayer(item: StubPlayerItem) -> FVPVideoPlayer {
    let avPlayer = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
    return FVPVideoPlayer(
      playerItem: item,
      avFactory: StubFVPAVFactory(player: avPlayer, playerItem: item),
      viewProvider: StubViewProvider())
  }

  private func advance(to stage: Stage, asset: DeferredAsset, track: DeferredVideoTrack) throws {
    if stage.rawValue >= Stage.videoTracks.rawValue {
      try asset.takeValuesCompletion()()
    }
    if stage == .preferredTransform {
      try asset.takeTracksCompletion()([track.assetTrack], nil)
    }
  }

  private func completion(for stage: Stage, asset: DeferredAsset, track: DeferredVideoTrack) throws
    -> @Sendable () -> Void
  {
    switch stage {
    case .assetKeys:
      return try asset.takeValuesCompletion()
    case .videoTracks:
      let callback = try asset.takeTracksCompletion()
      return { callback([track.assetTrack], nil) }
    case .preferredTransform:
      return try track.takeTransformCompletion()
    }
  }

  private func expectNoFollowUpWork(
    after stage: Stage, asset: DeferredAsset, track: DeferredVideoTrack
  ) {
    #expect(asset.trackLoadCount == (stage == .assetKeys ? 0 : 1))
    #expect(track.transformLoadCount == (stage == .preferredTransform ? 1 : 0))
  }

  private func completeOnBackgroundQueue(_ callback: @escaping @Sendable () -> Void) {
    let finished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      #expect(!Thread.isMainThread)
      callback()
      finished.signal()
    }
    // Hold the main queue until the native callback has returned, so disposal can deterministically
    // win over queued work. This is a completion gate, not a timing delay.
    #expect(finished.wait(timeout: .now() + 5) == .success)
  }

  private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
}
