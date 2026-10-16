import CoreVideo
import UIKit
import WebRTC
import XCTest

@testable import discourse_voice

final class VoicePictureInPictureTests: XCTestCase {
  func testConversionRunsOffMainAndKeepsOneFrameThroughMainPresentation() throws {
    XCTAssertTrue(Thread.isMainThread)
    let frame = try nativeFrame()
    let converter = VoicePictureInPictureFrameConverter()
    let entered = expectation(description: "First conversion entered")
    let release = DispatchSemaphore(value: 0)
    let returned = DispatchSemaphore(value: 0)
    let conversions = LockedCount()
    let renderer = VoicePictureInPictureFrameRenderer { frame in
      XCTAssertFalse(Thread.isMainThread)
      if conversions.increment() == 1 { entered.fulfill() }
      XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
      let output = converter.presentationBuffer(frame)
      returned.signal()
      return output
    }
    defer { release.signal() }
    renderer.setLive(true)
    let sink = FrameSink()
    let first = render(frame, with: renderer, to: sink)
    wait(for: [entered], timeout: 5)
    for _ in 0..<100 { renderer.renderFrame(frame, isReady: sink.isReady, present: sink.present) }
    XCTAssertEqual(conversions.value, 1)
    release.signal()
    XCTAssertEqual(returned.wait(timeout: .now() + 5), .success)
    for _ in 0..<100 { renderer.renderFrame(frame, isReady: sink.isReady, present: sink.present) }
    XCTAssertEqual(conversions.value, 1)
    wait(for: [first], timeout: 5)
    XCTAssertEqual(sink.buffers.count, 1)
    release.signal()
    let second = render(frame, with: renderer, to: sink)
    wait(for: [second], timeout: 5)
    XCTAssertEqual(conversions.value, 2)
    XCTAssertEqual(sink.buffers.count, 2)
    XCTAssertEqual(sink.readinessChecks, 4)
  }

  func testResetBeforeAdmissionDiscardsWithoutConversionAndAllowsNewPrime() throws {
    let frame = try nativeFrame()
    let output = try pixelBuffer()
    let conversions = LockedCount()
    let renderer = VoicePictureInPictureFrameRenderer { _ in
      conversions.increment()
      return output
    }
    let sink = FrameSink()
    let stale = render(frame, with: renderer, to: sink)
    renderer.reset()
    wait(for: [stale], timeout: 5)
    XCTAssertEqual(conversions.value, 0)
    XCTAssertEqual(sink.readinessChecks, 0)
    let current = render(frame, with: renderer, to: sink)
    wait(for: [current], timeout: 5)
    XCTAssertEqual(conversions.value, 1)
    XCTAssertEqual(sink.buffers.count, 1)
  }

  func testRepeatedResetDuringConversionDoesNotReopenAdmissionOrPresentStaleFrame() throws {
    let frame = try nativeFrame()
    let output = try pixelBuffer()
    let entered = expectation(description: "Old generation conversion entered")
    let release = DispatchSemaphore(value: 0)
    let conversions = LockedCount()
    let renderer = VoicePictureInPictureFrameRenderer { _ in
      if conversions.increment() == 1 {
        entered.fulfill()
        XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
      }
      return output
    }
    defer { release.signal() }
    let sink = FrameSink()
    let stale = render(frame, with: renderer, to: sink)
    wait(for: [entered], timeout: 5)
    for _ in 0..<5 {
      renderer.reset()
      for _ in 0..<100 { renderer.renderFrame(frame, isReady: sink.isReady, present: sink.present) }
    }
    XCTAssertEqual(conversions.value, 1)
    release.signal()
    wait(for: [stale], timeout: 5)
    XCTAssertTrue(sink.buffers.isEmpty)
    let current = render(frame, with: renderer, to: sink)
    wait(for: [current], timeout: 5)
    XCTAssertEqual(conversions.value, 2)
    XCTAssertEqual(sink.buffers.count, 1)
    let checks = sink.readinessChecks
    for _ in 0..<100 { renderer.renderFrame(frame, isReady: sink.isReady, present: sink.present) }
    drainMainQueue()
    XCTAssertEqual(sink.readinessChecks, checks)
  }

