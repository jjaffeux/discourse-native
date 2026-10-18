import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/material_theme.dart';
import '../foundation/tokens.dart';
import 'd_avatar.dart';

/// A destination card shared by directories. The solid raised surface is the
/// same in Standard and Liquid Glass; it never refracts the text underneath.
/// Slots contain passive content. This component owns the single visible
/// target, keyboard activation, focus ring, hover lift and reduced motion.
class DPlaceCard extends StatefulWidget {
  const DPlaceCard({
    super.key,
    required this.leading,
    required this.title,
    required this.footer,
    required this.onPressed,
    this.description,
    this.unreadCount,
    this.semanticLabel,
    this.strong = false,
    this.muted = false,
    this.selected = false,
    this.focusNode,
  });

  final Widget leading;
  final Widget title;
  final Widget? description;
  final Widget footer;
  final String? unreadCount;
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
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onPressed != null;
    final lifted = enabled && _hovered && !widget.selected;
    final reduced = DMaterialTheme.reducedOf(context);
    const radius = BorderRadius.all(Radius.circular(12));
    final fill = widget.selected
        ? tokens.primary.withValues(alpha: .12)
        : (dark
                  ? Color.lerp(tokens.background, tokens.foreground, .1)!
                  : tokens.background)
              .withValues(
                alpha: reduced
                    ? 1
                    : dark
                    ? .72
                    : .82,
              );
    final ring = _focused
        ? tokens.focusRing
        : widget.selected
        ? tokens.primary
        : Colors.transparent;
    final text = widget.muted ? tokens.mutedForeground : tokens.foreground;
    Widget content = AnimatedContainer(
      duration: DMotion.duration(context, const Duration(milliseconds: 200)),
      curve: Curves.ease,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: fill,
        boxShadow: widget.selected || !enabled
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: dark ? (lifted ? .16 : .14) : (lifted ? .07 : .06),
                  ),
                  offset: Offset(0, lifted ? 2 : 1),
                  blurRadius: lifted ? 4 : 2,
                ),
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: dark ? (lifted ? .18 : .12) : (lifted ? .10 : .06),
                  ),
                  offset: Offset(0, lifted ? 10 : 4),
                  blurRadius: lifted ? 24 : 14,
                ),
              ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: ring, width: _focused ? 2 : 1),
      ),
      child: CustomPaint(
        foregroundPainter: _PlaceHighlight(
          widget.selected
              ? Colors.transparent
              : Colors.white.withValues(
                  alpha: dark ? (lifted ? .09 : .06) : .9,
                ),
        ),
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
                        widget.leading,
                        const SizedBox(width: 9),
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
              DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DiscourseTypography.xs,
                  height: 1.5,
                  color: Color.lerp(tokens.background, tokens.foreground, .4),
                  fontWeight: FontWeight.w400,
                ),
                child: widget.footer,
              ),
            ],
          ),
        ),
      ),
    );
    content = _PlaceHitShape(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: widget.onPressed,
        child: content,
      ),
    );
    // Transform paint and input together. Shadows do not own input, and the
    // inter-card gutters never forward a tap to a neighbouring destination.
    return Semantics(
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
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              end: lifted && !MediaQuery.disableAnimationsOf(context) ? -1 : 0,
            ),
            duration: DMotion.duration(
              context,
              const Duration(milliseconds: 250),
            ),
            curve: const Cubic(.34, 1.56, .64, 1),
            builder: (context, y, child) =>
                Transform.translate(offset: Offset(0, y), child: child),
            child: content,
          ),
        ),
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

/// A lazy, auto-fill directory grid with equal-height cards in each row.
/// Cards measure normally; a second tight layout aligns their footers without
/// intrinsic probes or constructing the entire directory during scrolling.
class DPlaceCardGrid extends StatelessWidget {
  const DPlaceCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final scale = math.max(
        1.0,
        MediaQuery.textScalerOf(context).scale(14) / 14,
      );
      final columns = math.max(
        1,
        ((constraints.crossAxisExtent + 10) / (236 * scale + 10)).floor(),
      );
      return SliverList.builder(
        itemCount: (itemCount / columns).ceil(),
        itemBuilder: (context, row) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _PlaceRow(
            columns: columns,
            direction: Directionality.of(context),
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
    },
  );
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

class _PlaceHighlight extends CustomPainter {
  const _PlaceHighlight(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final shape = BorderRadius.circular(12).toRRect(Offset.zero & size);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRRect(shape),
        Path()..addRRect(shape.shift(const Offset(0, 1))),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PlaceHighlight old) => color != old.color;
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
      ..direction = direction
      ..markNeedsLayout();
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
  _PlaceRowLayout(this.columns, this.direction);
  int columns;
  TextDirection direction;
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
