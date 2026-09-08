import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// Semantic styles from the frozen shadcn Typography reference.
enum DTextVariant {
  h1,
  h2,
  h3,
  h4,
  paragraph,
  lead,
  large,
  small,
  muted,
  inlineCode;

  int? get _headingLevel => switch (this) {
    h1 => 1,
    h2 => 2,
    h3 => 3,
    h4 => 4,
    _ => null,
  };
}

/// Native text with a semantic typography role and optional caller emphasis.
///
/// Uses shadcn's sizes, leading, weights and tracking, with the current theme's
/// font family and colors. The inherited text scaler remains authoritative.
/// Headings expose their level to accessibility.
/// h2 includes a bottom rule; inlineCode includes a padded, rounded background.
/// Other variants have no margins. Use [DProse] or ordinary layout for spacing.
///
/// Place a [SelectionArea] above a document to select across its text, lists,
/// and code. This widget does not create a second selection or focus owner.
/// [DText.rich] accepts ordinary spans; use focusable widgets in [WidgetSpan]s
/// for interactive content, since a gesture recognizer alone cannot take Tab
/// focus. The caller owns any recognizers, focus nodes, and callbacks.
class DText extends StatelessWidget {
  const DText(
    String this.data, {
    super.key,
    this.variant = DTextVariant.paragraph,
    this.style,
    this.textAlign = TextAlign.start,
    this.softWrap = true,
    this.maxLines,
    this.overflow,
    this.semanticsLabel,
    this.headingLevel,
  }) : textSpan = null,
       assert(maxLines == null || maxLines > 0),
       assert(headingLevel == null || (headingLevel >= 0 && headingLevel <= 6));