  func testDisplayBackpressureRejectsBeforeAndAfterConversionAndRecovers() throws {
    let frame = try nativeFrame()
    let output = try pixelBuffer()
    let entered = expectation(description: "Conversion entered before backpressure")
    let release = DispatchSemaphore(value: 0)
    let conversions = LockedCount()
    let renderer = VoicePictureInPictureFrameRenderer { _ in
      if conversions.increment() == 1 {
        entered.fulfill()
        XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
      }
      return output
    }
    defer { release.signal() }
    renderer.setLive(true)
    let sink = FrameSink()
    sink.ready = false
    let rejected = render(frame, with: renderer, to: sink)
    wait(for: [rejected], timeout: 5)
    XCTAssertEqual(conversions.value, 0)
    sink.ready = true
    let blocked = render(frame, with: renderer, to: sink)
    wait(for: [entered], timeout: 5)
    sink.ready = false
    release.signal()
    wait(for: [blocked], timeout: 5)
    XCTAssertEqual(conversions.value, 1)
    XCTAssertTrue(sink.buffers.isEmpty)
    sink.ready = true
    let accepted = render(frame, with: renderer, to: sink)
    wait(for: [accepted], timeout: 5)
    XCTAssertEqual(conversions.value, 2)
    XCTAssertEqual(sink.buffers.count, 1)
  }

  func testConversionFailureReleasesAdmission() throws {
    let frame = try nativeFrame()
    let output = try pixelBuffer()
    let conversions = LockedCount()
    let renderer = VoicePictureInPictureFrameRenderer { _ in
      conversions.increment() == 1 ? nil : output
    }
    renderer.setLive(true)
    let sink = FrameSink()
    let failed = render(frame, with: renderer, to: sink)
    wait(for: [failed], timeout: 5)
    XCTAssertTrue(sink.buffers.isEmpty)
    let recovered = render(frame, with: renderer, to: sink)
    wait(for: [recovered], timeout: 5)
    XCTAssertEqual(conversions.value, 2)
    XCTAssertEqual(sink.buffers.count, 1)
  }

  func testInlinePrimingAndLiveModeKeepFirstAttemptSemantics() throws {
    let frame = try nativeFrame()
    let output = try pixelBuffer()
    let conversions = LockedCount()
    let renderer = VoicePictureInPictureFrameRenderer { _ in
      conversions.increment()
      return output
    }
    let sink = FrameSink()
    let prime = render(frame, with: renderer, to: sink)
    wait(for: [prime], timeout: 5)
    let primedChecks = sink.readinessChecks
    for _ in 0..<100 { renderer.renderFrame(frame, isReady: sink.isReady, present: sink.present) }
    drainMainQueue()
    XCTAssertEqual(sink.readinessChecks, primedChecks)
    renderer.setLive(true)
    let live = render(frame, with: renderer, to: sink)
    renderer.setLive(false)
    wait(for: [live], timeout: 5)
    XCTAssertEqual(conversions.value, 2)
    let stoppedChecks = sink.readinessChecks
    for _ in 0..<100 { renderer.renderFrame(frame, isReady: sink.isReady, present: sink.present) }
    drainMainQueue()
    XCTAssertEqual(sink.readinessChecks, stoppedChecks)
    renderer.reset()
    sink.ready = false
    let failedPrime = render(frame, with: renderer, to: sink)
    wait(for: [failedPrime], timeout: 5)
    sink.ready = true
    let failedPrimeChecks = sink.readinessChecks
    renderer.renderFrame(frame, isReady: sink.isReady, present: sink.present)
    drainMainQueue()
    XCTAssertEqual(sink.readinessChecks, failedPrimeChecks)
    XCTAssertEqual(conversions.value, 2)
    renderer.reset()
    let nextPrime = render(frame, with: renderer, to: sink)
    wait(for: [nextPrime], timeout: 5)
    XCTAssertEqual(conversions.value, 3)
    XCTAssertEqual(sink.buffers.count, 3)
  }

