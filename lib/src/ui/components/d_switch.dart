import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_label.dart';

/// The two base-nova switch sizes, in logical pixels.
enum DSwitchSize { standard, small }

/// A shadcn switch with native focus, keyboard and accessibility interaction.
///
/// Supply [value] for controlled state, or omit it to own state initialized by
/// [initialValue]. A controlled switch with no [onChanged] is disabled.
/// Uncontrolled switches can omit the callback. [readOnly] keeps focus and the
/// value available while preventing edits. Borrowed [focusNode] is never disposed.
class DSwitch extends StatefulWidget {
  const DSwitch({
    super.key,
    this.value,
    this.initialValue = false,
    this.onChanged,
    this.enabled = true,
    this.readOnly = false,
    this.invalid = false,
    this.size = DSwitchSize.standard,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.semanticHint,
  }) : _content = null,
       _card = false;

  const DSwitch._tile({
    required this.value,
    required this.onChanged,
    required this.enabled,
    required this.readOnly,
    required this.invalid,
    required this.size,
    required this.focusNode,
    required this.autofocus,
    required this._content,
    required this._card,
  }) : initialValue = false,
       semanticLabel = null,
       semanticHint = null;

  final bool? value;
  final bool initialValue;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final bool readOnly;
  final bool invalid;
  final DSwitchSize size;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;
  final String? semanticHint;
  final Widget Function(BuildContext, Widget, bool, bool)? _content;
  final bool _card;

  @override
  State<DSwitch> createState() => _DSwitchState();
}

class _DSwitchState extends State<DSwitch> {
  late bool _value = widget.initialValue;
  bool _focusVisible = false;
  bool _hovered = false;
  final FocusNode _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  bool get _checked => widget.value ?? _value;
  bool get _enabled =>
      widget.enabled && (widget.value == null || widget.onChanged != null);

