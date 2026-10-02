import Cocoa
import FlutterMacOS
import WebKit
import webview_all_wkwebview

class MainFlutterWindow: NSWindow {
  private var flutterController: FlutterViewController?
  private let videoThumbnails = VideoThumbnailChannel()
  private let pdfThumbnails = PdfThumbnailChannel()
  private var windowChannel: FlutterMethodChannel?
  private var windowFrameObservers: [NSObjectProtocol] = []
  private var liveResize = false
  private var youtubeScrollChannel: FlutterMethodChannel?
  private var pasteboardChannel: FlutterMethodChannel?
  private var webViewScrollRouting = WebViewScrollRouting()
  private var launchScreen: LaunchScreenView?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    flutterController = flutterViewController
    self.contentViewController = flutterViewController
    let backdrop = NSVisualEffectView(frame: flutterViewController.view.bounds)
    backdrop.autoresizingMask = [.width, .height]
    backdrop.material = .underWindowBackground
    backdrop.blendingMode = .behindWindow
    backdrop.state = .active
    flutterViewController.view.addSubview(backdrop, positioned: .below, relativeTo: nil)
    self.isOpaque = false

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
    self.backgroundColor = .clear
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
    videoThumbnails.attach(to: flutterViewController.engine.binaryMessenger)
    pdfThumbnails.attach(to: flutterViewController.engine.binaryMessenger)
    MacOSPushNotifications.shared.attach(
      to: flutterViewController.engine.binaryMessenger
    )
    attachWindowChannel(to: flutterViewController.engine.binaryMessenger)
    attachPasteboardChannel(to: flutterViewController.engine.binaryMessenger)
    observeWindowFrame(NSWindow.willStartLiveResizeNotification) { window in
      window.liveResize = true
      window.sendWindowFrame()
    }
    observeWindowFrame(NSWindow.didResizeNotification) { window in
      window.sendWindowFrame()
    }
    observeWindowFrame(NSWindow.didMoveNotification) { window in
      // AppKit may report the move of a dragged left edge before its new size.
      if !window.liveResize { window.sendWindowFrame() }
    }
    observeWindowFrame(NSWindow.didEndLiveResizeNotification) { window in
      window.liveResize = false
      window.sendWindowFrame()
    }
    youtubeScrollChannel = FlutterMethodChannel(
      name: "org.discourse.native/youtube_scroll",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }

