import ImageIO
import XCTest
@testable import DiscourseNativeSupport

@MainActor
final class VideoThumbnailGeneratorTests: XCTestCase {
  func testExtractsDecodableJPEGWithVideoRotation() async throws {
    for (name, width, height) in [("thumbnail", 96, 64), ("thumbnail-rotated", 64, 96)] {
      let generator = VideoThumbnailGenerator()
      let url = try XCTUnwrap(Bundle.module.url(
        forResource: name, withExtension: "mp4", subdirectory: "Fixtures"
      ))
      let data: Data? = await withCheckedContinuation { continuation in
        generator.start(url: url) { continuation.resume(returning: $0) }
      }
      let bytes = try XCTUnwrap(data)
      let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      XCTAssertEqual(image.width, width)
      XCTAssertEqual(image.height, height)
      XCTAssertLessThan(bytes.count, 2 * 1024 * 1024)
    }
  }

  func testUnavailableVideoCompletesWithoutAnImage() async {
    let generator = VideoThumbnailGenerator()
    let data: Data? = await withCheckedContinuation { continuation in
      generator.start(url: URL(fileURLWithPath: "/missing-video-thumbnail-fixture.mp4")) {
        continuation.resume(returning: $0)
      }
    }
    XCTAssertNil(data)
  }

  func testCancellationCompletesOnceAndDiscardsLateFrames() async throws {
    let generator = VideoThumbnailGenerator()
    let url = try XCTUnwrap(Bundle.module.url(
      forResource: "thumbnail", withExtension: "mp4", subdirectory: "Fixtures"
    ))
    var callbacks = 0
    generator.start(url: url) { data in
      callbacks += 1
      XCTAssertNil(data)
    }
    generator.cancel()
    generator.cancel()
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(callbacks, 1)
  }
}
