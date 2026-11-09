import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../foundation/focus_highlight.dart';

/// A square image that picks what a gallery shows.
///
/// An unselected thumbnail recedes; the selected one stands at full strength
/// inside an outline of [outlineColor], the theme's foreground by default.
/// The outline is drawn outside the bounds and takes [outlineExtent] on every
/// side, which a parent that clips must leave clear. The caller supplies the
/// image, decoded for [size], and owns what [onPressed] selects.
/// [focusNode] is borrowed.
class DImageThumbnail extends StatefulWidget {
  const DImageThumbnail({
    super.key,
    required this.child,
    required this.semanticLabel,
    required this.selected,
    required this.onPressed,
    this.outlineColor,
    this.focusNode,
  });

  static const size = 52.0;

  /// The room the outline takes: a 2px gap and a 2px stroke.
  static const outlineExtent = 4.0;

  static const _radius = 6.0;

  final Widget child;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onPressed;
  final Color? outlineColor;
  final FocusNode? focusNode;

  @override
  State<DImageThumbnail> createState() => _DImageThumbnailState();
}

class _DImageThumbnailState extends State<DImageThumbnail> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final focused = _focused && DFocusHighlight.visibleOf(context);
    final outline = focused
        ? tokens.focusRing
        : widget.selected
        ? widget.outlineColor ?? tokens.foreground
        : Colors.transparent;

    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: DImageThumbnail.size,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              AnimatedOpacity(
                opacity: widget.selected ? 1 : .45,
                duration: DMotion.duration(
                  context,
                  const Duration(milliseconds: 150),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DImageThumbnail._radius),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      focusNode: widget.focusNode,
                      onFocusChange: (value) =>
                          setState(() => _focused = value),
                      onTap: widget.onPressed,
                      excludeFromSemantics: true,
                      hoverColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      splashFactory: NoSplash.splashFactory,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                left: -DImageThumbnail.outlineExtent,
                top: -DImageThumbnail.outlineExtent,
                right: -DImageThumbnail.outlineExtent,
                bottom: -DImageThumbnail.outlineExtent,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        DImageThumbnail._radius + DImageThumbnail.outlineExtent,
                      ),
                      border: Border.all(color: outline, width: 2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