  const DText.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.variant = DTextVariant.paragraph,
    this.style,
    this.textAlign = TextAlign.start,
    this.softWrap = true,
    this.maxLines,
    this.overflow,
    this.semanticsLabel,
    this.headingLevel,
  }) : data = null,
       assert(maxLines == null || maxLines > 0),
       assert(headingLevel == null || (headingLevel >= 0 && headingLevel <= 6));

  final String? data;
  final InlineSpan? textSpan;
  final DTextVariant variant;

  /// Merged after the reference style for an intentional caller customization.
  final TextStyle? style;
  final TextAlign textAlign;
  final bool softWrap;
  final int? maxLines;
  final TextOverflow? overflow;
  final String? semanticsLabel;

  /// Overrides the heading variant's semantic level when visual size and
  /// document hierarchy differ. 1–6 declares a heading; 0 disables the inferred
  /// heading. Null uses h1–h4's level and leaves other variants as ordinary text.
  final int? headingLevel;

  Widget _balanceHeading(BuildContext context, TextStyle style, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth == 0) {
          return child;
        }
        final painter = TextPainter(
          text: TextSpan(
            text: data,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        );
        try {
          painter.layout(maxWidth: constraints.maxWidth);
          final lineCount = painter.computeLineMetrics().length;
          if (lineCount < 2 || lineCount > 6) return child;
          var lower = constraints.maxWidth / lineCount;
          var upper = constraints.maxWidth;
          // Preserve the natural line count while finding a compact measure,
          // the same principle as CSS text-wrap: balance for short headings.
          while (upper - lower > 0.25) {
            final candidate = (lower + upper) / 2;
            painter.layout(maxWidth: candidate);
            if (painter.computeLineMetrics().length > lineCount) {
              lower = candidate;
            } else {
              upper = candidate;
            }
          }
          return Align(
            alignment: switch (textAlign) {
              TextAlign.center => Alignment.center,
              TextAlign.end => AlignmentDirectional.centerEnd,
              TextAlign.left => Alignment.centerLeft,
              TextAlign.right => Alignment.centerRight,
              _ => AlignmentDirectional.centerStart,
            },
            child: SizedBox(width: upper, child: child),
          );
        } finally {
          painter.dispose();
        }
      },
    );
  }

  /// The reference's inherited 16px/24px body text for lists, quotes and tables.
  /// Paragraphs explicitly use the roomier 28px leading from `leading-7`.
  static TextStyle bodyStyleOf(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(
        fontSize: DiscourseTypography.base,
        height: DiscourseTypography.lineHeightBody,
        fontWeight: FontWeight.normal,
        letterSpacing: 0,
        color: DTokens.of(context).foreground,
      );

  /// Resolves an unscaled style for native spans or composed child widgets.
  ///
  /// Inline code spans keep a rectangular background so they can wrap and be
  /// selected within a paragraph. Use [DText] with inlineCode for a standalone
  /// padded, rounded label. Only code opts into the app's bundled monospace;
  /// all other families remain theme-owned. Metrics use the app's unscaled
  /// Tailwind tokens with the frozen reference's weights, leading and tracking.
  static TextStyle styleOf(BuildContext context, DTextVariant variant) {
    final text = Theme.of(context).textTheme;
    final tokens = DTokens.of(context);
    TextStyle resolve(
      TextStyle role,
      double size,
      double height, {
      FontWeight weight = FontWeight.normal,
      bool tight = false,
      Color? color,
    }) => role.copyWith(
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: tight ? size * DiscourseTypography.trackingTight : 0,
      color: color ?? tokens.foreground,
    );
    return switch (variant) {
      DTextVariant.h1 => resolve(
        text.headlineLarge!,
        DiscourseTypography.xxxxl,
        DiscourseTypography.lineHeightDisplayLarge,
        weight: FontWeight.w800,
        tight: true,
      ),
      DTextVariant.h2 => resolve(
        text.headlineMedium!,
        DiscourseTypography.xxxl,
        DiscourseTypography.lineHeightDisplaySmall,
        weight: FontWeight.w600,
        tight: true,
      ),
      DTextVariant.h3 => resolve(
        text.headlineSmall!,
        DiscourseTypography.xxl,
        DiscourseTypography.lineHeightHeading,
        weight: FontWeight.w600,
        tight: true,
      ),
      DTextVariant.h4 => resolve(
        text.titleLarge!,
        DiscourseTypography.xl,
        DiscourseTypography.lineHeightTitle,
        weight: FontWeight.w600,
        tight: true,
      ),
      DTextVariant.paragraph => resolve(
        text.bodyLarge!,
        DiscourseTypography.base,
        DiscourseTypography.lineHeightProse,
      ),
      DTextVariant.lead => resolve(
        text.titleLarge!,
        DiscourseTypography.xl,
        DiscourseTypography.lineHeightTitle,
        color: tokens.mutedForeground,
      ),
      DTextVariant.large => resolve(
        text.titleMedium!,
        DiscourseTypography.lg,
        DiscourseTypography.lineHeightLarge,
        weight: FontWeight.w600,
      ),
      DTextVariant.small => resolve(
        text.labelLarge!,
        DiscourseTypography.sm,
        1,
        weight: FontWeight.w500,
      ),
      DTextVariant.muted => resolve(
        text.bodyMedium!,
        DiscourseTypography.sm,
        DiscourseTypography.lineHeightSmall,
        color: tokens.mutedForeground,
      ),
      DTextVariant.inlineCode => resolve(
        text.bodyMedium!,
        DiscourseTypography.sm,
        DiscourseTypography.lineHeightSmall,
        weight: FontWeight.w600,
      ).copyWith(fontFamily: 'JetBrains Mono', backgroundColor: tokens.muted),
    };
  }

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = styleOf(context, variant).merge(style);
    Widget result = textSpan == null
        ? Text(
            data!,
            style: resolvedStyle,
            textAlign: textAlign,
            softWrap: softWrap,
            maxLines: maxLines,
            overflow: overflow,
            semanticsLabel: semanticsLabel,
          )
        : Text.rich(
            textSpan!,
            style: resolvedStyle,
            textAlign: textAlign,
            softWrap: softWrap,
            maxLines: maxLines,
            overflow: overflow,
            semanticsLabel: semanticsLabel,
          );

    final tokens = DTokens.of(context);
    if (variant == DTextVariant.h1 &&
        data != null &&
        softWrap &&
        maxLines == null) {
      result = _balanceHeading(context, resolvedStyle, result);
    }
    if (variant == DTextVariant.h2) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: DSpacing.sm),
          child: result,
        ),
      );
    } else if (variant == DTextVariant.inlineCode) {
      result = Align(
        widthFactor: 1,
        heightFactor: 1,
        alignment: switch (textAlign) {
          TextAlign.center => Alignment.center,
          TextAlign.end => AlignmentDirectional.centerEnd,
          TextAlign.left => Alignment.centerLeft,
          TextAlign.right => Alignment.centerRight,
          _ => AlignmentDirectional.centerStart,
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.muted,
            borderRadius: tokens.borderRadius,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.8, vertical: 3.2),
            child: result,
          ),
        ),
      );
    }
    if (headingLevel ?? variant._headingLevel case final level?
        when level > 0) {
      result = Semantics(headingLevel: level, child: result);
    }
    return result;
  }
}

