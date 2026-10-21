import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/control_style.dart';
import '../foundation/focus_highlight.dart';
import '../foundation/input_group_scope.dart';
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
/// The box is editable edge to edge: its padding takes the text cursor, focuses
/// the editor and invokes [onTap]. There is no browser resize grip; content
/// growth and optional line bounds keep native layouts usable without adding
/// an independent resize interaction.
class DTextarea extends FormField<String> {
  DTextarea({
    super.key,
    this.controller,

    this.focusNode,
    this.labelText,
    this.semanticLabel,
    this.hintText,

    this.errorText,

    this.onChanged,

    this.keyboardType = TextInputType.multiline,

    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,

    this.autocorrect = true,
    this.enableSuggestions = true,

    this.minLines = 1,
    this.maxLines,

    this.maxLength,
    this.maxLengthEnforcement,

    super.enabled = true,

    super.validator,
  }) : assert(maxLength == null || maxLength > 0),
       assert(minLines > 0),
       assert(maxLines == null || maxLines >= minLines),
       super(
         initialValue: ((controller?.text)) ?? '',
         builder: (state) => (state as _DTextareaState)._build(),
       );

  final TextEditingController? controller;

  final FocusNode? focusNode;
  final String? labelText, semanticLabel, hintText, errorText;

  final ValueChanged<String>? onChanged;

  final TextInputType? keyboardType;

  final TextCapitalization textCapitalization;
  final bool autofocus;
  final int minLines;
  final int? maxLines;

  final bool autocorrect, enableSuggestions;

  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;

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
  DInputGroupControlScope? _group;
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

  void _tapSurface() {
    _focus.requestFocus();
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
    final isInvalid = (error != null);
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final fontSize = touch ? DiscourseTypography.base : DiscourseTypography.sm;
    final style =
        _group?.editorStyle ??
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
    final editor = Semantics(
      container: true,
      label: input.semanticLabel ?? input.labelText,
      isRequired: false,
      validationResult: isInvalid
          ? SemanticsValidationResult.invalid
          : SemanticsValidationResult.none,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: enabled,
        readOnly: false,
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
        cursorOpacityAnimates: DControlStyle.caretOpacityAnimates,
        keyboardType: input.keyboardType,
        textInputAction: TextInputAction.newline,
        textCapitalization: input.textCapitalization,
        minLines: input.minLines,
        maxLines: input.maxLines,
        scrollController: null,
        scrollPhysics: null,
        textAlignVertical: TextAlignVertical.top,
        autocorrect: input.autocorrect,
        enableSuggestions: input.enableSuggestions,
        enableInteractiveSelection: true,
        inputFormatters: null,
        autofillHints: null,
        maxLength: input.maxLength,
        maxLengthEnforcement: input.maxLengthEnforcement,
        textAlign: TextAlign.start,
        textDirection: null,
        undoController: null,
        contextMenuBuilder: DTextarea._contextMenu,
        onChanged: input.onChanged,
        onSubmitted: null,
        onEditingComplete: null,
        onTap: null,
        onTapOutside: null,
      ),
    );
    if (group != null) {
      return Padding(padding: group.inputPadding, child: editor);
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
          onTap: _tapSurface,
          child: editor,
        ),

        if ((error != null)) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: style.copyWith(
                fontSize: DiscourseTypography.sm,
                height: 1.5,
                color: t.destructive,
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
    required this.onTap,
  });
  final Widget child;
  final bool enabled, invalid, focused;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = invalid
        ? t.destructive.withValues(alpha: t.destructive.a * (dark ? .5 : 1))
        : focused && DFocusHighlight.visibleOf(context)
        ? t.focusRing
        : DControlStyle.outlineBorder(t, dark: dark, field: true);
    final ring = invalid
        ? t.destructive.withValues(alpha: t.destructive.a * (dark ? .4 : .2))
        : focused && DFocusHighlight.visibleOf(context)
        ? t.focusRing.withValues(alpha: t.focusRing.a * .5)
        : null;
    // The editor's own recognizers win presses inside it; the surface only
    // claims the padding, which the reference box also makes editable.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onTap: enabled ? onTap : null,
      child: MouseRegion(
        cursor: enabled
            ? SystemMouseCursors.text
            : SystemMouseCursors.forbidden,
        child: Opacity(
          opacity: enabled ? 1 : .5,
          child: IgnorePointer(
            ignoring: !enabled,
            // transition-colors eases the border and fill; the ring is a box
            // shadow outside that property list, so it paints at once.
            child: CustomPaint(
              foregroundPainter: ring == null
                  ? null
                  : _TextareaRing(color: ring, radius: t.controlRadius),
              child: AnimatedContainer(
                duration: DMotion.duration(
                  context,
                  const Duration(milliseconds: 150),
                ),
                curve: Curves.fastOutSlowIn,
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: DControlStyle.fieldFill(
                    t,
                    dark: dark,
                    enabled: enabled,
                  ),
                  borderRadius: BorderRadius.circular(t.controlRadius),
                  border: Border.all(color: border),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints only the exterior annulus: a spread shadow would also tint the
/// translucent input fill behind the text.
class _TextareaRing extends CustomPainter {
  const _TextareaRing({required this.color, required this.radius});
  final Color color;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final inner = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawDRRect(inner.inflate(3), inner, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TextareaRing oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
