/// The chip a mention or a hashtag is drawn as.
///
/// Discourse gives all three — `a.mention`, `a.mention-group` and
/// `.hashtag-cooked` — the same `@mixin mention`, which is the strongest signal
/// available that they are one visual idea rather than three that happen to
/// look alike. So they are one widget here.
///
/// Every dimension is a *ratio* of the prose the pill sits in rather than a
/// pixel count, for the reason `emojiScale` gives: the stylesheet fixes these
/// against a 15px body, and here the surrounding style varies — a post is
/// `bodyMedium`, a chat message, an onebox body and a user card bio are
/// smaller.
///
/// Deliberately knows nothing about the DOM, the shell or any model: the
/// composer draws pills too, and must not import `package:html` to do it.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';

/// `font-size: 0.93em`, against the prose around the pill.
const double pillScale = 0.93;

/// `padding: 0.2em 0.34em`. Every measurement below this line is against the
/// *pill's* own font size, which is what `em` means inside the mixin.
const double pillPadX = 0.34;
const double pillPadY = 0.2;

/// `border-radius: 0.6em`.
const double pillRadius = 0.6;

/// `.hashtag-category-square` — `width: 0.72em`, plus its `margin-left: 0.1em`.
const double pillSquare = 0.72;
const double pillSquareInset = 0.1;

/// What an `svg` or an `img.emoji` inside a pill is drawn at.
const double pillGlyph = 0.93;

/// `margin-right: var(--space-1)` — 4px, which against the 13.95px a pill's
/// text comes out at on a 15px body is this.
const double pillGap = 0.287;

/// One pill: optional leading art, then the label.
///
/// [onTap] is null in the composer, where [EditableText] owns pointer handling
/// and the composer resolves the pill's exact render-box geometry itself.
class Pill extends StatefulWidget {
  const Pill({
    super.key,
    required this.label,
    required this.baseStyle,
    this.leading,
    this.onTap,
    this.hoverable = false,
    this.highlighted = false,
  });

  final String label;

  /// The prose around the pill. Everything is sized from it.
  final TextStyle? baseStyle;

  /// Drawn ahead of the label, already sized by the caller — a category square,
  /// a [DIcon], or an emoji. Wrapped in [ExcludeSemantics] here rather than at
  /// each call site: an icon-font glyph announces as a stray codepoint, and the
  /// label beside it already says the same thing properly.
  final Widget? leading;

  final VoidCallback? onTap;

  /// Whether this pill is actionable through an owning widget such as an
  /// editable, rather than through [onTap] itself.
  final bool hoverable;

  /// A keyboard focus ring for projected composer items.
  final bool highlighted;

  /// The pill's own font size, which every other measurement is taken against.
  static double fontSizeFor(TextStyle? baseStyle) =>
      (baseStyle?.fontSize ?? 14) * pillScale;

  /// The box a [DIcon] needs for its *glyph* to come out at [pillGlyph].
  ///
  /// [DIcon.size] is the square the glyph is centred in, not the glyph itself.
  static double iconBoxFor(TextStyle? baseStyle) =>
      fontSizeFor(baseStyle) * pillGlyph / DIcon.glyphScale;

  @override
  State<Pill> createState() => _PillState();
}

class _PillState extends State<Pill> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  void didUpdateWidget(Pill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hoverable && widget.onTap == null) _hovered = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = Pill.fontSizeFor(widget.baseStyle);
    final radius = BorderRadius.circular(size * pillRadius);
    final background = _hovered
        ? Color.alphaBlend(
            theme.colorScheme.onSurface.withValues(alpha: 0.08),
            theme.shell.mention,
          )
        : theme.shell.mention;

    final pill = Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * pillPadX,
        vertical: size * pillPadY,
      ),
      decoration: BoxDecoration(color: background, borderRadius: radius),
      foregroundDecoration: widget.highlighted
          ? BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary, width: 1.5),
              borderRadius: radius,
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.leading case final leading?) ...[
            ExcludeSemantics(child: leading),
            SizedBox(width: size * pillGap),
          ],
          // Flexible, so a label longer than the line it is on is cut rather
          // than overflowing the Row and throwing. A name that long is
          // pathological — but it comes from the site rather than from us, and
          // a post is not where that should be discovered.
          Flexible(
            child: Text(
              widget.label,
              // `text-wrap: nowrap`. A pill broken across two lines reads as
              // two pills; past the end of the line it is cut instead.
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: (widget.baseStyle ?? const TextStyle()).copyWith(
                fontSize: size,
                // `line-height: 1`, so the chip hugs its label rather than
                // inheriting the paragraph's leading and standing taller than
                // the line it sits on.
                height: 1,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );

    final onTap = widget.onTap;
    Widget interactive = onTap == null
        ? pill
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: pill,
          );
    if (widget.hoverable || onTap != null) {
      interactive = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: interactive,
      );
    }

    // A paragraph whose only content is a pill — a post that says nothing but
    // `#support` — reaches the renderer as a *block*, with a tight width. The
    // chip has to keep hugging its label there rather than stretching into a
    // full-width bar, and [Align] is what loosens the constraint back off it.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      heightFactor: 1,
      child: interactive,
    );
  }
}
