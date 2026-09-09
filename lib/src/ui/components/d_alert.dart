import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

enum DAlertVariant { normal, destructive }

/// A passive inline callout. Children own actions, focus and async state.
///
/// [liveRegion] requests a platform live announcement when content changes;
/// set it false for historical/static notices. It never moves keyboard focus.
/// Colors are optional equivalents of reference custom classes. Resolve them
/// during build so host palette changes continue to reach the callout.
class DAlert extends StatelessWidget {
  const DAlert({
    super.key,
    this.icon,
    this.title,
    this.description,
    this.action,
    this.variant = DAlertVariant.normal,
    this.liveRegion = true,
    this.backgroundColor,
    this.foregroundColor,
    this.descriptionColor,
    this.borderColor,
  });

  final Widget? icon;
  final DAlertTitle? title;
  final DAlertDescription? description;
  final DAlertAction? action;
  final DAlertVariant variant;
  final bool liveRegion;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? descriptionColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final destructive = variant == DAlertVariant.destructive;
    final foreground =
        foregroundColor ??
        (destructive ? tokens.destructive : tokens.foreground);
    final secondary =
        descriptionColor ??
        (destructive
            ? tokens.destructive.withValues(alpha: tokens.destructive.a * .9)
            : tokens.mutedForeground);
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor ?? tokens.surface,
          border: Border.all(color: borderColor ?? tokens.border),
          borderRadius: BorderRadius.circular(tokens.radius),
        ),
        child: _AlertColors(
          description: secondary,
          child: DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: foreground,
              fontSize: DiscourseTypography.sm,
              height: 20 / 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
            textAlign: TextAlign.start,
            child: IconTheme.merge(
              data: IconThemeData(size: 16, color: foreground),
              child: _AlertLayout(
                direction: Directionality.of(context),
                minimumTextWidth:
                    160 * MediaQuery.textScalerOf(context).scale(14) / 14,
                action: action,
                content: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: ExcludeSemantics(child: icon!),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ?title,
                          if (title != null && description != null)
                            const SizedBox(height: 2),
                          ?description,
                        ],
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
  }
}

class DAlertTitle extends StatelessWidget {
  const DAlertTitle({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: const TextStyle(fontWeight: FontWeight.w500),
    child: child,
  );
}

/// Rich content can compose paragraphs with 16px gaps, lists and inline links.
/// Links retain their own gesture/focus owner and underline styling.
class DAlertDescription extends StatelessWidget {
  const DAlertDescription({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyle(
      color:
          context
              .dependOnInheritedWidgetOfExactType<_AlertColors>()
              ?.description ??
          DTokens.of(context).mutedForeground,
      fontWeight: FontWeight.w400,
    ),
    child: child,
  );
}

/// Places caller-owned controls at the logical top end. Moves below the content
/// when reserving their measured width would make the text column too narrow.
class DAlertAction extends StatelessWidget {
  const DAlertAction({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class _AlertColors extends InheritedWidget {
  const _AlertColors({required this.description, required super.child});
  final Color description;
  @override
  bool updateShouldNotify(_AlertColors oldWidget) =>
      description != oldWidget.description;
}

class _AlertLayout extends MultiChildRenderObjectWidget {
  _AlertLayout({
    required Widget content,
    Widget? action,
    required this.direction,
    required this.minimumTextWidth,
  }) : super(children: [content, ?action]);
  final TextDirection direction;
  final double minimumTextWidth;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAlertLayout(direction, minimumTextWidth);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAlertLayout renderObject,
  ) {
    renderObject
      ..direction = direction
      ..minimumTextWidth = minimumTextWidth
      ..markNeedsLayout();
  }
}

class _RenderAlertLayout extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderAlertLayout(this.direction, this.minimumTextWidth);
  TextDirection direction;
  double minimumTextWidth;
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _AlertParentData();
    }
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final content = firstChild!;
    final action = childAfter(content);
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 448.0;
    final inner = math.max(0.0, width - 22);
    Size measure(RenderBox child, BoxConstraints c) {
      if (dry) return child.getDryLayout(c);
      child.layout(c, parentUsesSize: true);
      return child.size;
    }

    final actionSize = action == null
        ? Size.zero
        : measure(action, BoxConstraints(maxWidth: inner));
    // Source reserves 72px from the border's inside edge. Wider native actions
    // reserve their real hit bounds instead of overlapping text.
    final reserve = action == null ? 0.0 : math.max(62.0, actionSize.width + 6);
    final stacked = action != null && inner - reserve < minimumTextWidth;
    final contentSize = measure(
      content,
      BoxConstraints.tightFor(
        width: stacked ? inner : math.max(0.0, inner - reserve),
      ),
    );
    final height = stacked
        ? 18.0 + contentSize.height + 8 + actionSize.height
        : 18.0 + math.max(contentSize.height, actionSize.height);
    if (!dry) {
      (content.parentData! as ContainerBoxParentData<RenderBox>)
          .offset = Offset(
        direction == TextDirection.ltr ? 11 : width - 11 - contentSize.width,
        9,
      );
      if (action != null) {
        (action.parentData! as ContainerBoxParentData<RenderBox>).offset =
            Offset(
              direction == TextDirection.ltr ? width - 9 - actionSize.width : 9,
              stacked ? 9 + contentSize.height + 8 : 9,
            );
      }
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() => size = _layout(constraints, dry: false);
  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, dry: true);
  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _AlertParentData extends ContainerBoxParentData<RenderBox> {}
