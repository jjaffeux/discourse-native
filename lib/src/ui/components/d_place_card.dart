import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/surface_depth.dart';
import '../foundation/tokens.dart';
import 'd_avatar.dart';
import 'd_skeleton.dart';

/// A destination card standing off its panel, shared by directories.
/// Slots contain passive content, except [trailing] and [action]. This
/// component owns the card's target, keyboard activation, focus ring, hover
/// lift and reduced motion.
class DPlaceCard extends StatefulWidget {
  const DPlaceCard({
    super.key,
    this.leading,
    required this.title,
    required this.footer,
    required this.onPressed,
    this.description,
    this.unreadCount,
    this.trailing,
    this.action,
    this.semanticLabel,
    this.strong = false,
    this.muted = false,
    this.selected = false,
    this.focusNode,
  });

  final Widget? leading;
  final Widget title;
  final Widget? description;
  final Widget footer;
  final String? unreadCount;

  /// A compact control after the title row, such as a menu button. It keeps
  /// its own target, focus and semantics inside the card's node.
  final Widget? trailing;

  /// A control at the footer's end, such as Join. The footer text yields to it.
  final Widget? action;
  final String? semanticLabel;
  final bool strong;
  final bool muted;
  final bool selected;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  State<DPlaceCard> createState() => _DPlaceCardState();
}

class _DPlaceCardState extends State<DPlaceCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onPressed != null;

    const radius = BorderRadius.all(Radius.circular(12));
    final fill = widget.selected
        ? tokens.primary.withValues(alpha: .12)
        : (dark
                  ? Color.lerp(tokens.background, tokens.foreground, .1)!
                  : tokens.background)
              .withValues(alpha: dark ? .72 : .82);
    final ring = _focused
        ? tokens.focusRing
        : widget.selected
        ? tokens.primary
        : Colors.transparent;
    final text = widget.muted ? tokens.mutedForeground : tokens.foreground;
    final footer = DefaultTextStyle.merge(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: DiscourseTypography.xs,
        height: 1.5,
        color: Color.lerp(tokens.background, tokens.foreground, .4),
        fontWeight: FontWeight.w400,
      ),
      child: widget.footer,
    );
    Widget surface(DSurfaceEdges? edges) => AnimatedContainer(
      duration: DMotion.duration(context, const Duration(milliseconds: 200)),
      curve: Curves.ease,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: fill,
        boxShadow: const [],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: ring, width: _focused ? 2 : 1),
      ),
      child: CustomPaint(
        painter: edges?.insetPainter(radius),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: text, letterSpacing: 0),
          child: _PlaceContents(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (widget.leading case final leading?) ...[
                          leading,
                          const SizedBox(width: 9),
                        ],
                        Expanded(
                          child: DefaultTextStyle.merge(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: DiscourseTypography.sm,
                              height: 18 / 14,
                              fontWeight: widget.strong
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                            child: widget.title,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.unreadCount case final count?)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 4,
                        top: 2,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            tokens.background,
                            tokens.primary,
                            .25,
                          ),
                          borderRadius: BorderRadius.circular(DRadius.pill),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            count,
                            style: TextStyle(
                              color: Color.lerp(
                                tokens.foreground,
                                tokens.primary,
                                .5,
                              ),
                              fontSize: DiscourseTypography.metadata,
                              height: 16 / 11.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (widget.trailing case final trailing?)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 4),
                      child: trailing,
                    ),
                ],
              ),
              DefaultTextStyle.merge(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DiscourseTypography.preview,
                  height: 1.38,
                  color: Color.lerp(
                    tokens.background,
                    tokens.foreground,
                    widget.strong && !widget.muted ? .9 : .5,
                  ),
                  fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
                  fontFamilyFallback: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.fontFamilyFallback,
                  fontWeight: widget.strong ? FontWeight.w600 : FontWeight.w400,
                ),
                child: widget.description ?? const SizedBox.shrink(),
              ),
              switch (widget.action) {
                final action? => Row(
                  children: [
                    Expanded(child: footer),
                    const SizedBox(width: 8),
                    action,
                  ],
                ),
                null => footer,
              },
            ],
          ),
        ),
      ),
    );
    // A chosen card is marked by its ring instead and lies on the panel.
    final raised = _hovered && !widget.selected;
    final rest = DSurfaceEdges.resolve(context, DSurfaceDepth.place);
    final lifted = DSurfaceEdges.resolve(context, DSurfaceDepth.placeHovered);
    Widget content = TweenAnimationBuilder<double>(
      tween: Tween(end: raised ? 1 : 0),
      duration: DMotion.duration(context, const Duration(milliseconds: 200)),
      curve: Curves.ease,
      builder: (context, t, _) {
        final edges = widget.selected
            ? null
            : DSurfaceEdges.lerp(rest, lifted, t);
        return CustomPaint(
          painter: edges?.castPainter(radius),
          child: surface(edges),
        );
      },
    );
    content = TweenAnimationBuilder<double>(
      tween: Tween(end: raised ? -1 : 0),
      duration: DMotion.duration(context, const Duration(milliseconds: 250)),
      curve: const Cubic(.34, 1.56, .64, 1),
      builder: (context, lift, child) =>
          Transform.translate(offset: Offset(0, lift), child: child),
      child: content,
    );
    content = _PlaceHitShape(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: widget.onPressed,
        child: content,
      ),
    );
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: widget.selected ? true : null,
      label: widget.semanticLabel,
      onTap: widget.onPressed,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: widget.focusNode,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: content,
      ),
    );
  }
}

