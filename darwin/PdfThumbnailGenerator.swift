import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downloads a bounded PDF into memory and draws only its first page.
/// Requests are anonymous: Dart resolves secure uploads to signed URLs first.
final class PdfThumbnailGenerator: NSObject, URLSessionDataDelegate {
  static let maximumDocumentBytes = 20 * 1024 * 1024
  private static let renderQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 2
    queue.qualityOfService = .utility
    return queue
  }()
  private let configuration: URLSessionConfiguration
  private var session: URLSession?
  private var document = Data()
  private var timeout: DispatchWorkItem?
  private var completion: ((Data?) -> Void)?
  private var renderOperation: BlockOperation?
  private var redirects = 0

  init(configuration: URLSessionConfiguration = .ephemeral) {
    self.configuration = configuration
  }

  func start(url: URL, completion: @escaping (Data?) -> Void) {
    precondition(Thread.isMainThread)
    precondition(self.completion == nil)
    self.completion = completion
    guard Self.safe(url) else { finish(nil); return }
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 15
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    self.session = session
    let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
    self.timeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
    var request = URLRequest(url: url)
    request.setValue("application/pdf", forHTTPHeaderField: "Accept")
    session.dataTask(with: request).resume()
  }

  func cancel() {
    precondition(Thread.isMainThread)
    finish(nil)
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard completion != nil, let response = response as? HTTPURLResponse,
      response.statusCode == 200,
      response.expectedContentLength <= Self.maximumDocumentBytes
    else { completionHandler(.cancel); finish(nil); return }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard completion != nil else { return }
    guard document.count + data.count <= Self.maximumDocumentBytes else {
      finish(nil); return
    }
    document.append(data)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    redirects += 1
    guard completion != nil, redirects <= 5, let url = request.url, Self.safe(url),
      !(response.url?.scheme == "https" && url.scheme == "http")
    else { completionHandler(nil); finish(nil); return }
    completionHandler(request)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard completion != nil else { return }
    guard error == nil else { finish(nil); return }
    let data = document
    document = Data()
    let operation = BlockOperation()
    operation.addExecutionBlock { [weak self, weak operation] in
      guard let operation, !operation.isCancelled else { return }
      let thumbnail = Self.render(data)
      guard !operation.isCancelled else { return }
      DispatchQueue.main.async { [weak self] in self?.finish(thumbnail) }
    }
    renderOperation = operation
    Self.renderQueue.addOperation(operation)
  }

  private func finish(_ data: Data?) {
    guard let completion else { return }
    self.completion = nil
    timeout?.cancel()
    timeout = nil
    session?.invalidateAndCancel()
    session = nil
    renderOperation?.cancel()
    renderOperation = nil
    document = Data()
    completion(data)
  }

  private static func safe(_ url: URL) -> Bool {
    ["http", "https"].contains(url.scheme?.lowercased() ?? "") &&
      !(url.host ?? "").isEmpty && url.user == nil && url.password == nil
  }

  static func render(_ data: Data) -> Data? {
    guard !data.isEmpty, data.count <= maximumDocumentBytes,
      let provider = CGDataProvider(data: data as CFData),
      let document = CGPDFDocument(provider), !document.isEncrypted,
      let page = document.page(at: 1)
    else { return nil }
    let box = page.getBoxRect(.cropBox)
    guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else {
      return nil
    }
    let rotated = abs(page.rotationAngle) % 180 == 90
    let width = rotated ? box.height : box.width
    let height = rotated ? box.width : box.height
    let scale = min(1, 256 / max(width, height))
    let pixelWidth = max(1, Int(ceil(width * scale)))
    let pixelHeight = max(1, Int(ceil(height * scale)))
    guard let context = CGContext(
      data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    let rect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(rect)
    context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
    context.drawPDFPage(page)
    guard let image = context.makeImage() else { return nil }
    let bytes = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination), bytes.length <= 2 * 1024 * 1024 else { return nil }
    return bytes as Data
  }
}
