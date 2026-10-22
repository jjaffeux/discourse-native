import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'd_overlay_route.dart';
import 'material_theme.dart';

/// Draws opted-in glass with the system material on iOS 26.
///
/// A backdrop filter in Flutter's frame ends the render pass, copies the screen
/// and blurs it on every frame. UIKit composites `UIGlassEffect` views above
/// the Flutter view outside that frame. Flutter keeps layout, gestures and
/// semantics: after each frame it reports every glass shape's frame, corners,
/// tint and opacity, plus an image of the content drawn above the glass, which
/// Flutter composites itself at 1/255 opacity so touches still land on it.
///
/// UIKit draws above everything Flutter shows, so a [NativeGlassScope] hands
/// its glass back to Flutter while its route is covered, while a sheet closes
/// over it, and while any [NativeGlassOccluder] is mounted.
abstract final class NativeGlass {
  static const channel = MethodChannel('org.discourse.native/glass');

  /// Whether the host app renders system glass; probed once per process.
  static final ValueNotifier<bool> available = ValueNotifier(false);

  /// Keeps Flutter glass everywhere, for side-by-side measurement.
  static final ValueNotifier<bool> disabled = ValueNotifier(false);

  static final ValueNotifier<int> _occluders = ValueNotifier(0);
  static final _groups = <NativeGlassGroup>{};
  static final _images = <_RenderNativeGlassContent, int>{};
  static bool _probed = false;
  static bool _ticking = false;
  static String? _sent;

  static void _probe() {
    if (_probed || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    _probed = true;
    unawaited(
      channel
          .invokeMethod<bool>('available')
          .then((value) => available.value = value ?? false)
          .catchError((Object _) => false),
    );
  }

  /// The active group drawing this context's glass, or null for Flutter glass.
  static NativeGlassGroup? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ActiveGroup>()?.group;

  static void _activate(NativeGlassGroup group) {
    _groups.add(group);
    if (_ticking) return;
    _ticking = true;
    SchedulerBinding.instance.addPostFrameCallback(_tick);
  }

  static void _deactivate(NativeGlassGroup group) {
    if (_groups.remove(group)) SchedulerBinding.instance.scheduleFrame();
  }

  // Runs after every frame while any group is active: transforms above the
  // glass can move it without repainting or rebuilding anything inside.
  static void _tick(Duration _) {
    _sync();
    if (_groups.isEmpty) {
      _ticking = false;
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback(_tick);
  }

  static void _sync() {
    final groups = <(List<int>, Map<String, Object?>)>[];
    for (final group in _groups) {
      if (group._sceneOf() case final scene?) groups.add(scene);
    }
    groups.sort((a, b) => _compare(a.$1, b.$1));
    _send({
      'visible': groups.isNotEmpty,
      'groups': [for (final group in groups) group.$2],
      'alive': {
        for (final group in _groups) ...[
          for (final node in group._nodes)
            if (node is _RenderNativeGlassContent) identityHashCode(node),
          ...group._slots.values,
        ],
      }.toList(),
    });
  }

  static void _send(Map<String, Object?> scene) {
    // Hosts without system glass never showed anything to hide.
    if (_sent == null && scene['visible'] != true) return;
    final encoded = jsonEncode(scene);
    if (encoded == _sent) return;
    _sent = encoded;
    unawaited(
      channel.invokeMethod<void>('scene', scene).catchError((Object _) {}),
    );
  }

  static int _compare(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }

  /// Child indexes from [ancestor] down to [node], which is their paint order.
  static List<int> _path(RenderObject node, RenderObject? ancestor) {
    final path = <int>[];
    for (var child = node; child != ancestor; child = child.parent!) {
      final parent = child.parent;
      if (parent == null) break;
      var index = 0;
      var found = 0;
      parent.visitChildren((sibling) {
        if (sibling == child) found = index;
        index++;
      });
      path.add(found);
    }
    return path.reversed.toList();
  }

  static Rect _globalRect(RenderBox box) => MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );

  static List<double> _rect(Rect rect) => [
    rect.left,
    rect.top,
    rect.width,
    rect.height,
  ];
}

/// A group of glass drawn by the system while it is active, such as one
/// control row. With [merge], touching shapes become one, as joined controls
/// look in Flutter glass.
class NativeGlassScope extends StatefulWidget {
  const NativeGlassScope({super.key, this.merge = false, required this.child});

