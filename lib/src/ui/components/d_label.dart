import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_typography.dart';

/// Wrapping, non-selectable text for a native control's label slot.
///
/// The reference `<label htmlFor>` associates by element id. Flutter has no id
/// registry, so the control's label slot owns association: DCheckbox.title,
/// DSwitchTile.title and DRadioGroupItem.label toggle their control from the
/// label and merge one accessible name with its state; DFieldLabel,
/// DInput.labelText, DTextarea.labelText and DNativeSelect.label focus their
/// editor. The label adds no gesture handler or tab stop. A standalone DLabel is
/// ordinary text; placing one beside a control does not associate them.
///
/// A slot owner wraps the label it receives in its own DLabel to supply the
/// composition's line height and invalid color, and derives the disabled
/// treatment from its control the way the reference `peer-disabled` and
/// `group-data-[disabled=true]` selectors do. A DLabel nested inside another
/// therefore inherits the enclosing metrics, merges only its own [style], and
/// dims only when the enclosing label has not already done so.
///
/// [child] can compose text, spans and decorative icons. The reference label is
/// a cross-axis-centered flex row with an 8 logical pixel gap: use a `Row` with
/// `crossAxisAlignment: center`, `spacing: DSpacing.sm` and a flexible text
/// child so it wraps. Native slots merge semantics, so keep independently
/// interactive links outside them. The caller owns layout and the control's
/// value, callbacks and focus node. There is no outer padding, border or
/// minimum height on the label itself.
class DLabel extends StatelessWidget {
  const DLabel({
    super.key,
    required this.child,
    this.enabled = true,
    this.style,
  });

  final Widget child;

  /// Disabled treatment for a standalone label: 50% opacity, disabled
  /// semantics, a forbidden cursor, and no pointer or keyboard interaction
  /// with its content. It cannot disable a sibling or ancestor control. Inside
  /// a control's label slot the control derives this from its own state, and
  /// a label whose enclosing label is already disabled adds nothing.
  final bool enabled;

  /// Optional emphasis merged after the reference metrics and live colors.
  /// The host supplies the font family; the reference uses 14 logical pixels,
  /// weight 500, and line height 1. Inherited text scaling remains in effect.
  /// Child text styles take precedence.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scope = _DLabelScope.maybeOf(context);
    final base =
        scope?.style ??
        DText.styleOf(context, DTextVariant.small).copyWith(
          fontSize: DiscourseTypography.sm,
          fontWeight: FontWeight.w500,
          height: 1,
          letterSpacing: 0,
          color: DTokens.of(context).foreground,
        );
    final resolved = base.merge(style);
    final dims = !enabled && (scope?.enabled ?? true);
    return _DLabelScope(
      enabled: enabled && (scope?.enabled ?? true),
      style: resolved,
      child: Semantics(
        enabled: dims ? false : null,
        child: MouseRegion(
          cursor: dims ? SystemMouseCursors.forbidden : MouseCursor.defer,
          child: ExcludeFocus(
            excluding: dims,
            child: IgnorePointer(
              ignoring: dims,
              child: Opacity(
                opacity: dims ? 0.5 : 1,
                child: SelectionContainer.disabled(
                  child: DefaultTextStyle(
                    style: resolved,
                    textAlign: TextAlign.start,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The resolved metrics and effective enabled state of an enclosing label, so
/// a nested label extends its slot owner's composition instead of resetting it.
class _DLabelScope extends InheritedWidget {
  const _DLabelScope({
    required this.enabled,
    required this.style,
    required super.child,
  });

  final bool enabled;
  final TextStyle style;

  static _DLabelScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DLabelScope>();

  @override
  bool updateShouldNotify(_DLabelScope oldWidget) =>
      enabled != oldWidget.enabled || style != oldWidget.style;
}
