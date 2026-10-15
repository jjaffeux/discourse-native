import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../foundation/app_text_scaler.dart';
import '../foundation/control_artwork.dart';
import '../foundation/tokens.dart';
import 'd_tooltip.dart';

/// A compact filter pill with independent edit and remove actions.
///
/// Uses 12/18px text, a 200px value limit and the reference's shared accent
/// tint. Both actions grow with text and keep their targets inside the pill.
/// Null callbacks disable their respective action. Labels belong to the caller.
class DFilterToken extends StatelessWidget {
  const DFilterToken({
    super.key,
    required this.label,
    required this.value,
    required this.editLabel,
    required this.removeLabel,
    required this.onEdited,
    required this.onRemoved,
    this.editKey,
    this.removeKey,
  });

  final String label;
  final String value;
  final String editLabel;
  final String removeLabel;
  final VoidCallback? onEdited;
  final VoidCallback? onRemoved;
  final Key? editKey;
  final Key? removeKey;

  @override
  Widget build(BuildContext context) =>
      DReferenceTextScale(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final tokens = DTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final accent = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(tokens.primary, Colors.white, .28)!
        : tokens.primary;
    final text = Theme.of(context).textTheme.bodySmall!.copyWith(
      fontSize: 12,
      height: 1.5,
      letterSpacing: 0,
      fontWeight: FontWeight.w400,
      color: tokens.foreground,
    );
    final measure = TextPainter(
      text: TextSpan(text: ' ', style: text),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    final prefix = [
      if (label.isNotEmpty) ...[
        TextSpan(
          text: '$label:',
          style: TextStyle(color: accent),
        ),
        TextSpan(
          text: ' ',
          style: TextStyle(letterSpacing: 5 - measure.width),
        ),
      ],
    ];
    measure.text = TextSpan(style: text, children: prefix);
    measure.layout();
    final maxLabelWidth = measure.width + 200 * scaler.scale(12) / 12;
    measure.dispose();
    ButtonStyle style(EdgeInsetsGeometry padding) => ButtonStyle(
      padding: WidgetStatePropertyAll(padding),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      textStyle: WidgetStatePropertyAll(text),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? tokens.mutedForeground
            : tokens.foreground,
      ),
      overlayColor: WidgetStatePropertyAll(
        tokens.primary.withValues(alpha: .1),
      ),
      shape: WidgetStateProperty.resolveWith(
        (states) => StadiumBorder(
          side: states.contains(WidgetState.focused)
              ? BorderSide(color: tokens.focusRing)
              : BorderSide.none,
        ),
      ),
    );
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: Material(
        color: tokens.primary.withValues(alpha: .12),
        shape: const StadiumBorder(),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: DTooltip(
                  message: editLabel,
                  child: DControlArtwork(
                    child: TextButton(
                      key: editKey,
                      style: style(
                        const EdgeInsetsDirectional.fromSTEB(9, 3, 2, 3),
                      ),
                      onPressed: onEdited,
                      child: Semantics(
                        label: editLabel,
                        excludeSemantics: true,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxLabelWidth),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                ...prefix,
                                TextSpan(
                                  text: value,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            style: text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              DTooltip(
                message: removeLabel,
                child: DControlArtwork(
                  child: TextButton(
                    key: removeKey,
                    style: style(
                      const EdgeInsetsDirectional.fromSTEB(4, 0, 9, 0),
                    ),
                    onPressed: onRemoved,
                    child: Semantics(
                      label: removeLabel,
                      excludeSemantics: true,
                      child: DIcon(
                        DIcons.xmark,
                        size: scaler.scale(10),
                        color: Color.lerp(
                          tokens.background,
                          tokens.foreground,
                          .62,
                        ),
                      ),
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
