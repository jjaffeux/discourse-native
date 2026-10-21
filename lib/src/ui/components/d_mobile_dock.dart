import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../foundation/app_text_scaler.dart';
import '../foundation/glass_presets.dart';
import '../foundation/material_surface.dart';
import '../foundation/material_theme.dart';
import '../foundation/native_glass.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_mobile_dock_item.dart';

/// A floating capsule whose destinations divide the space left by its action.
/// Natural label and badge widths determine overflow before the row is painted.
class DMobileDock extends StatefulWidget {
  const DMobileDock({
    super.key,
    required this.destinations,
    required this.more,
    required this.collapsedDestination,
    required this.onOverflowChanged,
    this.action,
    this.collapsed = false,
    this.destinationsHidden = false,
    this.referenceTextScale = false,
  });

  final List<Widget> destinations;
  final Widget more;
  final Widget collapsedDestination;
  final Widget? action;
  final bool collapsed;
  final bool destinationsHidden;

  /// Aligns with a composer's reference dimensions while retaining app zoom
  /// and accessibility scaling. Other navigation keeps its mobile baseline.
  final bool referenceTextScale;
  final ValueChanged<int> onOverflowChanged;

  /// Height of the expanded capsule with the dock's selected text scale.
  static double expandedExtentOf(
    BuildContext context, {
    bool referenceTextScale = false,
  }) {
    final scaler = referenceTextScale
        ? DReferenceTextScale.scalerOf(context)
        : MediaQuery.textScalerOf(context);
    return 62 + math.max(0.0, scaler.scale(11) - 11);
  }

  /// Width of the folded destination, including its visible capsule insets.
  static double collapsedExtentOf(BuildContext context) =>
      expandedExtentOf(context) - 14;

  @override
  State<DMobileDock> createState() => _DMobileDockState();
}

