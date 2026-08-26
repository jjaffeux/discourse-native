import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowChannel: FlutterMethodChannel?
  private var launchScreen: LaunchScreenView?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = LaunchScreenView.backgroundStart
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
    self.backgroundColor = LaunchScreenView.backgroundStart
    // desktop_drop installs a transparent native view across this entire
    // content view. AppKit considers transparent views draggable window
    // background, which can make it consume a click instead of forwarding the
    // complete down/up pair to Flutter. Keep content dragging disabled; the
    // retained native title-bar strip remains draggable.
    disableContentViewWindowDragging(self)

    guard let launchLogo = NSImage(named: NSImage.Name("LaunchLogo")) else {
      fatalError("LaunchLogo is missing from the macOS asset catalog")
    }
    let launchScreen = LaunchScreenView(logo: launchLogo)
    launchScreen.frame = flutterViewController.view.bounds
    launchScreen.autoresizingMask = [.width, .height]
    flutterViewController.view.addSubview(launchScreen)
    self.launchScreen = launchScreen

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
      switch call.method {
      case "toggleMaximized":
        toggleWindowZoom(self)
        result(nil)
      case "dismissLaunchScreen":
        self.launchScreen?.removeFromSuperview()
        self.launchScreen = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    windowChannel = channel
  }
}

final class LaunchScreenView: NSView {
  // Mirrors the diagonal app-icon background while leaving the centered mark
  // free of the icon's rounded plate and border.
  static let backgroundStart = NSColor(
    srgbRed: 80 / 255,
    green: 50 / 255,
    blue: 129 / 255,
    alpha: 1
  )
  static let backgroundEnd = NSColor(
    srgbRed: 57 / 255,
    green: 36 / 255,
    blue: 92 / 255,
    alpha: 1
  )

  let logoView: NSImageView
  let gradientLayer = CAGradientLayer()

  init(logo: NSImage) {
    logoView = NSImageView(image: logo)
    super.init(frame: .zero)

    gradientLayer.colors = [
      Self.backgroundStart.cgColor,
      Self.backgroundEnd.cgColor,
    ]
    gradientLayer.startPoint = CGPoint(x: 0, y: 1)
    gradientLayer.endPoint = CGPoint(x: 1, y: 0)
    wantsLayer = true
    layer = gradientLayer

    logoView.imageScaling = .scaleProportionallyUpOrDown
    logoView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(logoView)
    NSLayoutConstraint.activate([
      logoView.centerXAnchor.constraint(equalTo: centerXAnchor),
      logoView.centerYAnchor.constraint(equalTo: centerYAnchor),
      logoView.widthAnchor.constraint(equalToConstant: 192),
      logoView.heightAnchor.constraint(equalTo: logoView.widthAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("LaunchScreenView must be created programmatically")
  }

  override func layout() {
    super.layout()
    gradientLayer.frame = bounds
  }
}

func disableContentViewWindowDragging(_ window: NSWindow) {
  window.isMovableByWindowBackground = false
}

func toggleWindowZoom(_ window: NSWindow) {
  window.zoom(nil)
}
