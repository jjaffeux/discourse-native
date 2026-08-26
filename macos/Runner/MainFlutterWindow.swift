import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The shell wants room for rail + sidebar + content + details panel, so the
    // 800x600 Flutter default opens narrower than the layout was designed for.
    self.setContentSize(NSSize(width: 1280, height: 860))
    self.contentMinSize = NSSize(width: 380, height: 480)
    self.center()

    // No title bar: the shell draws its own chrome and runs the full height of
    // the window. The traffic lights stay, floating over the strip the shell
    // reserves across the top (see ShellTitleBar).
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    // desktop_drop installs a transparent native view across this entire
    // content view. AppKit considers transparent views draggable window
    // background, which can make it consume a click instead of forwarding the
    // complete down/up pair to Flutter. Keep content dragging disabled; the
    // retained native title-bar strip remains draggable.
    disableContentViewWindowDragging(self)

    RegisterGeneratedPlugins(registry: flutterViewController)
    MacOSPushNotifications.shared.attach(
      to: flutterViewController.engine.binaryMessenger
    )
    attachWindowChannel(to: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func attachWindowChannel(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "org.discourse.native/window",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "toggleMaximized" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(
          FlutterError(
            code: "window_unavailable",
            message: "The app window is no longer available.",
            details: nil
          )
        )
        return
      }
      toggleWindowZoom(self)
      result(nil)
    }
    windowChannel = channel
  }
}

func disableContentViewWindowDragging(_ window: NSWindow) {
  window.isMovableByWindowBackground = false
}

func toggleWindowZoom(_ window: NSWindow) {
  window.zoom(nil)
}
