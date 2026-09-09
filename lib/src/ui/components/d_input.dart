import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/input_group_scope.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_label.dart';

/// A single-line shadcn input with Flutter editing and Form ownership.
///
/// Supply [controller] for full selection/composing control, [value] for a
/// parent-updated string, or [initialValue] for local editing. These modes are
/// mutually exclusive. Equal string updates never replace the editing value;
/// changed strings collapse selection at the end and end composition. A Form
/// reset restores the value captured on mount and calls [onChanged]. Borrowed
/// controllers and focus nodes are never disposed. Switching controllers keeps
/// the new owner's value; switching to local ownership preserves editing state.
///
/// [labelText] is a static, focus-activating label, not a floating Material
/// label. Rich field layouts belong to Field; [prefix] and [suffix] are simple
/// inline slots for application search/status controls, not Input Group's API.
/// Multiline editing belongs to Textarea. Use [DFileInput] for file selection.
class DInput extends FormField<String> {
  DInput({
    super.key,
    this.editorKey,
    this.controller,
    this.value,
    String? initialValue,
    this.focusNode,
    this.labelText,
    this.semanticLabel,
    this.hintText,
    this.helperText,
    this.errorText,
    this.invalid = false,
    this.isRequired = false,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTap,
    this.onTapOutside,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
    this.readOnly = false,
    this.obscureText = false,
    this.obscuringCharacter = '•',
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enableInteractiveSelection = true,
    this.inputFormatters,
    this.autofillHints,
    this.maxLength,
    this.maxLengthEnforcement,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.undoController,
    this.contextMenuBuilder = _contextMenu,
    super.enabled = true,
    super.onSaved,
    super.onReset,
    super.validator,
    super.autovalidateMode,
  }) : assert(controller == null || (initialValue == null && value == null)),
       assert(initialValue == null || value == null),
       assert(maxLength == null || maxLength > 0),
       super(
         initialValue: controller?.text ?? value ?? initialValue ?? '',
         builder: (state) => (state as _DInputState)._build(),
       );

  final Key? editorKey;
  final TextEditingController? controller;
  final String? value;
  final FocusNode? focusNode;
  final String? labelText, semanticLabel, hintText, helperText, errorText;
  final bool invalid;

  /// Exposes required semantics; the caller supplies the validation rule.
  final bool isRequired;
  final Widget? prefix, suffix;
  final ValueChanged<String>? onChanged, onSubmitted;
  final VoidCallback? onEditingComplete, onTap;
  final TapRegionCallback? onTapOutside;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool autofocus, readOnly, obscureText;
  final String obscuringCharacter;
  final bool autocorrect, enableSuggestions, enableInteractiveSelection;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final UndoHistoryController? undoController;
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  static Widget _contextMenu(BuildContext context, EditableTextState state) {
    if (SystemContextMenu.isSupportedByField(state)) {
      return SystemContextMenu.editableText(editableTextState: state);
    }
    return AdaptiveTextSelectionToolbar.editableText(editableTextState: state);
  }

  @override
  FormFieldState<String> createState() => _DInputState();
}

class _DInputState extends FormFieldState<String> {
  TextEditingController? _ownedController;
  FocusNode? _ownedFocus;
  DInputGroupControlScope? _group;
  late final String _resetValue;
  bool _syncing = false;
  DInput get input => widget as DInput;
  TextEditingController get _controller =>
      input.controller ?? _ownedController!;
  FocusNode get _focus => input.focusNode ?? _ownedFocus!;

  @override
  void initState() {
    super.initState();
    _resetValue = widget.initialValue ?? '';
    if (input.controller == null) {
      _ownedController = TextEditingController(text: _resetValue);
    }
    if (input.focusNode == null) _ownedFocus = FocusNode();
    _controller.addListener(_changed);
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DInputGroupControlScope.maybeOf(context);
    if (!identical(next, _group)) {
      _group?.remove(_focus);
      _group = next;
    }
  }