  deinit {
    for observer in windowFrameObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  override func sendEvent(_ event: NSEvent) {
    if forwardYoutubeScroll(event) { return }
    if event.type == .scrollWheel,
      !event.phase.isEmpty || !event.momentumPhase.isEmpty,
      let flutterController = flutterController {
      // A gesture that began in Flutter must also finish there, even when a
      // native web view moves beneath the pointer before its end event.
      flutterController.scrollWheel(with: event)
      return
    }
    super.sendEvent(event)
  }

  /// WKWebView owns pointer events inside a platform view, so Flutter's parent
  /// Scrollable never sees a wheel or trackpad gesture over an active player.
  /// Forward just those deltas to the matching Flutter player; clicks remain
  /// native so YouTube's controls keep their normal behavior.
  private func forwardYoutubeScroll(_ event: NSEvent) -> Bool {
    guard event.type == .scrollWheel,
      let contentView,
      let flutterView = flutterController?.view,
      let channel = youtubeScrollChannel
    else {
      return false
    }

    // desktop_drop intentionally installs a transparent full-window native
    // view, so AppKit's ordinary hitTest stops there. Walk the native subtree
    // and use WKWebView.visibleRect to find a player below that drop target.
    guard webViewScrollRouting.shouldForward(
      phase: event.phase,
      momentumPhase: event.momentumPhase,
      overWebView: containsVisibleWebView(at: event.locationInWindow, in: contentView)
    ) else {
      return false
    }

    let pixelsPerLine: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 40
    let deltaY: CGFloat
    if event.modifierFlags.contains(.shift) {
      deltaY = -event.scrollingDeltaX * pixelsPerLine
    } else {
      deltaY = -event.scrollingDeltaY * pixelsPerLine
    }

    let flutterPoint = flutterView.convert(event.locationInWindow, from: nil)
    channel.invokeMethod(
      "scroll",
      arguments: [
        "x": flutterPoint.x,
        "y": flutterView.isFlipped
          ? flutterPoint.y
          : flutterView.bounds.height - flutterPoint.y,
        "deltaY": deltaY,
      ]
    )
    return true
  }

  private func containsVisibleWebView(at windowPoint: NSPoint, in view: NSView) -> Bool {
    if let webView = view as? WKWebView {
      let localPoint = webView.convert(windowPoint, from: nil)
      return !webView.isHiddenOrHasHiddenAncestor
        && webView.alphaValue > 0
        && webView.visibleRect.contains(localPoint)
    }
    for subview in view.subviews.reversed() {
      if containsVisibleWebView(at: windowPoint, in: subview) {
        return true
      }
    }
    return false
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
      case "getWindowFrame":
        result(self.windowFrameArguments())
      case "getWindowCornerRadius":
        if self.styleMask.contains(.fullScreen) {
          result(0.0)
        } else if #available(macOS 26.0, *) {
          // This window has a hidden title bar and no AppKit toolbar.
          result(16.0)
        } else {
          result(10.0)
        }
      case "enableYoutubeFullscreen":
        guard let identifier = call.arguments as? Int64,
          let registry = self.flutterController,
          let webView = WebviewAllWKWebViewExternalAPI.webView(
            forIdentifier: identifier, withPluginRegistry: registry
          )
        else {
          result(FlutterError(
            code: "player_unavailable",
            message: "The YouTube player is no longer available.",
            details: nil
          ))
          return
        }
        enableYoutubeFullscreen(webView)
        result(nil)
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

  /// The pasteboard plugin reads every URL as a file path, so a copied web
  /// link would name a local file. Paste reads copied files through this.
  private func attachPasteboardChannel(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "org.discourse.native/pasteboard",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "fileURLPaths" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(pasteboardFilePaths(NSPasteboard.general))
    }
    pasteboardChannel = channel
  }

  private func windowFrameArguments() -> [String: Double] {
    [
      "x": Double(frame.minX),
      "y": Double(frame.minY),
      "width": Double(frame.width),
      "height": Double(frame.height),
    ]
  }

  private func sendWindowFrame() {
    windowChannel?.invokeMethod("windowFrameChanged", arguments: windowFrameArguments())
  }

  private func observeWindowFrame(
    _ name: Notification.Name,
    action: @escaping (MainFlutterWindow) -> Void
  ) {
    windowFrameObservers.append(NotificationCenter.default.addObserver(
      forName: name,
      object: self,
      queue: .main
    ) { [weak self] _ in
      if let self { action(self) }
    })
  }
}

/// Keep one owner for a trackpad gesture, including its momentum. Rechecking
/// only the hit view on every event can switch between Flutter's pan/zoom
/// physics and forwarded wheel deltas as an embed scrolls under the pointer.
struct WebViewScrollRouting {
  private var forwardingGesture = false
  private var awaitingBegan = false

  mutating func shouldForward(
    phase: NSEvent.Phase,
    momentumPhase: NSEvent.Phase,
    overWebView: Bool
  ) -> Bool {
    if phase.contains(.mayBegin) {
      forwardingGesture = overWebView
      awaitingBegan = true
    } else if phase.contains(.began) {
      if !awaitingBegan { forwardingGesture = overWebView }
      awaitingBegan = false
    } else if phase.isEmpty && momentumPhase.isEmpty {
      // Discrete mouse-wheel ticks have no gesture lifecycle.
      return overWebView
    }

    let forward = forwardingGesture
    if phase.contains(.cancelled) || momentumPhase.contains(.ended)
      || momentumPhase.contains(.cancelled) {
      forwardingGesture = false
      awaitingBegan = false
    }
    // Retain ownership after phase.ended: native momentum may follow. A new
    // gesture's began/mayBegin replaces it when there is no momentum.
    return forward
  }
}

func enableYoutubeFullscreen(_ webView: WKWebView) {
  if #available(macOS 12.3, *) {
    webView.configuration.preferences.isElementFullscreenEnabled = true
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
