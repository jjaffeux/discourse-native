import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/control_style.dart';
import '../foundation/input_group_scope.dart';
import '../foundation/joined_control.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_label.dart';

/// A shadcn input with Flutter editing and Form ownership.
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
/// label. [semanticLabel] names the native editor without adding a visible
/// label. Rich field layouts belong to Field; [prefix] and [suffix] are simple
/// inline slots for application search/status controls, not Input Group's API.
/// The box is editable edge to edge: its padding takes the text cursor and a
/// press there focuses the editor. Multiline editing belongs to Textarea. Use
/// [DFileInput] for file selection. [borderless] supports editing a title in
/// place, with [style] and wrapping up to [maxLines] lines.
class DInput extends FormField<String> {
  DInput({
    super.key,
    this.borderless = false,
    this.style,
    this.maxLines = 1,
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
  }) : assert(maxLines > 0),
       assert(borderless || maxLines == 1),
       assert(controller == null || (initialValue == null && value == null)),
       assert(initialValue == null || value == null),
       assert(maxLength == null || maxLength > 0),
       super(
         initialValue: controller?.text ?? value ?? initialValue ?? '',
         builder: (state) => (state as _DInputState)._build(),
       );

  /// Removes the field surface and insets for editing text in place.
  final bool borderless;

  /// Text styling for an inline editor.
  final TextStyle? style;

  /// Inline editors may wrap; ordinary form inputs remain single-line.
  final int maxLines;

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
    final joined = DJoinedControlScope.maybeOf(context);
    final radius =
        joined?.resolveRadius(
          BorderRadius.circular(t.controlRadius),
          Directionality.of(context),
        ) ??
        BorderRadius.circular(t.controlRadius);
    final error = input.errorText ?? errorText;
    final isInvalid = input.invalid || error != null;
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final fontSize = touch ? DiscourseTypography.base : DiscourseTypography.sm;
    final style =
        input.style ??
        Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: fontSize,
          height: (touch ? 24 : 20) / fontSize,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: t.foreground,
        );
    final group = _group;
    final enabled = input.enabled && (group?.enabled ?? true);
    group?.report(_focus, enabled, isInvalid);
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
                controller: _controller,
                focusNode: _focus,
                enabled: enabled,
                readOnly: input.readOnly,
                autofocus: input.autofocus,
                style: style,
                maxLines: input.maxLines,
                minLines: input.borderless ? 1 : null,
                strutStyle: input.borderless
                    ? StrutStyle.fromTextStyle(style)
                    : null,
                scrollPadding: input.borderless
                    ? EdgeInsets.zero
                    : const EdgeInsets.all(20),
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
    if (group != null) {
      return Padding(padding: group.inputPadding, child: editor);
    }
    if (input.borderless &&
        input.labelText == null &&
        error == null &&
        input.helperText == null) {
      return editor;
    }
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
                style: TextStyle(
                  height: 19.25 / 14,
                  color: isInvalid ? t.destructive : null,
                ),
                child: Text(input.labelText!),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (input.borderless)
          editor
        else
          _InputHitTarget(
            touch: touch,
            onTap: input.enabled ? _focus.requestFocus : null,
            child: _InputSurface(
              enabled: input.enabled,
              invalid: isInvalid,
              focused: _focus.hasFocus,
              borderRadius: radius,
              joinedAxis: joined?.axis,
              omitLeadingBorder: joined?.omitsLeadingBorder ?? false,
              child: editor,
            ),
          ),
        if (error != null || input.helperText != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: error != null,
            child: Text(
              error ?? input.helperText!,
              style: style.copyWith(
                fontSize: DiscourseTypography.sm,
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
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    excludeFromSemantics: true,
    onTap: onTap,
    child: MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.text,
      child: touch
          ? ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DSpacing.touchTarget,
              ),
              child: Align(heightFactor: 1, child: child),
            )
          : child,
    ),
  );
}

