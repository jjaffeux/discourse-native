import CoreGraphics
import ImageIO
import XCTest
@testable import DiscourseNativeSupport

final class PdfThumbnailGeneratorTests: XCTestCase {
  func testDrawsOnlyTheFirstPageAndBoundsTheImage() throws {
    let data = try makeDocument(width: 600, height: 900)
    let thumbnail = try XCTUnwrap(PdfThumbnailGenerator.render(data))
    let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(image.width, 171)
    XCTAssertEqual(image.height, 256)
    let pixels = try XCTUnwrap(image.dataProvider?.data)
    let bytes = try XCTUnwrap(CFDataGetBytePtr(pixels))
    let center = image.bytesPerRow * (image.height / 2) + (image.width / 2) * 4
    XCTAssertGreaterThan(bytes[center], 240) // First page is red.
    XCTAssertLessThan(bytes[center + 2], 15) // Second page is blue.
  }

  func testPreservesLandscapeAndRejectsInvalidDocuments() throws {
    let thumbnail = try XCTUnwrap(PdfThumbnailGenerator.render(makeDocument(width: 900, height: 600)))
    let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(image.width, 256)
    XCTAssertEqual(image.height, 171)
    XCTAssertNil(PdfThumbnailGenerator.render(Data("not a PDF".utf8)))
    XCTAssertNil(PdfThumbnailGenerator.render(Data()))
    XCTAssertNil(PdfThumbnailGenerator.render(Data(count: PdfThumbnailGenerator.maximumDocumentBytes + 1)))
  }

  @MainActor
  func testDownloadRendersAndCancellationCompletesExactlyOnce() async throws {
    PdfProtocol.body = try makeDocument(width: 600, height: 900)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PdfProtocol.self]
    let generator = PdfThumbnailGenerator(configuration: configuration)
    let data: Data? = await withCheckedContinuation { continuation in
      generator.start(url: URL(string: "https://example.com/document.pdf")!) {
        continuation.resume(returning: $0)
      }
    }
    XCTAssertNotNil(data)
    let cancelled = PdfThumbnailGenerator(configuration: configuration)
    var callbacks = 0
    cancelled.start(url: URL(string: "https://example.com/document.pdf")!) { data in
      callbacks += 1
      XCTAssertNil(data)
    }
    cancelled.cancel()
    cancelled.cancel()
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(callbacks, 1)
  }

  @MainActor
  func testOversizedDownloadsKeepTheFallback() async throws {
    PdfProtocol.body = Data(count: PdfThumbnailGenerator.maximumDocumentBytes + 1)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PdfProtocol.self]
    let generator = PdfThumbnailGenerator(configuration: configuration)
    let data: Data? = await withCheckedContinuation { continuation in
      generator.start(url: URL(string: "https://example.com/document.pdf")!) {
        continuation.resume(returning: $0)
      }
    }
    XCTAssertNil(data)
  }

  private func makeDocument(width: CGFloat, height: CGFloat) throws -> Data {
    let bytes = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: bytes))
    var box = CGRect(x: 0, y: 0, width: width, height: height)
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    for color in [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1)] {
      context.beginPDFPage(nil)
      context.setFillColor(color)
      context.fill(box)
      context.endPDFPage()
    }
    context.closePDF()
    return bytes as Data
  }
}

private final class PdfProtocol: URLProtocol {
  static var body = Data()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/pdf", "Content-Length": "\(Self.body.count)"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