/// The directory's 29px tinted identity tile, independent of card activation.
class DPlaceCardMark extends StatelessWidget {
  const DPlaceCardMark({super.key, required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => DAvatar(
    dimension: 29,
    border: false,
    decorative: true,
    borderRadius: BorderRadius.circular(9),
    fallback: DAvatarFallback(
      backgroundColor: Color.lerp(DTokens.of(context).background, color, .2),
      child: IconTheme.merge(
        data: IconThemeData(size: 13, color: color),
        child: child,
      ),
    ),
  );
}

/// A loading card with the same geometry as a loaded one. Place it inside a
/// [DSkeletonRegion] so every placeholder shares one pulse.
class DPlaceCardSkeleton extends StatelessWidget {
  const DPlaceCardSkeleton({super.key, this.action = false});

  /// Reserves a pill at the footer's end for directories whose cards act.
  final bool action;

  @override
  Widget build(BuildContext context) => DPlaceCard(
    onPressed: null,
    leading: DSkeleton(
      width: 29,
      height: 29,
      borderRadius: BorderRadius.circular(9),
    ),
    title: const FractionallySizedBox(
      widthFactor: .65,
      alignment: AlignmentDirectional.centerStart,
      child: DSkeleton(height: 14),
    ),
    description: const Column(
      spacing: 6,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DSkeleton(height: 12),
        FractionallySizedBox(widthFactor: .8, child: DSkeleton(height: 12)),
      ],
    ),
    footer: const Align(
      alignment: AlignmentDirectional.centerStart,
      child: DSkeleton(width: 90, height: 12),
    ),
    action: action
        ? DSkeleton(
            width: 56,
            height: 24,
            borderRadius: BorderRadius.circular(DRadius.pill),
          )
        : null,
  );
}

/// A lazy, auto-fill directory grid with equal-height cards in each row.
/// Cards measure normally; a second tight layout aligns their footers without
/// intrinsic probes or constructing the entire directory during scrolling.
class DPlaceCardGrid extends StatefulWidget {
  const DPlaceCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Placeholders fill whole rows by asking how many cards one row holds.
  static int columnsFor(BuildContext context, double width) =>
      _columns(MediaQuery.textScalerOf(context), width);

  static int _columns(TextScaler textScaler, double width) {
    final scale = math.max(1.0, textScaler.scale(14) / 14);
    return math.max(1, ((width + 10) / (236 * scale + 10)).floor());
  }