  final bool merge;
  final Widget child;

  @override
  State<NativeGlassScope> createState() => NativeGlassGroup();
}

class NativeGlassGroup extends State<NativeGlassScope> {
  _RenderNativeGlassScopeBox? _box;
  final _nodes = <_NativeGlassNode>{};
  bool _dark = false;
  bool _shown = false;

  // The content last shown at each position in this group. A control that
  // remounts there, such as an action whose icon changed, keeps showing it
  // until its own image arrives.
  var _slots = <String, int>{};

  @override
  void initState() {
    super.initState();
    NativeGlass._probe();
  }

  @override
  void dispose() {
    NativeGlass._deactivate(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      NativeGlass.available,
      NativeGlass.disabled,
      NativeGlass._occluders,
      // Sheets count as covering through their closing transition, after
      // their route has already stopped covering this one.
      DOverlayRoute.modalCoverCountOf(context),
    ]),
    builder: (context, child) {
      final active =
          NativeGlass.available.value &&
          !NativeGlass.disabled.value &&
          NativeGlass._occluders.value == 0 &&
          DOverlayRoute.modalCoverCountOf(context).value == 0 &&
          DMaterialTheme.glassOf(context) &&
          (ModalRoute.isCurrentOf(context) ?? true);
      _dark = Theme.of(context).brightness == Brightness.dark;
      if (active) {
        NativeGlass._activate(this);
      } else {
        NativeGlass._deactivate(this);
      }
      return _ActiveGroup(
        group: active ? this : null,
        child: _NativeGlassScopeBox(group: this, child: child!),
      );
    },
    child: widget.child,
  );

  (List<int>, Map<String, Object?>)? _sceneOf() {
    final box = _box;
    if (!mounted || box == null || !box.attached || !box.hasSize) return null;
    final elements = <(List<int>, Map<String, Object?>)>[];
    final slots = <String, int>{};
    var complete = true;
    for (final node in _nodes) {
      final scene = node.sceneOf();
      if (scene == null) continue;
      final path = NativeGlass._path(node as RenderObject, box);
      if (scene['image'] != -1) {
        final slot = path.join('.');
        if (scene['image'] != 0) {
          slots[slot] = scene['id']! as int;
        } else {
          complete = false;
          if (_slots[slot] case final previous?) {
            scene['fallback'] = previous;
            slots[slot] = previous;
          }
        }
      }
      elements.add((path, scene));
    }
    // A group first appears with all of its content; afterwards a control
    // still waiting for its image never hides the rest.
    if (elements.isEmpty || (!_shown && !complete)) return null;
    _shown = true;
    // A position can be empty for a frame between one control leaving and
    // the next arriving, so keep what it showed last.
    _slots = {..._slots, ...slots};
    elements.sort((a, b) => NativeGlass._compare(a.$1, b.$1));
    Rect? clip;
    RenderObject child = box;
    for (var parent = box.parent; parent != null; parent = parent.parent) {
      final local = parent.describeApproximatePaintClip(child);
      if (local != null) {
        final global = MatrixUtils.transformRect(
          parent.getTransformTo(null),
          local,
        );
        clip = clip?.intersect(global) ?? global;
      }
      child = parent;
    }
    return (
      NativeGlass._path(box, null),
      {
        'id': identityHashCode(this),
        'merge': widget.merge,
        'dark': _dark,
        'clip': clip == null ? null : NativeGlass._rect(clip),
        'elements': [for (final element in elements) element.$2],
      },
    );
  }
}

class _ActiveGroup extends InheritedWidget {
  const _ActiveGroup({required this.group, required super.child});

  final NativeGlassGroup? group;

  @override
  bool updateShouldNotify(_ActiveGroup oldWidget) => oldWidget.group != group;
}

class _NativeGlassScopeBox extends SingleChildRenderObjectWidget {
  const _NativeGlassScopeBox({required this.group, required super.child});

  final NativeGlassGroup group;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNativeGlassScopeBox(group);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderNativeGlassScopeBox renderObject,
  ) => renderObject.group = group;
}

class _RenderNativeGlassScopeBox extends RenderProxyBox {
  _RenderNativeGlassScopeBox(this._group);