class _InputSurface extends StatelessWidget {
  const _InputSurface({
    required this.child,
    required this.enabled,
    required this.invalid,
    required this.focused,
    this.borderRadius,
    this.joinedAxis,
    this.omitLeadingBorder = false,
    this.verticalPadding = 5,
    this.fadeDisabled = true,
  });
  final Widget child;
  final bool enabled, invalid, focused;
  final BorderRadius? borderRadius;
  final Axis? joinedAxis;
  final bool omitLeadingBorder;
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
        : DControlStyle.outlineBorder(t, dark: dark, field: true);
    final ring = invalid
        ? t.destructive.withValues(alpha: t.destructive.a * (dark ? .4 : .2))
        : focused
        ? t.focusRing.withValues(alpha: t.focusRing.a * .5)
        : null;
    return Opacity(
      opacity: enabled || !fadeDisabled ? 1 : .5,
      child: IgnorePointer(
        ignoring: !enabled,
        // transition-colors eases the border and fill; the ring is a box
        // shadow outside that property list, so it paints at once.
        child: CustomPaint(
          foregroundPainter: ring == null
              ? null
              : _InputRing(
                  color: ring,
                  radius:
                      borderRadius ?? BorderRadius.circular(t.controlRadius),
                ),
          child: AnimatedContainer(
            duration: DMotion.duration(
              context,
              const Duration(milliseconds: 150),
            ),
            curve: Curves.fastOutSlowIn,
            constraints: const BoxConstraints(minHeight: 32),
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: verticalPadding,
            ),
            decoration: _InputSurfaceDecoration(
              backgroundColor: DControlStyle.fieldFill(
                t,
                dark: dark,
                enabled: enabled,
              ),
              borderRadius:
                  borderRadius ?? BorderRadius.circular(t.controlRadius),
              borderColor: border,
              joinedAxis: joinedAxis,
              omitLeadingBorder: omitLeadingBorder,
            ),
            child: IconTheme.merge(
              data: IconThemeData(size: 16, color: t.mutedForeground),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _InputSurfaceDecoration extends Decoration {
  const _InputSurfaceDecoration({
    required this.backgroundColor,
    required this.borderColor,
    required this.borderRadius,
    required this.joinedAxis,
    required this.omitLeadingBorder,
  });

  final Color backgroundColor;
  final Color borderColor;
  final BorderRadius borderRadius;
  final Axis? joinedAxis;
  final bool omitLeadingBorder;

  @override
  EdgeInsetsGeometry get padding => const EdgeInsets.all(1);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _InputSurfacePainter(this);

  @override
  Decoration? lerpFrom(Decoration? a, double t) => a is _InputSurfaceDecoration
      ? _InputSurfaceDecoration(
          backgroundColor: Color.lerp(a.backgroundColor, backgroundColor, t)!,
          borderColor: Color.lerp(a.borderColor, borderColor, t)!,
          borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
          joinedAxis: t < .5 ? a.joinedAxis : joinedAxis,
          omitLeadingBorder: t < .5 ? a.omitLeadingBorder : omitLeadingBorder,
        )
      : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is _InputSurfaceDecoration ? b.lerpFrom(this, t) : super.lerpTo(b, t);
}

class _InputSurfacePainter extends BoxPainter {
  const _InputSurfacePainter(this.decoration);
  final _InputSurfaceDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = offset & configuration.size!;
    final rrect = decoration.borderRadius.toRRect(rect);
    canvas.drawRRect(rrect, Paint()..color = decoration.backgroundColor);
    final outline = rrect.deflate(.5);
    final borderPaint = Paint()
      ..color = decoration.borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (!decoration.omitLeadingBorder || decoration.joinedAxis == null) {
      canvas.drawRRect(outline, borderPaint);
      return;
    }
    final direction = configuration.textDirection ?? TextDirection.ltr;
    final clip = switch (decoration.joinedAxis!) {
      Axis.vertical => Rect.fromLTRB(
        rect.left - 1,
        rect.top + 1.01,
        rect.right + 1,
        rect.bottom + 1,
      ),
      Axis.horizontal when direction == TextDirection.rtl => Rect.fromLTRB(
        rect.left - 1,
        rect.top - 1,
        rect.right - 1.01,
        rect.bottom + 1,
      ),
      Axis.horizontal => Rect.fromLTRB(
        rect.left + 1.01,
        rect.top - 1,
        rect.right + 1,
        rect.bottom + 1,
      ),
    };
    canvas
      ..save()
      ..clipRect(clip)
      ..drawRRect(outline, borderPaint)
      ..restore();
  }
}

/// Paints only the exterior annulus: a spread shadow would also tint the
/// translucent input fill behind the text.
class _InputRing extends CustomPainter {
  const _InputRing({required this.color, required this.radius});
  final Color color;
  final BorderRadius radius;
  @override
  void paint(Canvas canvas, Size size) {
    final inner = radius.toRRect(Offset.zero & size);
    canvas.drawDRRect(inner.inflate(3), inner, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_InputRing oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
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
                              variant: DButtonVariant.ghost,
                              size: DButtonSize.small,
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
