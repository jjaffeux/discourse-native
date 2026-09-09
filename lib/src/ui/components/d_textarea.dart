import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_label.dart';

/// A content-growing multiline field styled from shadcn's base-nova Textarea.
///
/// Supply one of [controller], [value] or [initialValue]. Borrowed controllers,
/// focus nodes, scroll and undo controllers remain caller-owned. Equal string
/// updates preserve selection and IME composition; a changed [value] replaces
/// text and collapses selection at its end. Form reset restores the mount-time
/// text, including when the parent has subsequently changed [value].
///
/// The default grows with content above a 64px minimum. [minLines] reserves
/// additional lines; [maxLines] bounds growth and enables native scrolling.
/// [labelText] is a static focus-activating DLabel. [helperText], [errorText]
/// and [showCounter] compose below the field. Validation remains caller-owned.
/// Native selection, clipboard, undo, keyboard and IME are owned by TextField.
/// There is no browser resize grip; content growth and optional line bounds
/// keep native layouts usable without adding an independent resize interaction.
class DTextarea extends FormField<String> {
  DTextarea({
    super.key,
    this.controller,
    this.value,
    String? initialValue,
    this.focusNode,
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.invalid = false,
    this.isRequired = false,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTap,
    this.onTapOutside,
    this.keyboardType = TextInputType.multiline,
    this.textInputAction = TextInputAction.newline,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
    this.readOnly = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enableInteractiveSelection = true,
    this.inputFormatters,
    this.autofillHints,
    this.minLines = 1,
    this.maxLines,
    this.scrollController,
    this.scrollPhysics,
    this.showCounter = false,
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
       assert(minLines > 0),
       assert(maxLines == null || maxLines >= minLines),
       super(
         initialValue: controller?.text ?? value ?? initialValue ?? '',
         builder: (state) => (state as _DTextareaState)._build(),
       );

  final TextEditingController? controller;
  final String? value;
  final FocusNode? focusNode;
  final String? labelText, hintText, helperText, errorText;
  final bool invalid;

  /// Exposes required semantics; the caller supplies the validation rule.
  final bool isRequired;
  final ValueChanged<String>? onChanged, onSubmitted;
  final VoidCallback? onEditingComplete, onTap;
  final TapRegionCallback? onTapOutside;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool autofocus, readOnly;
  final int minLines;
  final int? maxLines;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;
  final bool showCounter;
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
  FormFieldState<String> createState() => _DTextareaState();
}

class _DTextareaState extends FormFieldState<String> {
  TextEditingController? _ownedController;
  FocusNode? _ownedFocus;
  late final String _resetValue;
  bool _syncing = false;
  DTextarea get input => widget as DTextarea;
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

  void _changed() {
    if (!_syncing && _controller.text != value) {
      // Selection and IME-only updates must never write back into the controller.
      super.didChange(_controller.text);
    }
  }

  @override
  void didUpdateWidget(covariant DTextarea oldWidget) {
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
                  height: 1.375,
                  color: isInvalid ? t.destructive : null,
                ),
                child: Text(input.labelText!),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _TextareaSurface(
          enabled: input.enabled,
          invalid: isInvalid,
          focused: _focus.hasFocus,
          child: Semantics(
            container: true,
            label: input.labelText,
            isRequired: input.isRequired,
            validationResult: isInvalid
                ? SemanticsValidationResult.invalid
                : SemanticsValidationResult.none,
            child: TextField(
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
              minLines: input.minLines,
              maxLines: input.maxLines,
              scrollController: input.scrollController,
              scrollPhysics: input.scrollPhysics,
              textAlignVertical: TextAlignVertical.top,
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
        if (input.showCounter && input.maxLength != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              '${_controller.text.characters.length}/${input.maxLength}',
              style: style.copyWith(color: t.mutedForeground),
            ),
          ),
        ],
        if (error != null || input.helperText != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: error != null,
            child: Text(
              error ?? input.helperText!,
              style: style.copyWith(
                fontSize: DiscourseTypography.sm,
                height: 1.5,
                color: error == null ? t.mutedForeground : t.destructive,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TextareaSurface extends StatelessWidget {
  const _TextareaSurface({
    required this.child,
    required this.enabled,
    required this.invalid,
    required this.focused,
  });
  final Widget child;
  final bool enabled, invalid, focused;
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
    return MouseRegion(
      cursor: enabled ? MouseCursor.defer : SystemMouseCursors.forbidden,
      child: Opacity(
        opacity: enabled ? 1 : .5,
        child: IgnorePointer(
          ignoring: !enabled,
          child: AnimatedContainer(
            duration: DMotion.duration(
              context,
              const Duration(milliseconds: 150),
            ),
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            foregroundDecoration: _TextareaRingDecoration(
              color: invalid || focused ? ring : ring.withValues(alpha: 0),
              radius: t.radius,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Paint only the exterior annulus: a spread shadow would also tint the
/// translucent input fill. Keeping a Decoration preserves color interpolation.
class _TextareaRingDecoration extends Decoration {
  const _TextareaRingDecoration({required this.color, required this.radius});
  final Color color;
  final double radius;
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _TextareaRingPainter(this);
  @override
  Decoration? lerpFrom(Decoration? a, double t) => a is _TextareaRingDecoration
      ? _TextareaRingDecoration(
          color: Color.lerp(a.color, color, t)!,
          radius: a.radius + (radius - a.radius) * t,
        )
      : super.lerpFrom(a, t);
  @override
  Decoration? lerpTo(Decoration? b, double t) => b is _TextareaRingDecoration
      ? _TextareaRingDecoration(
          color: Color.lerp(color, b.color, t)!,
          radius: radius + (b.radius - radius) * t,
        )
      : super.lerpTo(b, t);
}

class _TextareaRingPainter extends BoxPainter {
  _TextareaRingPainter(this.decoration);
  final _TextareaRingDecoration decoration;
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
