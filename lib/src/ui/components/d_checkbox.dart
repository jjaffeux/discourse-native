import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/tokens.dart';
import 'd_label.dart';

/// A shadcn checkbox with native focus, keyboard and semantic ownership.
///
/// The default constructor is controlled: update [value] in [onChanged]. A null
/// callback disables it. [DCheckbox.defaultValue] owns its initial state and
/// permits an optional change observer. Null represents mixed when [tristate]
/// is true; activation toggles false/true, and mixed activates to true.
/// Mixed is a derived group state, never a third stop in the activation cycle.
///
/// [title] and [subtitle] form one accessible, clickable label. Keep links and
/// other independently interactive content outside those slots. [secondary]
/// remains outside the control's semantics and focus owner. Borrowed [focusNode]
/// is never disposed. Pointer targets are 40×32, touch targets 48×48; the painted
/// control always remains 16×16 logical pixels.
class DCheckbox extends StatefulWidget {
  const DCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tristate = false,
    this.enabled = true,
    this.invalid = false,
    this.readOnly = false,
    this.title,
    this.subtitle,
    this.secondary,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.contentPadding = EdgeInsets.zero,
  }) : _controlled = true,
       assert(tristate || value != null);

  const DCheckbox.defaultValue({
    super.key,
    bool? defaultValue = false,
    this.onChanged,
    this.tristate = false,
    this.enabled = true,
    this.invalid = false,
    this.readOnly = false,
    this.title,
    this.subtitle,
    this.secondary,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.contentPadding = EdgeInsets.zero,
  }) : value = defaultValue,
       _controlled = false,
       assert(tristate || defaultValue != null);

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;
  final bool enabled;
  final bool invalid;

  /// Remains focusable and visually enabled, but refuses all value changes.
  final bool readOnly;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final EdgeInsetsGeometry contentPadding;
  final bool _controlled;

  @override
  State<DCheckbox> createState() => _DCheckboxState();
}

class _DCheckboxState extends State<DCheckbox> {
  late bool? _value = widget.value;
  bool _focusVisible = false;
  final FocusNode _ownedFocusNode = FocusNode(debugLabel: 'Checkbox');
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;

  @override
  void dispose() {
    _ownedFocusNode.dispose();
    super.dispose();
  }

  void _pointerActivate() {
    if (!_enabled) return;
    _focusNode.requestFocus();
    _activate();
  }

  bool get _enabled =>
      widget.enabled && (!widget._controlled || widget.onChanged != null);
  bool? get _current => widget._controlled ? widget.value : _value;

  void _activate() {
    if (!_enabled || widget.readOnly) return;
    final next = switch (_current) {
      false => true,
      true => false,
      null => true,
    };
    if (!widget._controlled) setState(() => _value = next);
    widget.onChanged?.call(next);
  }

