import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../foundation/control_style.dart';
import '../foundation/menu_content_scale.dart';
import 'd_button.dart';

/// A circular corner action for modal headers.
class DModalHeaderAction extends StatelessWidget {
  const DModalHeaderAction({
    super.key,
    this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
    this.semanticLabel,
    this.focusNode,
    this.hasPopup = false,
    this.expanded = false,
    this.loading = false,
  });

  const DModalHeaderAction.close({
    super.key,
    this.buttonKey,
    required this.onPressed,
    this.tooltip,
    this.semanticLabel,
    this.focusNode,
    this.hasPopup = false,
    this.expanded = false,
    this.loading = false,
  }) : icon = const _CloseIcon(),
       primary = false;

  final Widget icon;
  final Key? buttonKey;
  final String? tooltip;
  final VoidCallback? onPressed;

  /// Gives an enabled action an accent fill and white glyph on touch.
  final bool primary;

  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool hasPopup;
  final bool expanded;
  final bool loading;

  static const _touchIconSize = 24.0;

  static DButtonSize _sizeOf(BuildContext context) =>
      DControlStyle.isTouch(context) ? DButtonSize.action : DButtonSize.small;

  static double extentOf(BuildContext context) => DControlStyle.scaledHeight(
    _sizeOf(context),
    MediaQuery.textScalerOf(context),
    context: context,
  );

  @override
  Widget build(BuildContext context) =>
      DMenuContentScale.unscaled(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final touch = DControlStyle.isTouch(context);
    final tokens = DTokens.of(context);
    final enabled = onPressed != null && !loading;
    final accented = touch && primary && enabled;
    return DButton.iconOnly(
      key: buttonKey,
      icon: touch
          ? IconTheme.merge(
              data: const IconThemeData(size: _touchIconSize),
              child: icon,
            )
          : icon,
      tooltip: tooltip ?? context.l10n.close,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      focusNode: focusNode,
      hasPopup: hasPopup,
      expanded: expanded,
      loading: loading,
      size: _sizeOf(context),
      variant: accented ? DButtonVariant.primary : DButtonVariant.quiet,
      foregroundColor: accented
          ? Colors.white
          : touch && enabled
          ? tokens.foreground
          : null,
      backgroundColor: accented
          ? tokens.primary
          : touch
          ? tokens.foreground.withValues(alpha: expanded ? .16 : .10)
          : null,
      interactiveBackgroundColor: accented
          ? Color.lerp(tokens.primary, Colors.black, .08)
          : touch
          ? tokens.foreground.withValues(alpha: .16)
          : null,
    );
  }
}

class _CloseIcon extends StatelessWidget {
  const _CloseIcon();

  @override
  Widget build(BuildContext context) {
    final touch = DControlStyle.isTouch(context);
    final theme = IconTheme.of(context);
    return SizedBox.square(
      dimension: touch ? theme.size : 16,
      child: CustomPaint(
        painter: _CloseIconPainter(
          theme.color ?? DTokens.of(context).foreground,
          touch: touch,
        ),
      ),
    );
  }
}

class _CloseIconPainter extends CustomPainter {
  const _CloseIconPainter(this.color, {required this.touch});

  final Color color;
  final bool touch;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.width / (touch ? 6 : 4);
    final end = size.width - inset;
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width / 12
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset(inset, inset), Offset(end, end), paint)
      ..drawLine(Offset(end, inset), Offset(inset, end), paint);
  }

  @override
  bool shouldRepaint(_CloseIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.touch != touch;
}