  func testViewCanDeallocateWhileConversionIsBlocked() throws {
    let frame = try nativeFrame()
    let output = try pixelBuffer()
    let entered = expectation(description: "Conversion entered with weak view callbacks")
    let finished = expectation(description: "Dropped frame completed after view teardown")
    let release = DispatchSemaphore(value: 0)
    let renderer = VoicePictureInPictureFrameRenderer { _ in
      entered.fulfill()
      XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
      return output
    }
    defer { release.signal() }
    var view: UIView? = UIView()
    weak var weakView = view
    var presentations = 0
    renderer.renderFrame(frame, isReady: { [weak view] in view != nil }, present: { [weak view] _ in
      if view != nil { presentations += 1 }
    }, completion: { finished.fulfill() })
    wait(for: [entered], timeout: 5)
    view = nil
    XCTAssertNil(weakView)
    release.signal()
    wait(for: [finished], timeout: 5)
    XCTAssertEqual(presentations, 0)
  }

  func testUprightNativeFramePreservesPixelBufferIdentity() throws {
    let source = try pixelBuffer()
    let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: source), rotation: ._0, timeStampNs: 0)
    let output = try convert(frame)
    XCTAssertTrue(output === source)
  }

  func testSoftwareRotationPreservesPixelCornersAndChangesDimensions() throws {
    let source = try quadrantBuffer(width: 4, height: 2)
    let cases: [(RTCVideoRotation, Int, Int, [[UInt8]])] = [
      (._90, 2, 4, [blue, red, white, green]),
      (._180, 4, 2, [white, blue, green, red]),
      (._270, 2, 4, [green, white, red, blue]),
    ]
    let converter = VoicePictureInPictureFrameConverter()
    for (rotation, width, height, corners) in cases {
      let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: source),
        rotation: rotation, timeStampNs: 0)
      let output = try convert(frame, using: converter)
      XCTAssertEqual(CVPixelBufferGetWidth(output), width)
      XCTAssertEqual(CVPixelBufferGetHeight(output), height)
      assertColor(output, x: 0, y: 0, equals: corners[0])
      assertColor(output, x: width - 1, y: 0, equals: corners[1])
      assertColor(output, x: 0, y: height - 1, equals: corners[2])
      assertColor(output, x: width - 1, y: height - 1, equals: corners[3])
    }
  }

  func testSoftwareCropUsesTopOriginBeforeRotation() throws {
    let source = try quadrantBuffer(width: 4, height: 4)
    let native = RTCCVPixelBuffer(pixelBuffer: source, adaptedWidth: 2, adaptedHeight: 2,
      cropWidth: 2, cropHeight: 2, cropX: 0, cropY: 0)
    let rotations: [RTCVideoRotation] = [._0, ._90]
    for rotation in rotations {
      let frame = RTCVideoFrame(buffer: native, rotation: rotation, timeStampNs: 0)
      let output = try convert(frame)
      XCTAssertEqual(CVPixelBufferGetWidth(output), 2)
      XCTAssertEqual(CVPixelBufferGetHeight(output), 2)
      for y in 0..<2 {
        for x in 0..<2 { assertColor(output, x: x, y: y, equals: red) }
      }
    }
  }

  func testI420CopiesOddSizedPlanesAndInterleavesPaddedChroma() throws {
    let planar = RTCMutableI420Buffer(width: 5, height: 3, strideY: 8, strideU: 4, strideV: 5)
    for y in 0..<3 {
      for x in 0..<5 { planar.mutableDataY[y * Int(planar.strideY) + x] = UInt8(16 + y * 10 + x) }
    }
    for y in 0..<2 {
      for x in 0..<3 {
        planar.mutableDataU[y * Int(planar.strideU) + x] = UInt8(70 + y * 10 + x)
        planar.mutableDataV[y * Int(planar.strideV) + x] = UInt8(140 + y * 10 + x)
      }
    }
    let output = try convert(RTCVideoFrame(buffer: planar, rotation: ._0, timeStampNs: 0))
    XCTAssertEqual(CVPixelBufferGetWidth(output), 5)
    XCTAssertEqual(CVPixelBufferGetHeight(output), 3)
    XCTAssertEqual(CVPixelBufferGetPixelFormatType(output), kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    CVPixelBufferLockBaseAddress(output, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(output, .readOnly) }
    let luma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(output, 0))
      .assumingMemoryBound(to: UInt8.self)
    let chroma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(output, 1))
      .assumingMemoryBound(to: UInt8.self)
    for y in 0..<3 {
      for x in 0..<5 {
        XCTAssertEqual(luma[y * CVPixelBufferGetBytesPerRowOfPlane(output, 0) + x], UInt8(16 + y * 10 + x))
      }
    }
    for y in 0..<2 {
      for x in 0..<3 {
        let offset = y * CVPixelBufferGetBytesPerRowOfPlane(output, 1) + x * 2
        XCTAssertEqual(chroma[offset], UInt8(70 + y * 10 + x))
        XCTAssertEqual(chroma[offset + 1], UInt8(140 + y * 10 + x))
      }
    }
  }

  private func render(_ frame: RTCVideoFrame, with renderer: VoicePictureInPictureFrameRenderer,
    to sink: FrameSink) -> XCTestExpectation {
    let finished = expectation(description: "Admitted frame finished")
    renderer.renderFrame(frame, isReady: sink.isReady, present: sink.present, completion: {
      XCTAssertTrue(Thread.isMainThread)
      finished.fulfill()
    })
    return finished
  }

  private func drainMainQueue() {
    let drained = expectation(description: "Main admission queue drained")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 5)
  }

  private func convert(_ frame: RTCVideoFrame,
    using converter: VoicePictureInPictureFrameConverter = VoicePictureInPictureFrameConverter()) throws -> CVPixelBuffer {
    let renderer = VoicePictureInPictureFrameRenderer { frame in
      XCTAssertFalse(Thread.isMainThread)
      return converter.presentationBuffer(frame)
    }
    let sink = FrameSink()
    let finished = render(frame, with: renderer, to: sink)
    wait(for: [finished], timeout: 5)
    return try XCTUnwrap(sink.buffers.first)
  }

  private func nativeFrame() throws -> RTCVideoFrame {
    RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: try pixelBuffer()), rotation: ._0, timeStampNs: 0)
  }

  private func pixelBuffer(width: Int = 4, height: Int = 2) throws -> CVPixelBuffer {
    var output: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
      [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &output), kCVReturnSuccess)
    return try XCTUnwrap(output)
  }

  private var red: [UInt8] { [0, 0, 255, 255] }
  private var green: [UInt8] { [0, 255, 0, 255] }
  private var blue: [UInt8] { [255, 0, 0, 255] }
  private var white: [UInt8] { [255, 255, 255, 255] }

  private func quadrantBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    let output = try pixelBuffer(width: width, height: height)
    CVPixelBufferLockBaseAddress(output, [])
    defer { CVPixelBufferUnlockBaseAddress(output, []) }
    let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(output)).assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
      for x in 0..<width {
        let color = y < height / 2 ? (x < width / 2 ? red : green) : (x < width / 2 ? blue : white)
        let offset = y * CVPixelBufferGetBytesPerRow(output) + x * 4
        for channel in 0..<4 { base[offset + channel] = color[channel] }
      }
    }
    return output
  }

  private func assertColor(_ buffer: CVPixelBuffer, x: Int, y: Int, equals color: [UInt8],
    file: StaticString = #filePath, line: UInt = #line) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
      XCTFail("Expected a packed BGRA buffer", file: file, line: line)
      return
    }
    let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
    for channel in 0..<4 {
      XCTAssertEqual(Double(base[offset + channel]), Double(color[channel]), accuracy: 2, file: file, line: line)
    }
  }
}

private final class FrameSink {
  var ready = true
  var readinessChecks = 0
  var buffers: [CVPixelBuffer] = []

  func isReady() -> Bool {
    XCTAssertTrue(Thread.isMainThread)
    readinessChecks += 1
    return ready
  }

  func present(_ buffer: CVPixelBuffer) {
    XCTAssertTrue(Thread.isMainThread)
    buffers.append(buffer)
  }
}

private final class LockedCount {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  @discardableResult func increment() -> Int {
    lock.lock()
    defer { lock.unlock() }
    count += 1
    return count
  }
}
