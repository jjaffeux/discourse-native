import Cocoa
import FlutterMacOS

/// Draws opted-in glass with the system material above the Flutter view, where
/// the window server composites it outside Flutter's frame. Flutter keeps
/// layout, pointer input and semantics: it reports each group's clip and each
/// glass shape's frame, corners, tint and opacity whenever they change, and an
/// image of the content drawn above the glass. These views never take events.
final class GlassRenderer {
  private let channel: FlutterMethodChannel
  private weak var host: NSView?
  private let root = PassiveGlassLayer()
  private var groups: [Int: GlassGroupView] = [:]
  private var images: [Int: (version: Int, image: NSImage)] = [:]

  init(messenger: FlutterBinaryMessenger, host: NSView) {
    self.host = host
    channel = FlutterMethodChannel(
      name: "org.discourse.native/glass", binaryMessenger: messenger
    )
    root.isHidden = true
    root.setAccessibilityElement(false)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "available":
        if #available(macOS 26.0, *) { result(true) } else { result(false) }
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
    guard scene["visible"] as? Bool == true, let host else {
      root.isHidden = true
      return
    }
    if root.superview !== host {
      host.addSubview(root, positioned: .above, relativeTo: nil)
    } else if host.subviews.last !== root {
      host.addSubview(root, positioned: .above, relativeTo: nil)
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    root.frame = host.bounds
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
    GlassGroupView.order(order, in: root)
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
      let bitmap = NSBitmapImageRep(data: png.data)
    else { return }
    if let current = images[id], current.version >= version { return }
    let scale = CGFloat(payload["scale"] as? Double ?? 2)
    let image = NSImage(
      size: NSSize(
        width: CGFloat(bitmap.pixelsWide) / scale,
        height: CGFloat(bitmap.pixelsHigh) / scale
      )
    )
    image.addRepresentation(bitmap)
    images[id] = (version, image)
    for group in groups.values { group.setImage(image, for: id) }
  }
}

/// Top-left origin, so Flutter's logical rectangles apply as they are, and no
/// pointer event ever lands on it.
class PassiveGlassLayer: NSView {
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// One Flutter scope: its glass behind all of its content, clipped like the
/// Flutter subtree. Merging groups render touching shapes as one, as joined
/// controls look in Flutter glass.
final class GlassGroupView: PassiveGlassLayer {
  let merge: Bool
  private let glassLayer: NSView
  private let imageLayer = PassiveGlassLayer()
  private var glass: [Int: NSView] = [:]
  private var contents: [Int: NSImageView] = [:]
  private var tints: [Int: Int] = [:]

  init(merge: Bool) {
    self.merge = merge
    if merge, #available(macOS 26.0, *) {
      let container = PassiveGlassContainer()
      container.spacing = 0
      let content = PassiveGlassLayer()
      container.contentView = content
      glassLayer = container
    } else {
      glassLayer = PassiveGlassLayer()
    }
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = true
    addSubview(glassLayer)
    addSubview(imageLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private var glassParent: NSView {
    if #available(macOS 26.0, *), let container = glassLayer as? NSGlassEffectContainerView {
      return container.contentView ?? glassLayer
    }
    return glassLayer
  }

  func update(
    _ group: [String: Any], bounds: CGRect, images: [Int: (version: Int, image: NSImage)]
  ) {
    let clip = GlassGroupView.rect(group["clip"]) ?? bounds
    frame = clip
    glassLayer.frame = self.bounds
    glassParent.frame = glassLayer.bounds
    imageLayer.frame = self.bounds
    appearance = NSAppearance(named: group["dark"] as? Bool == true ? .darkAqua : .aqua)
    var glassOrder: [NSView] = []
    var imageOrder: [NSView] = []
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
        view.alphaValue = opacity
        GlassGroupView.shape(view, element["radius"])
        glassOrder.append(view)
      } else if let view = glass.removeValue(forKey: id) {
        view.removeFromSuperview()
      }
      if (element["image"] as? Int ?? -1) >= 0 {
        let view = contents[id] ?? {
          let view = PassiveImageView()
          // A control that resizes keeps its last image until the new one
          // arrives; drawn at its own size it stays legible meanwhile.
          view.imageScaling = .scaleNone
          view.imageAlignment = .alignTopLeft
          contents[id] = view
          return view
        }()
        // A remounted control shows what its position showed until its own
        // image arrives.
        view.image = images[id]?.image
          ?? (element["fallback"] as? Int).flatMap { images[$0]?.image }
        view.frame = local
        view.alphaValue = opacity
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

  func setImage(_ image: NSImage, for id: Int) {
    contents[id]?.image = image
  }

  private func glassView(_ id: Int, tint: Int?) -> NSView {
    if let view = glass[id], tints[id] == tint { return view }
    let view: NSView
    if #available(macOS 26.0, *) {
      let effect = (glass[id] as? PassiveGlassBackdrop) ?? PassiveGlassBackdrop()
      effect.style = .regular
      effect.tintColor = tint.map(GlassGroupView.color)
      view = effect
    } else {
      let effect = (glass[id] as? PassiveVibrancyBackdrop) ?? PassiveVibrancyBackdrop()
      effect.material = .hudWindow
      effect.blendingMode = .withinWindow
      effect.state = .active
      effect.wantsLayer = true
      effect.layer?.masksToBounds = true
      view = effect
    }
    glass[id] = view
    tints[id] = tint
    return view
  }

  private static func shape(_ view: NSView, _ radius: Any?) {
    let corners = radius as? [Double]
    // AppKit glass rounds every corner alike; the largest corner keeps a
    // panel-cornered control's outline inside its Flutter shape.
    let value = corners.flatMap { $0.max() }.map { CGFloat($0) }
      ?? min(view.frame.width, view.frame.height) / 2
    if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
      glass.cornerRadius = value
    } else {
      view.layer?.cornerRadius = value
    }
  }

  static func order(_ views: [NSView], in parent: NSView) {
    for (index, view) in views.enumerated()
    where view.superview !== parent || index >= parent.subviews.count
      || parent.subviews[index] !== view
    {
      if view.superview === parent { view.removeFromSuperview() }
      if index >= parent.subviews.count {
        parent.addSubview(view)
      } else {
        parent.addSubview(view, positioned: .below, relativeTo: parent.subviews[index])
      }
    }
  }

  private static func rect(_ value: Any?) -> CGRect? {
    guard let values = value as? [Double], values.count == 4 else { return nil }
    return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
  }

  private static func color(_ argb: Int) -> NSColor {
    NSColor(
      srgbRed: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}

@available(macOS 26.0, *)
final class PassiveGlassContainer: NSGlassEffectContainerView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PassiveImageView: NSImageView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
