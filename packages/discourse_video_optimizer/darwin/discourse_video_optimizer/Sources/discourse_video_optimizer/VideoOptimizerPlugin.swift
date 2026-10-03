#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import Foundation

public final class VideoOptimizerPlugin: NSObject, FlutterPlugin {
  @MainActor private var jobs: [Int: VideoOptimizationJob] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(macOS)
    let messenger = registrar.messenger
    #else
    let messenger = registrar.messenger()
    #endif
    let channel = FlutterMethodChannel(
      name: "org.discourse.native/video_optimizer", binaryMessenger: messenger
    )
    registrar.addMethodCallDelegate(VideoOptimizerPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // Flutter invokes platform-channel delegates on the platform's main thread.
    MainActor.assumeIsolated { handleOnMain(call, result: result) }
  }

  @MainActor private func handleOnMain(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "isAvailable" { result(true); return }
    guard let arguments = call.arguments as? [String: Any],
      let id = arguments["id"] as? Int
    else { result(false); return }
    switch call.method {
    case "optimize":
      guard jobs.isEmpty,
        let input = arguments["inputPath"] as? String,
        let output = arguments["outputPath"] as? String,
        input != output, input.hasPrefix("/"), output.hasPrefix("/"),
        !FileManager.default.fileExists(atPath: output)
      else { result(false); return }
      let job = VideoOptimizationJob()
      jobs[id] = job
      job.start(input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output)) {
        [weak self] success in
        self?.jobs.removeValue(forKey: id)
        result(success)
      }
    case "cancel":
      guard let job = jobs[id] else { result(nil); return }
      job.cancel { result(nil) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    MainActor.assumeIsolated {
      for job in Array(jobs.values) { job.cancel() }
    }
  }
}
