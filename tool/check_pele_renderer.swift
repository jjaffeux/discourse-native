import AppKit
import WebKit

// Runs the generated fixture in the same browser engine as the macOS app.
let path = CommandLine.arguments.dropFirst().first ?? "/tmp/pele-check/index.html"
let url = URL(fileURLWithPath: path)
guard FileManager.default.fileExists(atPath: path) else {
  fputs("Generate the fixture with dart run tool/check_pele_renderer.dart first.\n", stderr)
  exit(1)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                      styleMask: .borderless, backing: .buffered, defer: false)
let webView = WKWebView(frame: window.contentView!.bounds)
window.contentView = webView
window.orderFrontRegardless()
webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
let started = Date()
var checking = false
let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
  if Date().timeIntervalSince(started) > 120 {
    fputs("Pele WebKit verification timed out.\n", stderr)
    exit(1)
  }
  if checking { return }
  checking = true
  webView.evaluateJavaScript("window.done ? JSON.stringify(window.results) : null") { value, error in
    checking = false
    guard let json = value as? String, let data = json.data(using: .utf8),
          let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
    let report = url.deletingLastPathComponent().appendingPathComponent("results-webkit.json")
    try? data.write(to: report)
    let failures = results.filter { ($0["pass"] as? Bool) != true }
    print("\(results.count) WebKit cases, \(failures.count) failures. Report: \(report.path)")
    for failure in failures { print(failure) }
    exit(failures.isEmpty ? 0 : 1)
  }
}
app.run()
