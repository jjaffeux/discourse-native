library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';

const double pillScale = 0.93;

const double pillPadX = 0.34;
const double pillPadY = 0.2;

const double pillRadius = 0.6;

const double pillSquare = 0.72;
const double pillSquareInset = 0.1;

const double pillGlyph = 0.93;

const double pillGap = 0.287;

class Pill extends StatefulWidget {
  const Pill({
    super.key,
    required this.label,
    required this.baseStyle,
    this.leading,
    this.onTap,
    this.hoverable = false,
    this.hovered = false,
    this.highlighted = false,
  });

  final String label;

  final TextStyle? baseStyle;

  final Widget? leading;

  final VoidCallback? onTap;

  final bool hoverable;

  final bool hovered;

  final bool highlighted;

  static double fontSizeFor(TextStyle? baseStyle) =>
      (baseStyle?.fontSize ?? DiscourseTypography.base) * pillScale;

  static double iconBoxFor(TextStyle? baseStyle) =>
      fontSizeFor(baseStyle) * pillGlyph / DIcon.glyphScale;

  @override
  State<Pill> createState() => _PillState();
}

class _PillState extends State<Pill> {
  bool _hovered = false;
  bool _focused = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  @override
  void didUpdateWidget(Pill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hoverable && widget.onTap == null) _hovered = false;
    if (widget.onTap == null) _focused = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = Pill.fontSizeFor(widget.baseStyle);
    final radius = BorderRadius.circular(size * pillRadius);
    final background = _hovered || widget.hovered || _focused
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
        : Semantics(
            button: true,
            child: InkWell(
              onTap: onTap,
              onFocusChange: _setFocused,
              // InkWell's adaptive macOS default is the basic arrow, and its
              // cursor region sits inside the hover region below.
              mouseCursor: SystemMouseCursors.click,
              borderRadius: radius,
              child: pill,
            ),
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