  NativeGlassGroup _group;
  set group(NativeGlassGroup value) {
    if (value == _group) return;
    if (_group._box == this) _group._box = null;
    _group = value;
    if (attached) _group._box = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _group._box = this;
  }

  @override
  void detach() {
    if (_group._box == this) _group._box = null;
    super.detach();
  }
}

/// Opens over native glass: every group draws Flutter glass while mounted.
class NativeGlassOccluder extends StatefulWidget {
  const NativeGlassOccluder({super.key, required this.child});

  final Widget child;

  @override
  State<NativeGlassOccluder> createState() => _NativeGlassOccluderState();
}

class _NativeGlassOccluderState extends State<NativeGlassOccluder> {
  bool _counted = false;

  // Overlays mount during a build, where their listeners cannot rebuild.
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _counted = true;
      NativeGlass._occluders.value++;
    });
  }

  @override
  void dispose() {
    if (_counted) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => NativeGlass._occluders.value--,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

abstract interface class _NativeGlassNode {
  Map<String, Object?>? sceneOf();
}

Map<String, Object?>? _nodeScene(
  RenderBox node, {
  required bool glass,
  required BorderRadius? radius,
  required Color? tint,
  required int image,
}) {
  if (!node.attached || !node.hasSize) return null;
  var opacity = 1.0;
  for (RenderObject? parent = node.parent; parent != null;) {
    if (parent is RenderOffstage && parent.offstage) return null;
    if (parent is RenderOpacity) opacity *= parent.opacity;
    if (parent is RenderAnimatedOpacity) opacity *= parent.opacity.value;
    parent = parent.parent;
  }
  final rect = NativeGlass._globalRect(node);
  if (opacity <= 0 || rect.isEmpty) return null;
  return {
    'id': identityHashCode(node),
    'rect': NativeGlass._rect(rect),
    'opacity': opacity,
    'glass': glass,
    // Null draws a capsule, which follows the shape through size changes.
    'radius': radius == null
        ? null
        : [
            radius.topLeft.x,
            radius.topRight.x,
            radius.bottomRight.x,
            radius.bottomLeft.x,
          ],
    'tint': tint?.toARGB32(),
    'image': image,
  };
}

/// A glass shape with nothing drawn above it by the system, such as a
/// surface's background or a capsule whose controls are their own content.
class NativeGlassShape extends SingleChildRenderObjectWidget {
  const NativeGlassShape({
    super.key,
    required this.group,
    this.radius,
    this.tint,
    super.child,
  });

  final NativeGlassGroup group;

  /// Null for a capsule.
  final BorderRadius? radius;
  final Color? tint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderNativeGlassShape(group, radius, tint);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderNativeGlassShape renderObject,
  ) {
    renderObject
      ..group = group
      ..radius = radius
      ..tint = tint;
  }
}

class RenderNativeGlassShape extends RenderProxyBox
    implements _NativeGlassNode {
  RenderNativeGlassShape(this._group, this.radius, this.tint);

  NativeGlassGroup _group;
  set group(NativeGlassGroup value) {
    if (value == _group) return;
    if (attached) _group._nodes.remove(this);
    _group = value;
    if (attached) _group._nodes.add(this);
  }

  BorderRadius? radius;
  Color? tint;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _group._nodes.add(this);
  }

  @override
  void detach() {
    _group._nodes.remove(this);
    super.detach();
  }

  @override
  Map<String, Object?>? sceneOf() =>
      _nodeScene(this, glass: true, radius: radius, tint: tint, image: -1);
}

/// Content drawn by the system above the glass, optionally on a capsule pill
/// of its own. Flutter draws it at 1/255 opacity, where it still takes touches.
class NativeGlassContent extends StatelessWidget {
  const NativeGlassContent({
    super.key,
    required this.group,
    this.pill = false,
    this.tint,
    required this.child,
  });

  final NativeGlassGroup group;
  final bool pill;

  /// Colours the [pill]; null keeps the stock material.
  final Color? tint;
  final Widget child;

  @override
  Widget build(BuildContext context) => _Ghost(
    child: _NativeGlassContentSlot(
      group: group,
      pill: pill,
      tint: tint,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
      child: child,
    ),
  );
}

