import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../foundation/tokens.dart';

/// Semantic styles from the frozen Typography reference, using host text roles.
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
/// Uses the current [ThemeData.textTheme] without changing its sizes, leading,
/// or the inherited text scaler. Headings expose their level to accessibility.
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

  /// Merged after the semantic role. Prefer color/emphasis overrides; numeric
  /// sizes and line heights belong in the host's typography theme.
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

  /// Resolves an unscaled style for native spans or composed child widgets.
  ///
  /// Inline code spans keep a rectangular background so they can wrap and be
  /// selected within a paragraph. Use [DText] with inlineCode for a standalone
  /// padded, rounded label. Only code opts into the app's bundled monospace;
  /// all other families, sizes, and heading weights remain theme-owned.
  static TextStyle styleOf(BuildContext context, DTextVariant variant) {
    final text = Theme.of(context).textTheme;
    final tokens = DTokens.of(context);
    return switch (variant) {
      DTextVariant.h1 => text.headlineLarge!,
      DTextVariant.h2 => text.headlineMedium!,
      DTextVariant.h3 => text.headlineSmall!,
      DTextVariant.h4 => text.titleLarge!,
      DTextVariant.paragraph => text.bodyLarge!,
      DTextVariant.lead => text.titleLarge!.copyWith(
        fontWeight: FontWeight.normal,
        color: tokens.mutedForeground,
      ),
      DTextVariant.large => text.titleMedium!,
      DTextVariant.small => text.labelLarge!,
      DTextVariant.muted => text.bodyMedium!.copyWith(
        color: tokens.mutedForeground,
      ),
      DTextVariant.inlineCode => text.bodyMedium!.copyWith(
        fontFamily: 'JetBrains Mono',
        fontWeight: FontWeight.w600,
        backgroundColor: tokens.muted,
      ),
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
            padding: const EdgeInsets.symmetric(
              horizontal: DSpacing.xs,
              vertical: DSpacing.xs / 2,
            ),
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

/// A vertical document flow with reading text and explicit inter-block spacing.
///
/// Adds no outer margin or selection owner. Children fill the available width
/// and grow with their text. The caller supplies bounded width and scrolling,
/// and may wrap this in its existing [SelectionArea]. Empty prose has no height.
class DProse extends StatelessWidget {
  const DProse({super.key, required this.children, this.spacing = DSpacing.xl})
    : assert(spacing >= 0);

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: DText.styleOf(context, DTextVariant.paragraph),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: spacing,
      children: children,
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
        style: DText.styleOf(
          context,
          DTextVariant.paragraph,
        ).copyWith(fontStyle: FontStyle.italic),
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
    style: DText.styleOf(context, DTextVariant.paragraph),
    child: Semantics(
      role: SemanticsRole.list,
      container: true,
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: DSpacing.lg),
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
                    SelectionContainer.disabled(
                      child: ExcludeSemantics(
                        excluding: !ordered,
                        child: Text(ordered ? '${start + index}.' : '•'),
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
    ),
  );
}
