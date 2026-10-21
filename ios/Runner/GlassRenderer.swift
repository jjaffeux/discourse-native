import Flutter
import UIKit

/// Draws opted-in glass with the system material above the Flutter view, where
/// the render server composites it outside Flutter's frame. Flutter keeps
/// layout, gestures and semantics: it reports each group's clip and each glass
/// shape's frame, corners, tint and opacity whenever they change, and an image
/// of the content drawn above the glass. These views never take touches.
final class GlassRenderer {
  private let channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?
  private let root = UIView()
  private var groups: [Int: GlassGroupView] = [:]
  private var images: [Int: (version: Int, image: UIImage)] = [:]

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(
      name: "org.discourse.native/glass", binaryMessenger: registrar.messenger()
    )
    root.isUserInteractionEnabled = false
    root.accessibilityElementsHidden = true
    root.isHidden = true
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "available":
        if #available(iOS 26.0, *) { result(true) } else { result(false) }
      case "scene":
        self.apply(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "image":
        self.store(call.arguments as? [String: Any] ?? [:])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func apply(_ scene: [String: Any]) {
    guard scene["visible"] as? Bool == true,
      let host = registrar?.viewController?.view
    else {
      root.isHidden = true
      return
    }
    if root.superview !== host { host.addSubview(root) }
    if host.subviews.last !== root { host.bringSubviewToFront(root) }
    root.frame = host.bounds
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    var order: [GlassGroupView] = []
    for case let group as [String: Any] in scene["groups"] as? [Any] ?? [] {
      guard let id = group["id"] as? Int else { continue }
      let merge = group["merge"] as? Bool ?? false
      let view: GlassGroupView
      if let existing = groups[id], existing.merge == merge {
        view = existing
      } else {
        groups[id]?.removeFromSuperview()
        view = GlassGroupView(merge: merge)
        groups[id] = view
      }
      view.update(group, bounds: root.bounds, images: images)
      order.append(view)
    }
    let shown = Set(order.map(ObjectIdentifier.init))
    for (id, view) in groups where !shown.contains(ObjectIdentifier(view)) {
      view.removeFromSuperview()
      groups[id] = nil
    }
    for (index, view) in order.enumerated()
    where index >= root.subviews.count || root.subviews[index] !== view {
      root.insertSubview(view, at: index)
    }
    // Content that stops showing keeps its image: it repaints only when it
    // changes, so Flutter does not send it again when it reappears.
    let alive = Set((scene["alive"] as? [Int]) ?? [])
    for id in images.keys where !alive.contains(id) { images[id] = nil }
    CATransaction.commit()
    root.isHidden = false
  }

  private func store(_ payload: [String: Any]) {
    guard let id = payload["id"] as? Int,
      let version = payload["version"] as? Int,
      let png = payload["png"] as? FlutterStandardTypedData,
      let image = UIImage(
        data: png.data, scale: CGFloat(payload["scale"] as? Double ?? 3)
      )
    else { return }
    if let current = images[id], current.version >= version { return }
    images[id] = (version, image)
    for group in groups.values { group.setImage(image, for: id) }
  }
}

/// One Flutter scope: its glass behind all of its content, clipped like the
/// Flutter subtree. Merging groups render touching shapes as one, as joined
/// controls look in Flutter glass.
final class GlassGroupView: UIView {
  let merge: Bool
  private let glassLayer: UIView
  private let imageLayer = UIView()
  private var glass: [Int: UIVisualEffectView] = [:]
  private var contents: [Int: UIImageView] = [:]
  private var tints: [Int: Int] = [:]