  @override
  State<DPlaceCardGrid> createState() => _DPlaceCardGridState();
}

class _DPlaceCardGridState extends State<DPlaceCardGrid> {
  // Sliver constraints change with every scroll offset. Handing back the same
  // list while the column count holds keeps scrolling from rebuilding,
  // relaying out and repainting every visible card.
  ({int columns, Widget sliver})? _built;

  @override
  Widget build(BuildContext context) {
    _built = null;
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final itemCount = widget.itemCount;
    final itemBuilder = widget.itemBuilder;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = DPlaceCardGrid._columns(
          textScaler,
          constraints.crossAxisExtent,
        );
        if (_built case (
          columns: final built,
          :final sliver,
        ) when built == columns) {
          return sliver;
        }
        final sliver = SliverList.builder(
          itemCount: (itemCount / columns).ceil(),
          itemBuilder: (context, row) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PlaceRow(
              columns: columns,
              direction: direction,
              children: [
                for (
                  var index = row * columns;
                  index < math.min(itemCount, (row + 1) * columns);
                  index++
                )
                  itemBuilder(context, index),
              ],
            ),
          ),
        );
        _built = (columns: columns, sliver: sliver);
        return sliver;
      },
    );
  }
}

class _PlaceHitShape extends SingleChildRenderObjectWidget {
  const _PlaceHitShape({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PlaceHitShapeLayout();
}

class _PlaceHitShapeLayout extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      BorderRadius.circular(
        12,
      ).toRRect(Offset.zero & size).contains(position) &&
      super.hitTest(result, position: position);
}

class _PlaceParentData extends ContainerBoxParentData<RenderBox> {}

class _PlaceContents extends MultiChildRenderObjectWidget {
  const _PlaceContents({required super.children});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PlaceContentsLayout();
}

class _PlaceContentsLayout extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  @override
  void setupParentData(RenderBox child) =>
      child.parentData = _PlaceParentData();
  @override
  void performLayout() {
    final parts = getChildrenAsList();
    final width = constraints.maxWidth;
    for (final part in parts) {
      part.layout(
        BoxConstraints.tightFor(width: math.max(0, width - 24)),
        parentUsesSize: true,
      );
    }
    final hasDescription = parts[1].size.height > 0;
    final naturalHeight =
        22 +
        parts[0].size.height +
        parts[1].size.height +
        parts[2].size.height +
        (hasDescription ? 14 : 7);
    size = constraints.constrain(Size(width, math.max(100, naturalHeight)));
    (parts[0].parentData! as ContainerBoxParentData<RenderBox>).offset =
        const Offset(12, 11);
    (parts[1].parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      12,
      18 + parts[0].size.height,
    );
    (parts[2].parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      12,
      size.height - 11 - parts[2].size.height,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _PlaceRow extends MultiChildRenderObjectWidget {
  const _PlaceRow({
    required this.columns,
    required this.direction,
    required super.children,
  });
  final int columns;
  final TextDirection direction;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PlaceRowLayout(columns, direction);
  @override
  void updateRenderObject(BuildContext context, _PlaceRowLayout renderObject) {
    renderObject
      ..columns = columns
      ..direction = direction;
  }
}

class _PlaceRowLayout extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _PlaceRowLayout(this._columns, this._direction);

  int _columns;
  int get columns => _columns;
  set columns(int value) {
    if (value == _columns) return;
    _columns = value;
    markNeedsLayout();
  }

  TextDirection _direction;
  TextDirection get direction => _direction;
  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) =>
      child.parentData = _PlaceParentData();
  @override
  void performLayout() {
    final width = math.max(
      0.0,
      (constraints.maxWidth - 10 * (columns - 1)) / columns,
    );
    var height = 0.0;
    final cards = getChildrenAsList();
    for (final card in cards) {
      card.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      height = math.max(height, card.size.height);
    }
    size = constraints.constrain(Size(constraints.maxWidth, height));
    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      card.layout(
        BoxConstraints.tight(Size(width, height)),
        parentUsesSize: true,
      );
      (card.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
        direction == TextDirection.ltr
            ? i * (width + 10)
            : size.width - width - i * (width + 10),
        0,
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