  @override
  void didUpdateWidget(DCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._controlled != widget._controlled) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
    final checked = _current == true;
    final border = checked
        ? tokens.primary
        : widget.invalid
        ? (dark ? tokens.destructive.withValues(alpha: .5) : tokens.destructive)
        : _focusVisible
        ? tokens.focusRing
        : tokens.border;
    final ring = widget.invalid
        ? tokens.destructive.withValues(alpha: dark ? .4 : .2)
        : _focusVisible
        ? tokens.focusRing.withValues(alpha: .5)
        : null;
    final artwork = AnimatedContainer(
      duration: DMotion.duration(context, const Duration(milliseconds: 150)),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: checked
            ? tokens.primary
            : dark
            ? tokens.border.withValues(alpha: .3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
        boxShadow: ring == null
            ? null
            : [BoxShadow(color: ring, spreadRadius: 3)],
      ),
      child: Center(
        child: CustomPaint(
          size: const Size.square(14),
          painter: _CheckboxMark(
            _current,
            checked ? tokens.primaryForeground : tokens.foreground,
          ),
        ),
      ),
    );
    Widget content = widget.title == null
        ? SizedBox(
            width: touch ? 48 : 40,
            height: touch ? 48 : 32,
            child: Center(child: artwork),
          )
        : ConstrainedBox(
            constraints: BoxConstraints(minHeight: touch ? 48 : 32),
            child: Row(
              crossAxisAlignment: widget.subtitle == null
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: widget.subtitle == null ? 0 : 1,
                  ),
                  child: artwork,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DLabel(
                        style:
                            TextStyle(
                              height: widget.subtitle == null ? 1 : 1.375,
                              color: widget.invalid ? tokens.destructive : null,
                            ).merge(
                              widget.title is DLabel
                                  ? (widget.title! as DLabel).style
                                  : null,
                            ),
                        child: widget.title is DLabel
                            ? (widget.title! as DLabel).child
                            : widget.title!,
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        DefaultTextStyle.merge(
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: tokens.mutedForeground,
                          ),
                          child: widget.subtitle!,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
    content = FocusableActionDetector(
      enabled: _enabled,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      mouseCursor: _enabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.forbidden,
      onShowFocusHighlight: (value) => setState(() => _focusVisible = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: MergeSemantics(
        child: Semantics(
          validationResult: widget.invalid
              ? SemanticsValidationResult.invalid
              : SemanticsValidationResult.none,
          checked: _current == true,
          mixed: _current == null,
          readOnly: widget.readOnly,
          enabled: _enabled,
          label: widget.semanticLabel,
          onTap: _enabled && !widget.readOnly ? _pointerActivate : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _enabled ? _pointerActivate : null,
            child: Opacity(opacity: _enabled ? 1 : .5, child: content),
          ),
        ),
      ),
    );
    if (widget.secondary != null) {
      content = Row(
        children: [
          Expanded(child: content),
          const SizedBox(width: 12),
          widget.secondary!,
        ],
      );
    }
    return Padding(padding: widget.contentPadding, child: content);
  }
}

class _CheckboxMark extends CustomPainter {
  const _CheckboxMark(this.value, this.color);
  final bool? value;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (value == false) return;
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Lucide Check (20 6, 9 17, 4 12) and Minus (5 12, 19 12).
    final path = value == true
        ? (Path()
            ..moveTo(20, 6)
            ..lineTo(9, 17)
            ..lineTo(4, 12))
        : (Path()
            ..moveTo(5, 12)
            ..lineTo(19, 12));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckboxMark oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

/// Native FormField integration. Reset restores [initialValue] and notifies
/// [onChanged]; validation errors are announced and clear through normal Form
/// autovalidation. [DCheckboxFormField.controlled] also follows external value
/// updates, without treating those updates as user interaction. In controlled
/// fields, the constructor's initialValue is a reset proposal: the native field
/// retains the current controlled value until a parent rebuild accepts it,
/// including during synchronous save/validate calls inside change callbacks.
class DCheckboxFormField extends FormField<bool> {
  factory DCheckboxFormField.controlled({
    Key? key,
    required bool? value,
    required ValueChanged<bool?>? onChanged,
    bool? initialValue = false,
    bool enabled = true,
    bool tristate = false,
    bool readOnly = false,
    Widget? title,
    Widget? subtitle,
    String? semanticLabel,
    FocusNode? focusNode,
    bool autofocus = false,
    FormFieldSetter<bool>? onSaved,
    FormFieldValidator<bool>? validator,
    AutovalidateMode autovalidateMode = AutovalidateMode.disabled,
  }) => _ControlledCheckboxFormField(
    key: key,
    value: value,
    onChanged: onChanged,
    initialValue: initialValue,
    enabled: enabled && onChanged != null,
    tristate: tristate,
    readOnly: readOnly,
    title: title,
    subtitle: subtitle,
    semanticLabel: semanticLabel,
    focusNode: focusNode,
    autofocus: autofocus,
    onSaved: onSaved,
    validator: validator,
    autovalidateMode: autovalidateMode,
  );