  void _changed() {
    if (!_syncing && _controller.text != value) {
      // Selection and IME-only updates must never write back into the controller.
      super.didChange(_controller.text);
    }
  }

  @override
  void didUpdateWidget(covariant DInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != input.controller) {
      final previous = oldWidget.controller ?? _ownedController!;
      final editingValue = previous.value;
      previous.removeListener(_changed);
      if (input.controller == null) {
        _ownedController = TextEditingController.fromValue(editingValue);
      } else {
        _ownedController?.dispose();
        _ownedController = null;
      }
      _controller.addListener(_changed);
      setValue(_controller.text);
    }
    if (input.value != null && input.value != _controller.text) {
      _replace(input.value!);
      setValue(input.value);
    }
    if (oldWidget.focusNode != input.focusNode) {
      _group?.remove(oldWidget.focusNode ?? _ownedFocus!);
      (oldWidget.focusNode ?? _ownedFocus!).removeListener(_focusChanged);
      _ownedFocus?.dispose();
      _ownedFocus = input.focusNode == null ? FocusNode() : null;
      _focus.addListener(_focusChanged);
    }
    if (!input.enabled && oldWidget.enabled && _focus.hasFocus) {
      _focus.unfocus();
    }
  }

  void _replace(String text) {
    _syncing = true;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncing = false;
  }

  @override
  void didChange(String? value) {
    super.didChange(value);
    if (_controller.text != (value ?? '')) _replace(value ?? '');
  }

  @override
  void reset() {
    _replace(_resetValue);
    super.reset();
    setValue(_resetValue);
    input.onChanged?.call(_resetValue);
  }

  @override
  void dispose() {
    _group?.remove(_focus);
    _controller.removeListener(_changed);
    _focus.removeListener(_focusChanged);
    _ownedController?.dispose();
    _ownedFocus?.dispose();
    super.dispose();
  }

  Widget _build() {
    final t = DTokens.of(context);
    final error = input.errorText ?? errorText;
    final isInvalid = input.invalid || error != null;
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final fontSize = touch ? DiscourseTypography.base : DiscourseTypography.sm;
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: fontSize,
      height: (touch ? 24 : 20) / fontSize,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: t.foreground,
    );
    final group = _group;
    group?.report(_focus, input.enabled, isInvalid);
    final editor = TextFieldTapRegion(
      child: Row(
        children: [
          if (input.prefix != null) ...[
            input.prefix!,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Semantics(
              // Keep the editable role bounded to this editor. Without
              // a boundary it can merge into an entire page on macOS.
              container: true,
              label: input.semanticLabel ?? input.labelText,
              isRequired: input.isRequired,
              validationResult: isInvalid
                  ? SemanticsValidationResult.invalid
                  : SemanticsValidationResult.none,
              child: TextField(
                key: input.editorKey,
                controller: _controller,
                focusNode: _focus,
                enabled: input.enabled,
                readOnly: input.readOnly,
                autofocus: input.autofocus,
                style: style,
                decoration: InputDecoration(
                  isCollapsed: true,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  hintText: input.hintText,
                  hintStyle: style.copyWith(color: t.mutedForeground),
                  counterText: '',
                ),
                cursorColor: t.foreground,
                keyboardType: input.keyboardType,
                textInputAction: input.textInputAction,
                textCapitalization: input.textCapitalization,
                obscureText: input.obscureText,
                obscuringCharacter: input.obscuringCharacter,
                autocorrect: input.autocorrect,
                enableSuggestions: input.enableSuggestions,
                enableInteractiveSelection: input.enableInteractiveSelection,
                inputFormatters: input.inputFormatters,
                autofillHints: input.autofillHints,
                maxLength: input.maxLength,
                maxLengthEnforcement: input.maxLengthEnforcement,
                textAlign: input.textAlign,
                textDirection: input.textDirection,
                undoController: input.undoController,
                contextMenuBuilder: input.contextMenuBuilder,
                onChanged: input.onChanged,
                onSubmitted: input.onSubmitted,
                onEditingComplete: input.onEditingComplete,
                onTap: input.onTap,
                onTapOutside: input.onTapOutside,
              ),
            ),
          ),
          if (input.suffix != null) ...[
            const SizedBox(width: 8),
            input.suffix!,
          ],
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (input.labelText != null) ...[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: input.enabled ? _focus.requestFocus : null,
            child: ExcludeSemantics(
              child: DLabel(
                enabled: input.enabled,
                style: const TextStyle(height: 19.25 / 14),
                child: Text(input.labelText!),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (group == null)
          _InputHitTarget(
            touch: touch,
            onTap: input.enabled ? _focus.requestFocus : null,
            child: _InputSurface(
              enabled: input.enabled,
              invalid: isInvalid,
              focused: _focus.hasFocus,
              child: editor,
            ),
          )
        else
          Padding(
            padding: group.inputPadding,
            child: editor,
          ),
        if (error != null || input.helperText != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: error != null,
            child: Text(
              error ?? input.helperText!,
              style: style.copyWith(
                fontSize: 14,
                height: 21 / 14,
                color: error == null ? t.mutedForeground : t.destructive,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InputHitTarget extends StatelessWidget {
  const _InputHitTarget({required this.child, required this.touch, this.onTap});
  final Widget child;
  final bool touch;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => touch
      ? GestureDetector(
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: DSpacing.touchTarget),
            child: Align(heightFactor: 1, child: child),
          ),
        )
      : child;
}

class _InputSurface extends StatelessWidget {
  const _InputSurface({
    required this.child,
    required this.enabled,
    required this.invalid,
    required this.focused,
    this.verticalPadding = 5,
    this.fadeDisabled = true,
  });
  final Widget child;
  final bool enabled, invalid, focused;
  final double verticalPadding;
  final bool fadeDisabled;
  @override
  Widget build(BuildContext context) {
    final t = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = invalid
        ? t.destructive.withValues(alpha: t.destructive.a * (dark ? .5 : 1))
        : focused
        ? t.focusRing
        : t.colors.outlineVariant;
    final ring = invalid
        ? t.destructive.withValues(alpha: t.destructive.a * (dark ? .4 : .2))
        : t.focusRing.withValues(alpha: t.focusRing.a * .5);
    return Opacity(
      opacity: enabled || !fadeDisabled ? 1 : .5,
      child: IgnorePointer(
        ignoring: !enabled,
        child: AnimatedContainer(
          duration: DMotion.duration(
            context,
            const Duration(milliseconds: 150),
          ),
          constraints: const BoxConstraints(minHeight: 32),
          padding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            color: dark
                ? t.colors.outlineVariant.withValues(
                    alpha: t.colors.outlineVariant.a * (enabled ? .3 : .8),
                  )
                : enabled
                ? Colors.transparent
                : t.colors.outlineVariant.withValues(
                    alpha: t.colors.outlineVariant.a * .5,
                  ),
            borderRadius: BorderRadius.circular(t.radius),
            border: Border.all(color: border),
          ),
          foregroundDecoration: _InputRingDecoration(
            color: invalid || focused ? ring : ring.withValues(alpha: 0),
            radius: t.radius,
          ),
          child: IconTheme.merge(
            data: IconThemeData(size: 16, color: t.mutedForeground),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Paint only the exterior annulus: a spread shadow would also tint the
/// translucent input fill. Keeping a Decoration preserves color interpolation.
class _InputRingDecoration extends Decoration {
  const _InputRingDecoration({required this.color, required this.radius});
  final Color color;
  final double radius;
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _InputRingPainter(this);
  @override
  Decoration? lerpFrom(Decoration? a, double t) => a is _InputRingDecoration
      ? _InputRingDecoration(
          color: Color.lerp(a.color, color, t)!,
          radius: a.radius + (radius - a.radius) * t,
        )
      : super.lerpFrom(a, t);
  @override
  Decoration? lerpTo(Decoration? b, double t) => b is _InputRingDecoration
      ? _InputRingDecoration(
          color: Color.lerp(color, b.color, t)!,
          radius: radius + (b.radius - radius) * t,
        )
      : super.lerpTo(b, t);
}

class _InputRingPainter extends BoxPainter {
  _InputRingPainter(this.decoration);
  final _InputRingDecoration decoration;
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = offset & configuration.size!;
    final inner = RRect.fromRectAndRadius(
      rect,
      Radius.circular(decoration.radius),
    );
    canvas.drawDRRect(
      inner.inflate(3),
      inner,
      Paint()..color = decoration.color,
    );
  }
}

/// Native file input. The host owns the picker and file handles; this field
/// owns the displayed names and Form value. A null picker result is cancel.
/// The picker must return display names, never secret paths. It may support
/// multiple files; upload, permissions and file filtering remain host concerns.
class DFileInput extends FormField<List<String>> {
  DFileInput({
    super.key,
    required this.onPick,
    this.onChanged,
    this.label = 'Choose file',
    this.emptyLabel = 'No file chosen',
    super.initialValue = const [],
    super.enabled = true,
    super.validator,
    super.onSaved,
    super.onReset,
    super.autovalidateMode,
  }) : super(builder: (state) => (state as _DFileInputState)._build());
  final Future<List<String>?> Function() onPick;
  final ValueChanged<List<String>>? onChanged;
  final String label, emptyLabel;
  @override
  FormFieldState<List<String>> createState() => _DFileInputState();
}

class _DFileInputState extends FormFieldState<List<String>> {
  bool _busy = false;
  bool _focused = false;
  String? _pickerError;
  int _generation = 0;
  DFileInput get input => widget as DFileInput;
  Future<void> _pick() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _pickerError = null;
    });
    try {
      final names = await input.onPick();
      if (!mounted || generation != _generation || !input.enabled) return;
      if (names != null) {
        final selected = List<String>.unmodifiable(names);
        didChange(selected);
        input.onChanged?.call(selected);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _pickerError = 'Could not choose a file. Try again.');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  void didUpdateWidget(covariant DFileInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !input.enabled) {
      _generation++;
      _busy = false;
    }
  }

  @override
  void reset() {
    _generation++;
    _busy = false;
    _pickerError = null;
    super.reset();
    input.onChanged?.call(value ?? const []);
  }

  Widget _build() {
    final t = DTokens.of(context);
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(DiscourseTypography.sm) *
        20 /
        14;
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: t.foreground,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: Opacity(
            opacity: input.enabled ? 1 : .5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _InputSurface(
                  enabled: input.enabled,
                  fadeDisabled: false,
                  invalid: hasError || _pickerError != null,
                  focused: _focused,
                  verticalPadding: 3,
                  child: SizedBox(width: double.infinity, height: lineHeight),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Row(
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: touch ? DSpacing.touchTarget : 24,
                          ),
                          // The field owns disabled opacity. Keep the actual
                          // Button disabled, but neutralize its additional fade.
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              extensions: [
                                ...Theme.of(context).extensions.values.where(
                                  (value) => value is! DiscourseButtonTheme,
                                ),
                                Theme.of(
                                  context,
                                ).discourseButtons.copyWith(disabledOpacity: 1),
                              ],
                            ),
                            child: DButton(
                              onPressed: input.enabled && !_busy ? _pick : null,
                              variant: DButtonVariant.transparent,
                              size: DButtonSize.extraSmall,
                              padding: EdgeInsets.zero,
                              label: Text(
                                _busy ? 'Choosing…' : input.label,
                                maxLines: 1,
                                style: style.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          value?.isNotEmpty == true
                              ? value!.join(', ')
                              : input.emptyLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (errorText != null || _pickerError != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              errorText ?? _pickerError!,
              style: style.copyWith(color: t.destructive),
            ),
          ),
        ],
      ],
    );
  }
}