  init(merge: Bool) {
    self.merge = merge
    if merge, #available(iOS 26.0, *) {
      let container = UIGlassContainerEffect()
      container.spacing = 0
      glassLayer = UIVisualEffectView(effect: container)
    } else {
      glassLayer = UIView()
    }
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    clipsToBounds = true
    addSubview(glassLayer)
    addSubview(imageLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private var glassParent: UIView {
    (glassLayer as? UIVisualEffectView)?.contentView ?? glassLayer
  }

  func update(_ group: [String: Any], bounds: CGRect, images: [Int: (version: Int, image: UIImage)]) {
    let clip = GlassGroupView.rect(group["clip"]) ?? bounds
    frame = clip
    glassLayer.frame = self.bounds
    imageLayer.frame = self.bounds
    overrideUserInterfaceStyle = group["dark"] as? Bool == true ? .dark : .light
    var glassOrder: [UIView] = []
    var imageOrder: [UIView] = []
    var seen = Set<Int>()
    for case let element as [String: Any] in group["elements"] as? [Any] ?? [] {
      guard let id = element["id"] as? Int,
        let rect = GlassGroupView.rect(element["rect"])
      else { continue }
      seen.insert(id)
      let local = rect.offsetBy(dx: -clip.minX, dy: -clip.minY)
      let opacity = CGFloat(element["opacity"] as? Double ?? 1)
      if element["glass"] as? Bool == true {
        let view = glassView(id, tint: element["tint"] as? Int)
        view.frame = local
        view.alpha = opacity
        GlassGroupView.shape(view, element["radius"])
        glassOrder.append(view)
      } else if let view = glass.removeValue(forKey: id) {
        view.removeFromSuperview()
      }
      if (element["image"] as? Int ?? -1) >= 0 {
        let view = contents[id] ?? {
          let view = UIImageView()
          view.contentMode = .scaleToFill
          contents[id] = view
          return view
        }()
        view.image = images[id]?.image
        view.frame = local
        view.alpha = opacity
        imageOrder.append(view)
      }
    }
    for (id, view) in glass where !seen.contains(id) {
      view.removeFromSuperview()
      glass[id] = nil
    }
    for (id, view) in contents where !seen.contains(id) {
      view.removeFromSuperview()
      contents[id] = nil
    }
    GlassGroupView.order(glassOrder, in: glassParent)
    GlassGroupView.order(imageOrder, in: imageLayer)
  }

  func setImage(_ image: UIImage, for id: Int) {
    contents[id]?.image = image
  }

  private func glassView(_ id: Int, tint: Int?) -> UIVisualEffectView {
    if let view = glass[id], tints[id] == tint { return view }
    let view = glass[id] ?? UIVisualEffectView()
    if #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: .regular)
      effect.tintColor = tint.map(GlassGroupView.color)
      view.effect = effect
    } else {
      view.effect = UIBlurEffect(style: .systemThinMaterial)
      view.clipsToBounds = true
    }
    view.isUserInteractionEnabled = false
    glass[id] = view
    tints[id] = tint
    return view
  }

  private static func shape(_ view: UIView, _ radius: Any?) {
    let corners = radius as? [Double]
    if #available(iOS 26.0, *) {
      if let corners, corners.count == 4 {
        view.cornerConfiguration = .corners(
          topLeftRadius: .fixed(corners[0]),
          topRightRadius: .fixed(corners[1]),
          bottomLeftRadius: .fixed(corners[3]),
          bottomRightRadius: .fixed(corners[2])
        )
      } else {
        view.cornerConfiguration = .capsule()
      }
    } else {
      view.layer.cornerRadius = corners?.first.map { CGFloat($0) }
        ?? min(view.bounds.width, view.bounds.height) / 2
    }
  }

  private static func order(_ views: [UIView], in parent: UIView) {
    for (index, view) in views.enumerated()
    where view.superview !== parent || index >= parent.subviews.count
      || parent.subviews[index] !== view
    {
      parent.insertSubview(view, at: index)
    }
  }

  private static func rect(_ value: Any?) -> CGRect? {
    guard let values = value as? [Double], values.count == 4 else { return nil }
    return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
  }

  private static func color(_ argb: Int) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}