/// A vertical document flow with the reference's inter-block spacing.
///
/// Adds no outer margin or selection owner. Children fill the available width
/// and grow with their text. The caller supplies bounded width and scrolling,
/// and may wrap this in its existing [SelectionArea]. Empty prose has no height.
class DProse extends StatelessWidget {
  const DProse({super.key, required this.children, this.spacing})
    : assert(spacing == null || spacing >= 0);

  final List<Widget> children;

  /// Overrides the default 24px gaps, 40px before h2 and 32px before h3.
  /// The first block has no leading gap.
  final double? spacing;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: DText.styleOf(context, DTextVariant.paragraph),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0)
            SizedBox(
              height:
                  spacing ??
                  switch (children[index]) {
                    DText(variant: DTextVariant.h2) => 40,
                    DText(variant: DTextVariant.h3) => 32,
                    _ => DSpacing.xl,
                  },
            ),
          children[index],
        ],
      ],
    ),
  );
}

/// A directional quote rule around caller-owned text or composed content.
///
/// Plain [Text] children inherit italic reading text. Explicit styles on child
/// widgets win, allowing attribution, links, or multiple paragraphs. No quote
/// text or accessibility label is inserted on the caller's behalf.
class DBlockquote extends StatelessWidget {
  const DBlockquote({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: BorderDirectional(
        start: BorderSide(color: DTokens.of(context).border, width: 2),
      ),
    ),
    child: Padding(
      padding: const EdgeInsetsDirectional.only(start: DSpacing.xl),
      child: DefaultTextStyle.merge(
        style: DText.bodyStyleOf(context).copyWith(fontStyle: FontStyle.italic),
        child: child,
      ),
    ),
  );
}

/// A wrapping, directional prose list with native list/item semantics.
///
/// Children can include nested lists and native controls. Ordered markers are
/// spoken; decorative bullets are excluded from semantics. Markers are excluded
/// from text selection so copying prose does not insert decorative characters.
/// Empty lists have no height. This is document composition, not a lazy list.
class DTextList extends StatelessWidget {
  const DTextList({
    super.key,
    required this.children,
    this.ordered = false,
    this.start = 1,
  }) : assert(start >= 1);

  final List<Widget> children;
  final bool ordered;
  final int start;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: DText.bodyStyleOf(context),
    child: Semantics(
      role: SemanticsRole.list,
      container: true,
      explicitChildNodes: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DSpacing.sm,
        children: [
          for (var index = 0; index < children.length; index++)
            Semantics(
              role: SemanticsRole.listItem,
              container: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: DSpacing.lg),
                    child: SelectionContainer.disabled(
                      child: ExcludeSemantics(
                        excluding: !ordered,
                        child: Text(
                          ordered ? '${start + index}.' : '•',
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: DSpacing.sm),
                  Expanded(child: children[index]),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
