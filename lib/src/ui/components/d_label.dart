import 'package:flutter/material.dart';

import '../foundation/tokens.dart';
import 'd_typography.dart';

/// Wrapping, non-selectable text for a native control's label slot.
///
/// Put this in [CheckboxListTile.title], [SwitchListTile.title], or
/// [RadioListTile.title]. That owner associates the label with its control,
/// combines their semantics, and provides touch activation and keyboard focus.
/// The label adds no gesture handler or tab stop. Standalone labels are ordinary
/// text; placing one beside a control does not associate them.
///
/// Keep [InputDecoration.labelText] for native form fields: it owns floating
/// labels, focus/error colors, and the field's accessible name. Labels do not
/// replace [Form], validation, descriptions, or error messages.
///
/// [child] can compose text, spans, and decorative icons. Native list tiles merge
/// their semantics, so put independently interactive links outside the tile.
/// The caller owns layout and the control's value, callbacks, and focus node.
/// For icon/text rows, use [DSpacing.sm] (8 logical pixels) between children.
/// There is no outer padding, border or minimum height on the label itself.
class DLabel extends StatelessWidget {
  const DLabel({
    super.key,
    required this.child,
    this.enabled = true,
    this.style,
  });

  final Widget child;

  /// Keep this in sync with the owning control's enabled state / null callback.
  ///
  /// A disabled label uses 50% opacity, exposes disabled semantics, and blocks
  /// pointer and keyboard interaction with its content. It cannot disable a
  /// sibling or ancestor control on the caller's behalf.
  final bool enabled;

  /// Optional emphasis merged after the reference metrics and live colors.
  /// The host supplies the font family; the reference uses 14 logical pixels,
  /// weight 500, and line height 1. Inherited text scaling remains in effect.
  /// Child text styles take precedence.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Semantics(
      enabled: enabled ? null : false,
      child: MouseRegion(
        cursor: enabled ? MouseCursor.defer : SystemMouseCursors.forbidden,
        child: ExcludeFocus(
          excluding: !enabled,
          child: IgnorePointer(
            ignoring: !enabled,
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: SelectionContainer.disabled(
                child: DefaultTextStyle(
                  style: DText.styleOf(context, DTextVariant.small)
                      .copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1,
                        letterSpacing: 0,
                        color: tokens.foreground,
                      )
                      .merge(style),
                  textAlign: TextAlign.start,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
