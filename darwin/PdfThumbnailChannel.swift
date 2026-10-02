#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import Foundation

final class PdfThumbnailChannel {
  private var channel: FlutterMethodChannel?
  private var requests: [Int: PdfThumbnailGenerator] = [:]

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "org.discourse.native/pdf_thumbnails", binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      guard let arguments = call.arguments as? [String: Any], let id = arguments["id"] as? Int
      else { result(nil); return }
      switch call.method {
      case "generate":
        guard let source = arguments["url"] as? String, let url = URL(string: source)
        else { result(nil); return }
        self.requests[id]?.cancel()
        let generator = PdfThumbnailGenerator()
        self.requests[id] = generator
        generator.start(url: url) { [weak self] data in
          self?.requests.removeValue(forKey: id)
          result(data.map { FlutterStandardTypedData(bytes: $0) })
        }
      case "cancel":
        self.requests[id]?.cancel()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  deinit {
    for generator in requests.values { generator.cancel() }
  }
}