/// Composites its child at the lowest visible alpha. The child still paints
/// into its own layer, which is what the system's image is made from.
class _Ghost extends SingleChildRenderObjectWidget {
  const _Ghost({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGhost();
}

class _RenderGhost extends RenderProxyBox {
  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    layer = context.pushOpacity(
      offset,
      1,
      super.paint,
      oldLayer: layer as OpacityLayer?,
    );
  }
}

class _NativeGlassContentSlot extends SingleChildRenderObjectWidget {
  const _NativeGlassContentSlot({
    required this.group,
    required this.pill,
    required this.tint,
    required this.pixelRatio,
    required super.child,
  });

  final NativeGlassGroup group;
  final bool pill;
  final Color? tint;
  final double pixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNativeGlassContent(group, pill, tint, pixelRatio);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderNativeGlassContent renderObject,
  ) {
    renderObject
      ..group = group
      ..pill = pill
      ..tint = tint
      ..pixelRatio = pixelRatio;
  }
}

class _RenderNativeGlassContent extends RenderRepaintBoundary
    implements _NativeGlassNode {
  _RenderNativeGlassContent(
    this._group,
    this.pill,
    this.tint,
    this._pixelRatio,
  );

  NativeGlassGroup _group;
  set group(NativeGlassGroup value) {
    if (value == _group) return;
    if (attached) _group._nodes.remove(this);
    _group = value;
    if (attached) {
      _group._nodes.add(this);
      markNeedsPaint();
    }
  }

  bool pill;
  Color? tint;
  double _pixelRatio;
  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    _revision++;
    markNeedsPaint();
  }

  int _epoch = 0;
  int _revision = 0;
  int _attemptedRevision = 0;
  int _uploadVersion = 0;
  bool _captureScheduled = false;
  bool _capturing = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _group._nodes.add(this);
    _epoch++;
    markNeedsPaint();
  }

  @override
  void detach() {
    _group._nodes.remove(this);
    NativeGlass._images.remove(this);
    _epoch++;
    super.detach();
  }

  @override
  OffsetLayer updateCompositedLayer({required OffsetLayer? oldLayer}) =>
      oldLayer ?? _NativeGlassContentLayer(_contentChanged);

  void _contentChanged() {
    _revision++;
    _scheduleCapture();
  }

  void _scheduleCapture() {
    if (!attached ||
        _captureScheduled ||
        _capturing ||
        _revision == _attemptedRevision) {
      return;
    }
    _captureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _captureScheduled = false;
      unawaited(_capture());
    });
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.idle ||
        scheduler.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
      scheduler.scheduleFrame();
    }
  }

  Future<void> _capture() async {
    if (!attached || !hasSize || size.isEmpty || _capturing) return;
    final ticket = (epoch: _epoch, revision: _revision, scale: _pixelRatio);
    bool current() =>
        attached && _epoch == ticket.epoch && _revision == ticket.revision;
    _attemptedRevision = ticket.revision;
    _capturing = true;
    ui.Image? image;
    try {
      image = await toImage(pixelRatio: ticket.scale);
      if (!current()) return;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      image = null;
      if (bytes == null || !current()) return;
      final version = ++_uploadVersion;
      await NativeGlass.channel.invokeMethod<void>('image', {
        'id': identityHashCode(this),
        'version': version,
        'scale': ticket.scale,
        'png': bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        ),
      });
      if (!current()) return;
      NativeGlass._images[this] = version;
      SchedulerBinding.instance.scheduleFrame();
    } on Object {
      return;
    } finally {
      image?.dispose();
      _capturing = false;
      _scheduleCapture();
    }
  }

  @override
  Map<String, Object?>? sceneOf() => _nodeScene(
    this,
    glass: pill,
    radius: null,
    tint: tint,
    image: NativeGlass._images[this] ?? 0,
  );
}

class _NativeGlassContentLayer extends OffsetLayer {
  _NativeGlassContentLayer(this._onContentChanged);

  final VoidCallback _onContentChanged;
  static int _snapshotDepth = 0;

  @override
  void addToScene(ui.SceneBuilder builder) {
    super.addToScene(builder);
    if (_snapshotDepth == 0) _onContentChanged();
  }

  // Image snapshots build a scene too, including any nested content layers.
  @override
  ui.Scene buildScene(ui.SceneBuilder builder) {
    _snapshotDepth++;
    try {
      return super.buildScene(builder);
    } finally {
      _snapshotDepth--;
    }
  }
}