class _DMobileDockState extends State<DMobileDock>
    with SingleTickerProviderStateMixin {
  int? _shown;
  double _anchor = 20;
  late final _ticker = createTicker(_step);
  late double _phase;
  double _velocity = 0;
  Duration? _lastElapsed;
  bool _spring = false;
  static const _springDescription = SpringDescription(
    mass: 1,
    stiffness: 195,
    damping: 19.5,
  );

  @override
  void initState() {
    super.initState();
    _phase = widget.collapsed ? 1 : 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spring =
        DMaterialTheme.glassOf(context) &&
        !MediaQuery.disableAnimationsOf(context);
    if (!_spring) {
      _ticker.stop();
      _phase = widget.collapsed ? 1 : 0;
      _velocity = 0;
    }
  }

  @override
  void didUpdateWidget(DMobileDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsed != widget.collapsed) {
      if (_spring) {
        if (!_ticker.isActive) {
          _lastElapsed = null;
          _ticker.start();
        }
      } else {
        _phase = widget.collapsed ? 1 : 0;
      }
    }
  }

  void _step(Duration elapsed) {
    final dt = _lastElapsed == null
        ? 1 / 60.0
        : (elapsed - _lastElapsed!).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    final target = widget.collapsed ? 1.0 : 0.0;
    final simulation = SpringSimulation(
      _springDescription,
      _phase,
      target,
      _velocity,
    );
    final step = dt.clamp(0.0, .064);
    final phase = simulation.x(step);
    final velocity = simulation.dx(step);
    setState(() {
      _phase = phase;
      _velocity = velocity;
      if ((_phase - target).abs() < .001 && _velocity.abs() < .01) {
        _phase = target;
        _velocity = 0;
        _ticker.stop();
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  bool get collapsed => widget.collapsed;
  bool get destinationsHidden => widget.destinationsHidden;
  List<Widget> get destinations => widget.destinations;
  Widget get more => widget.more;
  Widget get collapsedDestination => widget.collapsedDestination;
  Widget? get action => widget.action;
  void _overflow(int shown) {
    if (!mounted) return;
    if (_shown != shown) setState(() => _shown = shown);
    widget.onOverflowChanged(shown);
  }

  void _anchorChanged(double anchor) {
    if (mounted && (_anchor - anchor).abs() > .5) {
      setState(() => _anchor = anchor);
    }
  }

  Widget _destination(Widget child) => ExcludeSemantics(
    excluding: destinationsHidden,
    child: IgnorePointer(
      ignoring: destinationsHidden,
      child: Opacity(opacity: destinationsHidden ? 0 : 1, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) => NativeGlassScope(
    child: widget.referenceTextScale
        ? DReferenceTextScale(child: Builder(builder: _buildDock))
        : Builder(builder: _buildDock),
  );

  Widget _buildDock(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final reduced = MediaQuery.disableAnimationsOf(context);
      final expandedExtent = DMobileDock.expandedExtentOf(context);
      final growth = expandedExtent - 62;
      final round = DMobileDock.collapsedExtentOf(context);
      final phase = _spring ? _phase.clamp(0.0, 1.0) : (collapsed ? 1.0 : 0.0);
      final inset = 6 - 2 * phase;
      final navOpacity = _spring
          ? (1 - phase / .35).clamp(0.0, 1.0)
          : (collapsed ? 0.0 : 1.0);
      final revealOpacity = _spring
          ? ((phase - .35) / .35).clamp(0.0, 1.0)
          : (collapsed ? 1.0 : 0.0);
      final radius = BorderRadius.circular(999);
      final tokens = DTokens.of(context);
      final glass = DMaterialTheme.glassOf(context);
      final nativeGlass = NativeGlass.of(context);
      // Opacity creates an empty offscreen layer around a live backdrop lens.
      // Keep glass on the dock's painted backdrop and dissolve the row through
      // geometry instead. Each control keeps its slot throughout the morph.
      Widget navigationArtwork(Widget child) =>
          glass ? Transform.scale(scale: navOpacity, child: child) : child;
      final well = Color.lerp(
        tokens.background,
        tokens.foreground,
        .12,
      )!.withValues(alpha: DMaterialTheme.reducedOf(context) ? 1 : .94);
      Widget dockSurface(Widget child) => nativeGlass != null
          ? NativeGlassShape(group: nativeGlass, child: child)
          : glass
          ? DGlassSurface(
              radius: (expandedExtent - 14 * phase) / 2,
              brightness: Theme.of(context).brightness,
              child: child,
            )
          : DMaterialSurface(
              color: well,
              radius: radius,
              depth: DSurfaceDepth.recessed,
              preserveColor: true,
              child: child,
            );
      final navigation = OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: constraints.maxWidth - 12,
        maxWidth: constraints.maxWidth - 12,
        child: _DockRow(
          direction: Directionality.of(context),
          onOverflowChanged: _overflow,
          selected: destinations.indexWhere(
            (item) => item is DMobileDockItem && item.selected,
          ),
          onAnchorChanged: _anchorChanged,
          count: destinations.length,
          actionExtent: action == null ? 0 : 50 + growth,
          children: [
            for (final (index, item) in destinations.indexed)
              Offstage(
                offstage: index >= (_shown ?? destinations.length),
                child: navigationArtwork(_destination(item)),
              ),
            Offstage(
              offstage: _shown == destinations.length,
              child: navigationArtwork(_destination(more)),
            ),
            if (action != null)
              navigationArtwork(action!)
            else
              const SizedBox.shrink(),
          ],
        ),
      );
      final capsuleArtwork = Align(
        alignment: AlignmentDirectional.bottomStart,
        heightFactor: 1,
        widthFactor: 1,
        child: AnimatedContainer(
          key: const ValueKey('mobile-dock-surface'),
          duration: reduced || _spring
              ? Duration.zero
              : const Duration(milliseconds: 420),
          curve: const Cubic(.32, .72, 0, 1),
          width: constraints.maxWidth + (round - constraints.maxWidth) * phase,
          decoration: glass
              ? null
              : BoxDecoration(
                  color: DMaterialSurface.fill(context, well),
                  borderRadius: radius,
                ),
          child: dockSurface(
            AnimatedPadding(
              padding: EdgeInsets.all(inset),
              duration: reduced || _spring
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: const Cubic(.32, .72, 0, 1),
              child: ClipRRect(
                borderRadius: radius,
                child: SizedBox(
                  height: 50 + growth - 10 * phase,
                  child: Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [
                      ExcludeSemantics(
                        excluding: collapsed || navOpacity < 1,
                        child: IgnorePointer(
                          ignoring: collapsed || navOpacity < 1,
                          child: glass
                              // Keep invisible controls mounted for measurement,
                              // but collapse their capture bounds into the capsule.
                              ? Transform.scale(
                                  scale: navOpacity > 0 ? 1 : 0,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: navigation,
                                )
                              : AnimatedOpacity(
                                  opacity: navOpacity,
                                  duration: reduced || _spring
                                      ? Duration.zero
                                      : const Duration(milliseconds: 100),
                                  child: navigation,
                                ),
                        ),
                      ),
                      if (collapsed || revealOpacity > 0)
                        ExcludeSemantics(
                          excluding: !collapsed || revealOpacity < 1,
                          child: IgnorePointer(
                            ignoring: !collapsed || revealOpacity < 1,
                            child: Opacity(
                              opacity: revealOpacity,
                              child: Transform.translate(
                                offset: Offset(
                                  _spring
                                      ? (_anchor - (round - 8) / 2) *
                                            (1 - phase) *
                                            (Directionality.of(context) ==
                                                    TextDirection.ltr
                                                ? 1
                                                : -1)
                                      : 0,
                                  0,
                                ),
                                child: SizedBox(
                                  width: round - 8,
                                  height: round - 8,
                                  child: collapsedDestination,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final capsule = glass && nativeGlass == null
          ? DGlassBackdrop(
              backdropKey: null,
              child: LiquidGlassCapture(child: capsuleArtwork),
            )
          : capsuleArtwork;
      // Reserve the open footer extent while only its artwork morphs. This
      // keeps scroll clearance and anchors stable throughout a reversal.
      return _spring
          ? SizedBox(
              height: expandedExtent,
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: capsule,
              ),
            )
          : capsule;
    },
  );
}

class _DockRow extends MultiChildRenderObjectWidget {
  const _DockRow({
    required this.count,
    required this.actionExtent,
    required this.direction,
    required this.onOverflowChanged,
    required this.selected,
    required this.onAnchorChanged,
    required super.children,
  });
  final int count;
  final double actionExtent;
  final TextDirection direction;
  final ValueChanged<int> onOverflowChanged;
  final int selected;
  final ValueChanged<double> onAnchorChanged;
  @override
  _RenderDockRow createRenderObject(BuildContext context) => _RenderDockRow(
    count,
    actionExtent,
    direction,
    onOverflowChanged,
    selected,
    onAnchorChanged,
  );
  @override
  void updateRenderObject(BuildContext context, _RenderDockRow renderObject) {
    renderObject.update(
      count,
      actionExtent,
      direction,
      onOverflowChanged,
      selected,
      onAnchorChanged,
    );
  }
}

class _DockParentData extends ContainerBoxParentData<RenderBox> {
  bool visible = true;
}

class _RenderDockRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DockParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _DockParentData> {
  _RenderDockRow(
    this.count,
    this.actionExtent,
    this.direction,
    this.onOverflowChanged,
    this.selected,
    this.onAnchorChanged,
  );
  int count;
  double actionExtent;
  TextDirection direction;
  ValueChanged<int> onOverflowChanged;
  int selected;
  ValueChanged<double> onAnchorChanged;
  double? _reportedAnchor;
  int? _reported;
  int _shown = 0;
  void update(
    int nextCount,
    double nextExtent,
    TextDirection nextDirection,
    ValueChanged<int> callback,
    int nextSelected,
    ValueChanged<double> anchorCallback,
  ) {
    count = nextCount;
    actionExtent = nextExtent;
    direction = nextDirection;
    onOverflowChanged = callback;
    selected = nextSelected;
    onAnchorChanged = anchorCallback;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DockParentData) {
      child.parentData = _DockParentData();
    }
  }

  @override
  void performLayout() {
    final boxes = getChildrenAsList();
    final more = boxes[count];
    final action = boxes[count + 1];
    final width = constraints.maxWidth;
    final natural = boxes
        .take(count)
        .map(
          (b) => math.max(
            66.0,
            (b is RenderOffstage ? b.child! : b).getMaxIntrinsicWidth(
              double.infinity,
            ),
          ),
        )
        .toList();
    final actionMin = actionExtent;
    // The mockup's nav margin is 14px and its capsule row gap adds 4px.
    final gap = actionExtent > 0 ? 18.0 : 0.0;
    var shown = count;
    double widest(int n) => n == 0 ? 0 : natural.take(n).reduce(math.max);
    while (shown > 0 &&
        widest(shown) * shown + (shown < count ? 40 : 0) + actionMin + gap >
            width) {
      shown--;
    }
    // On narrow, enlarged-text screens the action and overflow remain reachable.
    final moreWidth = shown < count ? math.min(40.0, width) : 0.0;
    final navNatural = widest(shown) * shown + moreWidth;
    final availableActionWidth = (width - navNatural - gap)
        .clamp(math.min(actionMin, math.max(0, width - moreWidth - gap)), 220.0)
        .toDouble();
    final actionWidth = actionExtent == 0
        ? 0.0
        : availableActionWidth >= 116
        ? availableActionWidth
        : math.min(actionMin, math.max(0.0, width - moreWidth - gap));
    final navWidth = math.max(0.0, width - actionWidth - gap);
    final itemWidth = shown == 0
        ? 0.0
        : math.max(0.0, (navWidth - moreWidth) / shown);
    final anchor = selected >= 0 && selected < shown
        ? (selected + .5) * itemWidth
        : shown * itemWidth + moreWidth / 2;
    if (_reportedAnchor == null || (_reportedAnchor! - anchor).abs() > .5) {
      _reportedAnchor = anchor;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (attached) onAnchorChanged(anchor);
      });
    }
    var x = 0.0;
    var height = 0.0;
    void place(RenderBox box, double slot, bool visible) {
      box.layout(BoxConstraints.tightFor(width: slot), parentUsesSize: true);
      final data = box.parentData! as _DockParentData;
      data.visible = visible;
      data.offset = Offset(
        direction == TextDirection.ltr ? x : width - x - slot,
        0,
      );
      if (visible) {
        x += slot;
        height = math.max(height, box.size.height);
      }
    }

    for (var i = 0; i < count; i++) {
      place(boxes[i], i < shown ? itemWidth : natural[i], i < shown);
    }
    place(more, shown < count ? moreWidth : 40, shown < count);
    x = width - actionWidth;
    place(action, actionWidth, actionExtent > 0);
    for (final box in boxes) {
      final data = box.parentData! as _DockParentData;
      data.offset = Offset(data.offset.dx, (height - box.size.height) / 2);
    }
    size = constraints.constrain(Size(width, height));
    _shown = shown;
    if (_reported != shown) {
      _reported = shown;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (attached) onOverflowChanged(_shown);
      });
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final box in getChildrenAsList()) {
      final data = box.parentData! as _DockParentData;
      if (data.visible) context.paintChild(box, offset + data.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final box in getChildrenAsList().reversed) {
      final data = box.parentData! as _DockParentData;
      if (data.visible &&
          result.addWithPaintOffset(
            offset: data.offset,
            position: position,
            hitTest: (result, transformed) =>
                box.hitTest(result, position: transformed),
          )) {
        return true;
      }
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final box in getChildrenAsList()) {
      if ((box.parentData! as _DockParentData).visible) visitor(box);
    }
  }
}

/// The dock action reveals its label only when its own slot can carry it.
class DMobileDockAction extends StatelessWidget {
  const DMobileDockAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.buttonKey,
  });
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Key? buttonKey;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 116
        ? SizedBox(
            width: constraints.maxWidth,
            child: DButton(
              key: buttonKey,
              icon: icon,
              label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              tooltip: label,
              loading: loading,
              shape: DButtonShape.pill,
              density: DButtonDensity.mobileDockAction,
              onPressed: onPressed,
            ),
          )
        : Align(
            heightFactor: 1,
            alignment: AlignmentDirectional.centerEnd,
            child: DButton.iconOnly(
              key: buttonKey,
              icon: icon,
              tooltip: label,
              loading: loading,
              shape: DButtonShape.pill,
              density: DButtonDensity.mobileDockAction,
              onPressed: onPressed,
            ),
          ),
  );
}
