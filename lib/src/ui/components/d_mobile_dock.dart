import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_mobile_dock_geometry.dart';

/// A phone's bar, cut as its [DMobileDockGeometry] says, whose destinations
/// divide the space left by its action. Natural label and badge widths
/// determine overflow before the row is painted. Folded, it is a circle in
/// the screen's bottom-start corner.
class DMobileDock extends StatefulWidget {
  const DMobileDock({
    super.key,
    required this.geometry,
    required this.destinations,
    required this.more,
    required this.collapsedDestination,
    required this.onOverflowChanged,
    this.action,
    this.collapsed = false,
    this.destinationsHidden = false,
  });

  final DMobileDockGeometry geometry;
  final List<Widget> destinations;
  final Widget more;
  final Widget collapsedDestination;
  final Widget? action;
  final bool collapsed;
  final bool destinationsHidden;
  final ValueChanged<int> onOverflowChanged;

  /// Around the folded circle's own button.
  static const circlePadding = 4.0;

  @override
  State<DMobileDock> createState() => _DMobileDockState();
}

class _DMobileDockState extends State<DMobileDock> {
  int? _shown;
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

  Widget _destination(Widget child) => ExcludeSemantics(
    excluding: destinationsHidden,
    child: IgnorePointer(
      ignoring: destinationsHidden,
      child: Opacity(opacity: destinationsHidden ? 0 : 1, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final reduced = MediaQuery.disableAnimationsOf(context);
      final geometry = widget.geometry;
      final round = geometry.circle;
      final navOpacity = (collapsed ? 0.0 : 1.0);
      final revealOpacity = (collapsed ? 1.0 : 0.0);
      final radius = BorderRadius.circular(999);
      final tokens = DTokens.of(context);

      final well = tokens.wellFill;
      final navigation = OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: constraints.maxWidth - geometry.padding.horizontal,
        maxWidth: constraints.maxWidth - geometry.padding.horizontal,
        maxHeight: geometry.rowHeight,
        child: _DockRow(
          direction: Directionality.of(context),
          onOverflowChanged: _overflow,
          count: destinations.length,
          actionExtent: action == null ? 0 : geometry.rowHeight,
          children: [
            for (final (index, item) in destinations.indexed)
              Offstage(
                offstage: index >= (_shown ?? destinations.length),
                child: _destination(item),
              ),
            Offstage(
              offstage: _shown == destinations.length,
              child: _destination(more),
            ),
            if (action != null) action! else const SizedBox.shrink(),
          ],
        ),
      );
      // The circle's corner is measured from the screen's edges; the bar's
      // own margin already keeps part of that distance.
      final corner = geometry.cornerAt(round) - geometry.reach;
      final capsuleArtwork = AnimatedPadding(
        padding: collapsed
            ? EdgeInsetsDirectional.only(start: corner, bottom: corner)
            : EdgeInsetsDirectional.zero,
        duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
        curve: const Cubic(.32, .72, 0, 1),
        child: AnimatedContainer(
          key: const ValueKey('mobile-dock-surface'),
          duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
          curve: const Cubic(.32, .72, 0, 1),
          width: collapsed ? round : constraints.maxWidth,
          height: collapsed ? round : geometry.barHeight,
          decoration: BoxDecoration(
            color: well,
            borderRadius: collapsed
                ? BorderRadius.circular(round / 2)
                : geometry.borderRadius,
          ),
          child: AnimatedPadding(
            key: const ValueKey('mobile-dock-controls'),
            padding: collapsed
                ? const EdgeInsets.all(DMobileDock.circlePadding)
                : geometry.padding,
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 420),
            curve: const Cubic(.32, .72, 0, 1),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  ExcludeSemantics(
                    excluding: collapsed || navOpacity < 1,
                    child: IgnorePointer(
                      ignoring: collapsed || navOpacity < 1,
                      child: AnimatedOpacity(
                        opacity: navOpacity,
                        duration: reduced
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
                          child: SizedBox(
                            width: round - 2 * DMobileDock.circlePadding,
                            height: round - 2 * DMobileDock.circlePadding,
                            child: collapsedDestination,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      return SizedBox(
        height: geometry.barHeight,
        child: Align(
          alignment: AlignmentDirectional.bottomStart,
          child: capsuleArtwork,
        ),
      );
    },
  );
}

class _DockRow extends MultiChildRenderObjectWidget {
  const _DockRow({
    required this.count,
    required this.actionExtent,
    required this.direction,
    required this.onOverflowChanged,
    required super.children,
  });
  final int count;
  final double actionExtent;
  final TextDirection direction;
  final ValueChanged<int> onOverflowChanged;
  @override
  _RenderDockRow createRenderObject(BuildContext context) =>
      _RenderDockRow(count, actionExtent, direction, onOverflowChanged);
  @override
  void updateRenderObject(BuildContext context, _RenderDockRow renderObject) {
    renderObject.update(count, actionExtent, direction, onOverflowChanged);
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
  );
  int count;
  double actionExtent;
  TextDirection direction;
  ValueChanged<int> onOverflowChanged;
  int? _reported;
  int _shown = 0;
  void update(
    int nextCount,
    double nextExtent,
    TextDirection nextDirection,
    ValueChanged<int> callback,
  ) {
    count = nextCount;
    actionExtent = nextExtent;
    direction = nextDirection;
    onOverflowChanged = callback;
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

/// The dock action reveals its label only when its own slot can carry it. It
/// takes the primary button colours, as a composer's send button does.
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
  Widget build(BuildContext context) {
    final colors = DTokens.of(context).buttonTheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 116
          ? SizedBox(
              width: constraints.maxWidth,
              child: DButton(
                key: buttonKey,
                icon: icon,
                label: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                tooltip: label,
                loading: loading,
                shape: DButtonShape.pill,
                density: DButtonDensity.mobileDockAction,
                foregroundColor: colors.foreground,
                backgroundColor: colors.background,
                interactiveBackgroundColor: colors.hover,
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
                foregroundColor: colors.foreground,
                backgroundColor: colors.background,
                interactiveBackgroundColor: colors.hover,
                onPressed: onPressed,
              ),
            ),
    );
  }
}
