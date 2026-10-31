#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import Foundation

final class VideoThumbnailChannel {
  private var channel: FlutterMethodChannel?
  private var requests: [Int: VideoThumbnailGenerator] = [:]

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "org.discourse.native/video_thumbnails", binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      guard let arguments = call.arguments as? [String: Any],
        let id = arguments["id"] as? Int
      else { result(nil); return }
      switch call.method {
      case "generate":
        guard let source = arguments["url"] as? String,
          let url = URL(string: source),
          Self.isPreviewSource(url)
        else { result(nil); return }
        self.requests[id]?.cancel()
        let generator = VideoThumbnailGenerator()
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

  private static func isPreviewSource(_ url: URL) -> Bool {
    if url.isFileURL {
      guard (url.host ?? "").isEmpty, url.query == nil, url.fragment == nil else {
        return false
      }
      let source = url.resolvingSymlinksInPath().standardizedFileURL
      let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        .resolvingSymlinksInPath().standardizedFileURL
      let prefix = temporary.path.hasSuffix("/") ? temporary.path : temporary.path + "/"
      return source.path.hasPrefix(prefix) &&
        source.deletingLastPathComponent().lastPathComponent.hasPrefix("composer-preview-")
    }
    return ["http", "https"].contains(url.scheme?.lowercased() ?? "") &&
      !(url.host ?? "").isEmpty && url.user == nil && url.password == nil
  }

  deinit {
    for generator in requests.values { generator.cancel() }
  }
}
