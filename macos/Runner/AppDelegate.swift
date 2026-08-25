import Cocoa
import FlutterMacOS

protocol ApplicationActivating {
  func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: ApplicationActivating {}

protocol MainWindowPresenting {
  func makeKeyAndOrderFront(_ sender: Any?)
}

extension NSWindow: MainWindowPresenting {}

func activateMainWindow(
  application: ApplicationActivating,
  window: MainWindowPresenting?
) {
  // A user-launched app must not leave its Flutter surface inactive: AppKit
  // consumes the first click to activate such a window and withholds hover.
  application.activate(ignoringOtherApps: true)
  window?.makeKeyAndOrderFront(nil)
}

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    activateMainWindow(
      application: NSApplication.shared,
      window: mainFlutterWindow
    )
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
