import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
if arguments.count < 2 || pid_t(arguments[1]) == nil {
  fputs("Usage: composer_window_state PID [--activate]\n", stderr)
  exit(1)
}
let process = pid_t(arguments[1])!
guard let app = NSRunningApplication(processIdentifier: process) else { exit(2) }
let workspace = NSWorkspace.shared
let activeBefore = app.isActive
let frontmostBefore = workspace.frontmostApplication?.processIdentifier
let activationRequested = arguments.contains("--activate")
let requestAccepted: Bool? = activationRequested
  ? app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) : nil

// AppKit caches these properties until the next main-run-loop turn. Activation
// is also asynchronous; keep a source alive while observing its bounded result.
let observationStart = Date()
let deadline = observationStart.addingTimeInterval(activationRequested ? 0.25 : 0.02)
let observationTimer = Timer(timeInterval: 0.01, repeats: true) { _ in }
RunLoop.main.add(observationTimer, forMode: .common)
repeat {
  RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
  if app.isActive && workspace.frontmostApplication?.processIdentifier == process { break }
} while Date() < deadline
observationTimer.invalidate()

let frontmost = workspace.frontmostApplication?.processIdentifier
let windows = CGWindowListCopyWindowInfo(
  [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] ?? []
let owned = windows.filter {
  ($0[kCGWindowOwnerPID as String] as? Int) == Int(process)
}
var result: [String: Any] = [
  "pid": Int(process),
  "active": app.isActive,
  "activeBefore": activeBefore,
  "hidden": app.isHidden,
  "onScreenWindows": owned.count,
  "bundlePath": app.bundleURL?.path ?? "",
  "activationRequested": activationRequested,
  "activationPolicy": app.activationPolicy.rawValue,
  "helperActivationPolicy": NSRunningApplication.current.activationPolicy.rawValue,
  "finishedLaunching": app.isFinishedLaunching,
  "ownsMenuBar": app.ownsMenuBar,
  "frontmostMatchesTarget": frontmost == process,
  "observationMs": Date().timeIntervalSince(observationStart) * 1000,
]
if let requestAccepted { result["activationRequestAccepted"] = requestAccepted }
if let frontmostBefore { result["frontmostPIDBefore"] = Int(frontmostBefore) }
if let frontmost { result["frontmostPID"] = Int(frontmost) }
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
