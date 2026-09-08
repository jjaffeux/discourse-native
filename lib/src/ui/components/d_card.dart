import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

enum DCardSize { normal, small }

/// A passive surface. Actions, selection, loading and errors belong to children.
///
/// Parts inherit [spacing], the native equivalent of `--card-spacing`.
/// [leading] and [trailing] place images or other content against clipped edges.
/// A [footer] removes bottom padding. Children retain their native interaction
/// owners; the zero-elevation Material supports ink without creating an action.
class DCard extends StatelessWidget {
  const DCard({
    super.key,
    this.children = const [],
    this.child,
    this.size = DCardSize.normal,
    this.spacing,
    this.leading,
    this.trailing,
    this.footer,
  }) : assert(spacing == null || (spacing >= 0 && spacing < double.infinity));

  /// Full-surface composition, useful for an InkWell with caller-owned padding.
  final Widget? child;
  final List<Widget> children;
  final DCardSize size;
  final double? spacing;
  final Widget? leading;
  final Widget? trailing;
  final DCardFooter? footer;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final inset =
        spacing ?? (size == DCardSize.small ? DSpacing.md : DSpacing.lg);
    final parts = <Widget>[?leading, ?child, ...children, ?footer, ?trailing];
    final radius = BorderRadius.circular(tokens.radius * 1.4);
    return _CardScope(
      spacing: inset,
      size: size,
      child: Semantics(
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: tokens.foreground.withValues(alpha: .1),
                spreadRadius: 1,
              ),
            ],
          ),
          child: Material(
            animationDuration: Duration.zero,
            color: tokens.surface,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            textStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(
              fontSize: DiscourseTypography.sm,
              height: 20 / 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              color: tokens.foreground,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                top: leading == null ? inset : 0,
                bottom:
                    footer == null &&
                        !children.any((part) => part is DCardFooter) &&
                        trailing == null
                    ? inset
                    : 0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0 &&
                        !(parts[i - 1] is DCardContent &&
                            (parts[i - 1] as DCardContent).joinNext))
                      SizedBox(height: inset),
                    parts[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardScope extends InheritedWidget {
  const _CardScope({
    required this.spacing,
    required this.size,
    required super.child,
  });
  final double spacing;
  final DCardSize size;
  static _CardScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CardScope>();
  @override
  bool updateShouldNotify(_CardScope oldWidget) =>
      spacing != oldWidget.spacing || size != oldWidget.size;
}

double _spacing(BuildContext context) =>
    _CardScope.of(context)?.spacing ?? DSpacing.lg;

/// Title and description share the first column; action aligns at logical end.
/// At narrow widths the action wraps below, keeping large text readable.
class DCardHeader extends StatelessWidget {
  const DCardHeader({
    super.key,
    this.title,
    this.description,
    this.action,
    this.border = false,
  });
  final Widget? title;
  final Widget? description;
  final DCardAction? action;
  final bool border;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsetsDirectional.fromSTEB(
      _spacing(context),
      0,
      _spacing(context),
      border ? _spacing(context) : 0,
    ),
    decoration: border
        ? BoxDecoration(
            border: Border(
              bottom: BorderSide(color: DTokens.of(context).border),
            ),
          )
        : null,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final text = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?title,
            if (title != null && description != null)
              const SizedBox(height: DSpacing.xs),
            ?description,
          ],
        );
        if (action == null) return text;
        final stacked =
            constraints.maxWidth < 240 ||
            MediaQuery.textScalerOf(context).scale(14) > 21;
        // Keep the element topology stable when reflowing an interactive action.
        return Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(fit: stacked ? FlexFit.loose : FlexFit.tight, child: text),
            SizedBox(
              width: stacked ? 0 : DSpacing.xs,
              height: stacked ? DSpacing.xs : 0,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: stacked ? constraints.maxWidth : 0,
                maxWidth: constraints.maxWidth * (stacked ? 1 : .5),
              ),
              child: action!,
            ),
          ],
        );
      },
    ),
  );
}

class DCardTitle extends StatelessWidget {
  const DCardTitle({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyle(
      fontSize: _CardScope.of(context)?.size == DCardSize.small
          ? DiscourseTypography.sm
          : DiscourseTypography.base,
      height: 1.375,
      fontWeight: FontWeight.w500,
    ),
    child: child,
  );
}

class DCardDescription extends StatelessWidget {
  const DCardDescription({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyle(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      color: DTokens.of(context).mutedForeground,
    ),
    child: child,
  );
}

class DCardAction extends StatelessWidget {
  const DCardAction({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topEnd,
    widthFactor: 1,
    heightFactor: 1,
    child: child,
  );
}

/// [edgeToEdge] removes horizontal inset; [joinNext] removes the following gap.
/// Together these express the reference's negative shared-spacing margins.
class DCardContent extends StatelessWidget {
  const DCardContent({
    super.key,
    required this.child,
    this.edgeToEdge = false,
    this.joinNext = false,
  });
  final Widget child;
  final bool edgeToEdge;
  final bool joinNext;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: edgeToEdge ? 0 : _spacing(context),
    ),
    child: child,
  );
}

/// Footer children own their row, wrap or column composition.
class DCardFooter extends StatelessWidget {
  const DCardFooter({
    super.key,
    required this.child,
    this.border = true,
    this.muted = true,
  });
  final Widget child;
  final bool border;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Container(
      padding: EdgeInsets.all(_spacing(context)),
      decoration: BoxDecoration(
        color: muted ? tokens.muted.withValues(alpha: .5) : null,
        border: border ? Border(top: BorderSide(color: tokens.border)) : null,
      ),
      child: child,
    );
  }
}
