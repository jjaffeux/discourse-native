import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/focus_highlight.dart';
import '../foundation/tokens.dart';

/// An image trigger with Discourse's fading metadata bar and hover shadow.
///
/// The caller supplies the image, its layout, and the action that opens it.
/// Metadata never changes that layout or intercepts image/GIF controls.
/// Keyboard focus reveals the bar; touch platforms show a compact expand hint.
/// [focusNode] is borrowed. A null [onPressed] disables the preview affordances.
class DImagePreview extends StatefulWidget {
  const DImagePreview({
    super.key,
    required this.child,
    required this.semanticLabel,
    required this.onPressed,
    this.filename,
    this.details,
    this.focusNode,
  });

  final Widget child;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final String? filename;
  final String? details;
  final FocusNode? focusNode;

  @override
  State<DImagePreview> createState() => _DImagePreviewState();
}

class _DImagePreviewState extends State<DImagePreview> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final enabled = widget.onPressed != null;
    final focused = enabled && _focused && DFocusHighlight.visibleOf(context);
    final active = enabled && (_hovered || focused);
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final radius = tokens.borderRadius;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: widget.onPressed,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ClipPath(
                  clipper: _OutsideImageClipper(radius),
                  child: AnimatedContainer(
                    duration: reducedMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 600),
                    curve: const Cubic(0.165, 0.84, 0.44, 1),
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      boxShadow: [
                        for (final blur in [5.0, 10.0])
                          BoxShadow(
                            color: tokens.colors.shadow.withValues(
                              alpha: active ? .2 : 0,
                            ),
                            offset: const Offset(0, 2),
                            blurRadius: blur,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            DecoratedBox(
              position: DecorationPosition.foreground,
              // Keep this layer mounted so focus and GIF state survive changes.
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: focused ? tokens.focusRing : Colors.transparent,
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    focusNode: widget.focusNode,
                    canRequestFocus: enabled,
                    onFocusChange: (value) => setState(() => _focused = value),
                    onTap: widget.onPressed,
                    excludeFromSemantics: true,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    splashFactory: NoSplash.splashFactory,
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        widget.child,
                        PositionedDirectional(
                          start: 0,
                          end: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: AnimatedOpacity(
                                opacity: active
                                    ? .9
                                    : (enabled && touch ? .8 : 0),
                                duration: reducedMotion
                                    ? Duration.zero
                                    : Duration(
                                        milliseconds: active ? 500 : 200,
                                      ),
                                child: _metadata(
                                  context,
                                  compact: touch && !active,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metadata(BuildContext context, {required bool compact}) {
    final tokens = DTokens.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final filename = widget.filename;
    final details = widget.details;
    final foreground = compact ? tokens.foreground : tokens.background;
    final expand = DIcon(DIcons.discourseExpand, size: 14, color: foreground);

    return Align(
      alignment: AlignmentDirectional.bottomEnd,
      child: ColoredBox(
        color: compact ? tokens.background : tokens.foreground,
        child: compact
            ? SizedBox.square(dimension: 25, child: Center(child: expand))
            : LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 80 * scale) {
                    return SizedBox(height: 25, child: Center(child: expand));
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 5,
                    ),
                    child: DefaultTextStyle(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontSize: DiscourseTypography.sm,
                        height: 1.25,
                        color: foreground,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 14,
                            color: foreground,
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text(filename ?? details ?? '')),
                          if (filename != null &&
                              details != null &&
                              constraints.maxWidth >= 260 * scale) ...[
                            const SizedBox(width: 6),
                            Expanded(child: Text(details)),
                          ],
                          const SizedBox(width: 12),
                          expand,
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// CSS box shadows leave the interior clear. Flutter's BoxShadow also paints
// beneath the image, so cut out that region to preserve transparent pixels.
class _OutsideImageClipper extends CustomClipper<Path> {
  const _OutsideImageClipper(this.radius);
  final BorderRadius radius;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect((Offset.zero & size).inflate(30))
    ..addRRect(radius.toRRect(Offset.zero & size).scaleRadii());

  @override
  bool shouldReclip(_OutsideImageClipper oldClipper) =>
      radius != oldClipper.radius;
}