  DCheckboxFormField({
    Key? key,
    bool? initialValue = false,
    bool enabled = true,
    FormFieldSetter<bool>? onSaved,
    FormFieldValidator<bool>? validator,
    AutovalidateMode? autovalidateMode,
    String? restorationId,
    bool tristate = false,
    bool readOnly = false,
    Widget? title,
    Widget? subtitle,
    String? semanticLabel,
    FocusNode? focusNode,
    bool autofocus = false,
    ValueChanged<bool?>? onChanged,
  }) : this._(
         key: key,
         initialValue: initialValue,
         resetValue: initialValue,
         enabled: enabled,
         onSaved: onSaved,
         validator: validator,
         autovalidateMode: autovalidateMode,
         restorationId: restorationId,
         tristate: tristate,
         readOnly: readOnly,
         title: title,
         subtitle: subtitle,
         semanticLabel: semanticLabel,
         focusNode: focusNode,
         autofocus: autofocus,
         onChanged: onChanged,
       );

  DCheckboxFormField._({
    required bool? resetValue,
    super.key,
    super.initialValue = false,
    super.enabled = true,
    super.onSaved,
    super.validator,
    super.autovalidateMode,
    super.restorationId,
    bool tristate = false,
    bool readOnly = false,
    Widget? title,
    Widget? subtitle,
    String? semanticLabel,
    FocusNode? focusNode,
    bool autofocus = false,
    ValueChanged<bool?>? onChanged,
  }) : assert(tristate || initialValue != null),
       assert(tristate || resetValue != null),
       super(
         onReset: () => onChanged?.call(resetValue),
         builder: (field) => Column(
           mainAxisSize: MainAxisSize.min,
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             DCheckbox(
               value: field.value,
               tristate: tristate,
               readOnly: readOnly,
               enabled: enabled,
               invalid: field.hasError,
               title: title,
               subtitle: subtitle,
               semanticLabel: semanticLabel,
               focusNode: focusNode,
               autofocus: autofocus,
               onChanged: enabled
                   ? (value) {
                       field.didChange(value);
                       onChanged?.call(value);
                     }
                   : null,
             ),
             if (field.errorText != null)
               Semantics(
                 liveRegion: true,
                 child: Padding(
                   padding: const EdgeInsetsDirectional.only(start: 24, top: 6),
                   child: Text(
                     field.errorText!,
                     style: TextStyle(
                       fontSize: 14,
                       height: 1.5,
                       color: DTokens.of(field.context).destructive,
                     ),
                   ),
                 ),
               ),
           ],
         ),
       );
}

class _ControlledCheckboxFormField extends DCheckboxFormField {
  _ControlledCheckboxFormField({
    super.key,
    required this.value,
    required super.onChanged,
    bool? initialValue = false,
    super.enabled,
    super.tristate,
    super.readOnly,
    super.title,
    super.subtitle,
    super.semanticLabel,
    super.focusNode,
    super.autofocus,
    super.onSaved,
    super.validator,
    super.autovalidateMode,
  }) : super._(initialValue: value, resetValue: initialValue);
  final bool? value;
  @override
  FormFieldState<bool> createState() => _ControlledCheckboxFormFieldState();
}

class _ControlledCheckboxFormFieldState extends FormFieldState<bool> {
  @override
  void didChange(bool? value) {
    // Mark the interaction and notify Form, without publishing an unaccepted
    // proposal to synchronous validators, save callbacks or Form listeners.
    super.didChange((widget as _ControlledCheckboxFormField).value);
  }

  // Native reset uses this widget's effective initialValue (the controlled
  // prop). Its onReset callback separately proposes the requested reset value,
  // after clearing interaction/error state and before notifying Form.

  @override
  void didUpdateWidget(covariant _ControlledCheckboxFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget as _ControlledCheckboxFormField;
    if (next.value != value) setValue(next.value);
  }
}