  void _toggle() {
    if (!_enabled || widget.readOnly) return;
    final next = !_checked;
    if (widget.value == null) setState(() => _value = next);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final artwork = _SwitchArtwork(
      checked: _checked,
      size: widget.size,
      invalid: widget.invalid,
      focused: _focusVisible && !widget._card,
    );
    return MergeSemantics(
      child: Semantics(
        toggled: _checked,
        enabled: _enabled,
        readOnly: widget.readOnly,
        label: widget.semanticLabel,
        hint: widget.semanticHint,
        validationResult: widget.invalid
            ? SemanticsValidationResult.invalid
            : SemanticsValidationResult.none,
        onTap: _enabled && !widget.readOnly ? _toggle : null,
        child: FocusableActionDetector(
          enabled: _enabled,
          focusNode: _focus,
          autofocus: widget.autofocus,
          mouseCursor: !_enabled
              ? SystemMouseCursors.forbidden
              : widget.readOnly
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          onShowFocusHighlight: (value) =>
              setState(() => _focusVisible = value),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _toggle();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _enabled
                ? () {
                    _focus.requestFocus();
                    _toggle();
                  }
                : null,
            child: Opacity(
              opacity: _enabled ? 1 : 0.5,
              child:
                  widget._content?.call(
                    context,
                    artwork,
                    _focusVisible,
                    _hovered,
                  ) ??
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: artwork),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchArtwork extends StatelessWidget {
  const _SwitchArtwork({
    required this.checked,
    required this.size,
    required this.invalid,
    required this.focused,
  });
  final bool checked;
  final DSwitchSize size;
  final bool invalid;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final small = size == DSwitchSize.small;
    final ring = invalid ? tokens.destructive : tokens.focusRing;
    final duration = DMotion.duration(
      context,
      const Duration(milliseconds: 150),
    );
    return AnimatedContainer(
      duration: duration,
      curve: const Cubic(0.4, 0, 0.2, 1),
      width: small ? 24 : 32,
      height: small ? 14 : 18.4,
      decoration: BoxDecoration(
        color: checked
            ? tokens.primary
            : tokens.border.withValues(alpha: dark ? 0.8 : 1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: invalid || focused
              ? ring.withValues(alpha: invalid && dark ? 0.5 : 1)
              : Colors.transparent,
        ),
        boxShadow: invalid || focused
            ? [
                BoxShadow(
                  color: ring.withValues(
                    alpha: invalid ? (dark ? 0.4 : 0.2) : 0.5,
                  ),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      child: AnimatedAlign(
        duration: duration,
        curve: const Cubic(0.4, 0, 0.2, 1),
        alignment: checked
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: SizedBox.square(
          dimension: small ? 12 : 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark
                  ? (checked ? tokens.primaryForeground : tokens.foreground)
                  : tokens.background,
            ),
          ),
        ),
      ),
    );
  }
}

/// A wrapping label/description associated with one switch and one tab stop.
///
/// The whole row activates the switch. Do not put independently interactive
/// links in [title] or [subtitle]. Those belong outside this merged control.
/// [choiceCard] adds the documented clickable border/card composition; this is
/// a switch composition, not a replacement for the general Field component.
class DSwitchTile extends StatelessWidget {
  const DSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.enabled = true,
    this.readOnly = false,
    this.invalid = false,
    this.choiceCard = false,
    this.leading = false,
    this.size = DSwitchSize.standard,
    this.contentPadding = EdgeInsets.zero,
    this.focusNode,
    this.autofocus = false,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget title;
  final Widget? subtitle;
  final bool enabled;
  final bool readOnly;
  final bool invalid;
  final bool choiceCard;
  final bool leading;
  final DSwitchSize size;
  final EdgeInsetsGeometry contentPadding;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => DSwitch._tile(
    value: value,
    onChanged: onChanged,
    enabled: enabled,
    readOnly: readOnly,
    invalid: invalid,
    size: size,
    focusNode: focusNode,
    autofocus: autofocus,
    card: choiceCard,
    content: (context, artwork, focused, hovered) {
      final tokens = DTokens.of(context);
      final dark = Theme.of(context).brightness == Brightness.dark;
      return AnimatedContainer(
        duration: DMotion.duration(context, const Duration(milliseconds: 150)),
        curve: const Cubic(0.4, 0, 0.2, 1),
        constraints: const BoxConstraints(minHeight: DSpacing.touchTarget),
        padding: choiceCard
            ? const EdgeInsets.all(10).add(contentPadding)
            : contentPadding,
        decoration: choiceCard
            ? BoxDecoration(
                border: Border.all(
                  color: focused
                      ? tokens.focusRing
                      : value
                      ? tokens.primary.withValues(alpha: dark ? 0.2 : 0.3)
                      : tokens.border,
                ),
                borderRadius: BorderRadius.circular(tokens.radius + 4),
                color: hovered && enabled && onChanged != null
                    ? tokens.muted.withValues(alpha: 0.5)
                    : value
                    ? tokens.primary.withValues(alpha: dark ? 0.1 : 0.05)
                    : null,
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: tokens.focusRing.withValues(alpha: 0.5),
                          spreadRadius: 3,
                        ),
                      ]
                    : null,
              )
            : null,
        child: Row(
          crossAxisAlignment: subtitle == null
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            if (leading) ...[artwork, const SizedBox(width: 8)],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title is DLabel
                      ? DLabel(
                          style: TextStyle(
                            height: subtitle == null && leading ? 1 : 1.375,
                            color: invalid ? tokens.destructive : null,
                          ).merge((title as DLabel).style),
                          child: (title as DLabel).child,
                        )
                      : DLabel(
                          style: TextStyle(
                            height: subtitle == null && leading ? 1 : 1.375,
                            color: invalid ? tokens.destructive : null,
                          ),
                          child: title,
                        ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontSize: DiscourseTypography.sm,
                        height: 1.5,
                        color: invalid
                            ? tokens.destructive
                            : tokens.mutedForeground,
                      ),
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (!leading) ...[const SizedBox(width: 8), artwork],
          ],
        ),
      );
    },
  );
}

/// A switch integrated with Flutter Form validation, save and reset.
///
/// [value] optionally makes the field controlled; external changes synchronize
/// the field value without reporting a user edit. Reset reports [initialValue]
/// through [onChanged], so controlled callers can update their state too.
class DSwitchFormField extends FormField<bool> {
  DSwitchFormField({
    super.key,
    this.value,
    bool initialValue = false,
    this.onChanged,
    required Widget title,
    Widget? subtitle,
    bool readOnly = false,
    bool choiceCard = false,
    DSwitchSize size = DSwitchSize.standard,
    FocusNode? focusNode,
    super.enabled,
    super.onSaved,
    super.validator,
    super.autovalidateMode,
    super.restorationId,
  }) : _resetValue = initialValue,
       super(
         initialValue: value ?? initialValue,
         builder: (field) => Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           mainAxisSize: MainAxisSize.min,
           children: [
             DSwitchTile(
               value: field.value ?? false,
               onChanged: enabled
                   ? (next) {
                       field.didChange(next);
                       onChanged?.call(next);
                     }
                   : null,
               enabled: enabled,
               readOnly: readOnly,
               invalid: field.hasError,
               title: title,
               subtitle: subtitle,
               choiceCard: choiceCard,
               size: size,
               focusNode: focusNode,
             ),
             if (field.errorText case final error?)
               Semantics(
                 liveRegion: true,
                 child: Text(
                   error,
                   style: TextStyle(
                     color: DTokens.of(field.context).destructive,
                     fontSize: DiscourseTypography.sm,
                     height: 1.5,
                   ),
                 ),
               ),
           ],
         ),
       );
  final bool? value;
  final bool _resetValue;
  final ValueChanged<bool>? onChanged;
  @override
  FormFieldState<bool> createState() => _DSwitchFormFieldState();
}

class _DSwitchFormFieldState extends FormFieldState<bool> {
  @override
  DSwitchFormField get widget => super.widget as DSwitchFormField;
  @override
  void didUpdateWidget(covariant DSwitchFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != oldWidget.value) {
      setValue(widget.value);
    }
  }

  @override
  void didChange(bool? value) => super.didChange(widget.value ?? value);
  @override
  void reset() {
    super.reset();
    setState(() => setValue(widget.value ?? widget._resetValue));
    widget.onChanged?.call(widget._resetValue);
  }
}
