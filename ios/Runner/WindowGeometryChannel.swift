import Flutter
import UIKit

final class WindowGeometryChannel {
  private weak var registrar: FlutterPluginRegistrar?
  private var channel: FlutterMethodChannel?
  private var probe: UIView?
  private var observers: [NSObjectProtocol] = []

  func attach(to registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    let channel = FlutterMethodChannel(
      name: "org.discourse.native/window_geometry", binaryMessenger: registrar.messenger()
    )
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "geometry" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.attachProbe()
      if #available(iOS 26.0, *) {
        result((self?.probe as? WindowCornerProbe)?.geometry?.payload)
      } else {
        result(nil)
      }
    }
    for name in [UIWindow.didBecomeVisibleNotification, UIScene.didActivateNotification,
                 UIApplication.didBecomeActiveNotification] {
      observers.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in self?.attachProbe() })
    }
    attachProbe()
  }

  private func attachProbe() {
    guard #available(iOS 26.0, *), let host = registrar?.viewController?.view else { return }
    if probe?.superview === host { return }
    probe?.removeFromSuperview()
    let next = WindowCornerProbe(frame: host.bounds)
    next.onChange = { [weak self] geometry in
      self?.channel?.invokeMethod("geometryChanged", arguments: geometry?.payload)
    }
    probe = next
    host.addSubview(next)
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    channel?.setMethodCallHandler(nil)
    probe?.removeFromSuperview()
  }
}

private struct WindowCornerGeometry: Equatable {
  let width: CGFloat
  let height: CGFloat
  let topLeft: CGFloat
  let topRight: CGFloat
  let bottomLeft: CGFloat
  let bottomRight: CGFloat

  var payload: [String: Double] {
    ["width": Double(width), "height": Double(height),
     "topLeft": Double(topLeft), "topRight": Double(topRight),
     "bottomLeft": Double(bottomLeft), "bottomRight": Double(bottomRight)]
  }
}

@available(iOS 26.0, *)
private final class WindowCornerProbe: UIView {
  private(set) var geometry: WindowCornerGeometry?
  var onChange: ((WindowCornerGeometry?) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    cornerConfiguration = .corners(radius: .containerConcentric())
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    isHidden = true
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    publish(nil)
    if window != nil { setNeedsLayout() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard window != nil, !bounds.isEmpty else { publish(nil); return }
    // UIKit resolves concentric radii during this view's own layout. Reading
    // earlier from its controller can report zero before that work completes.
    publish(WindowCornerGeometry(
      width: bounds.width, height: bounds.height,
      topLeft: effectiveRadius(corner: .topLeft),
      topRight: effectiveRadius(corner: .topRight),
      bottomLeft: effectiveRadius(corner: .bottomLeft),
      bottomRight: effectiveRadius(corner: .bottomRight)
    ))
  }

  private func publish(_ next: WindowCornerGeometry?) {
    guard next != geometry else { return }
    geometry = next
    onChange?(next)
  }
}
