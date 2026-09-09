import 'dart:math' as math;
import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// Accepts one ASCII digit per Input OTP slot.
final RegExp dInputOTPDigits = RegExp(r'^[0-9]$');

/// Accepts one ASCII letter or digit per Input OTP slot.
final RegExp dInputOTPAlphanumeric = RegExp(r'^[A-Za-z0-9]$');

typedef DInputOTPTransformer = String Function(String proposedValue);

/// A shadcn Input OTP composed around one real Flutter text editor.
///
/// Supply [controller], [value], or [initialValue]; these ownership modes are
/// mutually exclusive. The single editor preserves platform selection, paste,
/// IME and one-time-code autofill behavior. Slots are visual projections of
/// that editor rather than independent text fields. Borrowed controllers and
/// focus nodes are never disposed.
///
/// [inputTransformer] runs before [pattern] and [maxLength] filtering. This is
/// useful for upper-casing or stripping separators from pasted codes. [pattern]
/// must match one accepted character, not the complete code.
class DInputOTP extends FormField<String> {
  DInputOTP({
    super.key,
    required this.maxLength,
    this.controller,
    this.value,
    String? initialValue,
    this.focusNode,
    this.children,
    this.pattern,
    this.inputTransformer,
    this.onChanged,
    this.onCompleted,
    this.onSubmitted,
    this.semanticLabel,
    this.semanticHint,
    this.invalid = false,
    this.autofocus = false,
    this.readOnly = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.done,
    this.autofillHints = const [AutofillHints.oneTimeCode],
    this.contextMenuBuilder = _contextMenu,
    super.enabled = true,
    super.validator,
    super.onSaved,
    super.onReset,
    super.autovalidateMode,
  }) : assert(maxLength > 0),
       assert(controller == null || (initialValue == null && value == null)),
       assert(initialValue == null || value == null),
       super(
         initialValue: controller?.text ?? value ?? initialValue ?? '',
         builder: (state) => (state as _DInputOTPState)._build(),
       );

  final int maxLength;
  final TextEditingController? controller;
  final String? value;
  final FocusNode? focusNode;

  /// Visual anatomy. Defaults to one group containing [maxLength] slots.
  final List<Widget>? children;
  final RegExp? pattern;
  final DInputOTPTransformer? inputTransformer;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onSubmitted;
  final String? semanticLabel;
  final String? semanticHint;
  final bool invalid;
  final bool autofocus;
  final bool readOnly;

  /// The platform keyboard to request. Defaults to a numeric keypad; use
  /// [TextInputType.text] for alphanumeric codes.
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  static Widget _contextMenu(BuildContext context, EditableTextState state) {
    if (SystemContextMenu.isSupportedByField(state)) {
      return SystemContextMenu.editableText(editableTextState: state);
    }
    return AdaptiveTextSelectionToolbar.editableText(editableTextState: state);
  }

  @override
  FormFieldState<String> createState() => _DInputOTPState();
}

class _DInputOTPState extends FormFieldState<String> {
  TextEditingController? _ownedController;
  FocusNode? _ownedFocus;
  late final String _resetValue;
  bool _syncing = false;
  String _lastText = '';
  Offset? _primaryPointerDown;

  DInputOTP get input => widget as DInputOTP;
  TextEditingController get _controller =>
      input.controller ?? _ownedController!;
  FocusNode get _focus => input.focusNode ?? _ownedFocus!;

  TextInputFormatter get _formatter => _DInputOTPFormatter(
    maxLength: input.maxLength,
    pattern: input.pattern,
    transformer: input.inputTransformer,
  );

  @override
  void initState() {
    super.initState();
    _resetValue = _sanitize(widget.initialValue ?? '');
    _lastText = _resetValue;
    if (input.controller == null) {
      _ownedController = TextEditingController(text: _resetValue);
    } else if (_controller.text != _resetValue) {
      _replace(_resetValue);
    }
    setValue(_resetValue);
    if (input.focusNode == null) _ownedFocus = FocusNode();
    _controller.addListener(_editingChanged);
    _focus.addListener(_focusChanged);
  }

  String _sanitize(String value) => _DInputOTPFormatter.filter(
    value,
    maxLength: input.maxLength,
    pattern: input.pattern,
    transformer: input.inputTransformer,
  );

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _editingChanged() {
    if (_syncing) return;
    var editingValue = _controller.value;
    final sanitized = _sanitize(editingValue.text);
    if (sanitized != editingValue.text) {
      _replace(sanitized);
      editingValue = _controller.value;
    }
    if (editingValue.text == _lastText) {
      if (mounted) setState(() {});
      return;
    }
    final previousLength = _lastText.length;
    _lastText = editingValue.text;
    super.didChange(editingValue.text);
    input.onChanged?.call(editingValue.text);
    if (editingValue.text.length == input.maxLength &&
        previousLength != input.maxLength) {
      input.onCompleted?.call(editingValue.text);
    }
  }

  @override
  void didUpdateWidget(covariant DInputOTP oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != input.controller) {
      final previous = oldWidget.controller ?? _ownedController!;
      final editingValue = previous.value;
      previous.removeListener(_editingChanged);
      if (input.controller == null) {
        _ownedController = TextEditingController.fromValue(editingValue);
      } else {
        _ownedController?.dispose();
        _ownedController = null;
      }
      _controller.addListener(_editingChanged);
      final next = _sanitize(_controller.text);
      if (next != _controller.text) _replace(next);
      _lastText = next;
      setValue(next);
    }
    if (oldWidget.focusNode != input.focusNode) {
      (oldWidget.focusNode ?? _ownedFocus!).removeListener(_focusChanged);
      _ownedFocus?.dispose();
      _ownedFocus = input.focusNode == null ? FocusNode() : null;
      _focus.addListener(_focusChanged);
    }
    if (input.value != null && input.value != _controller.text) {
      final next = _sanitize(input.value!);
      _replace(next);
      setValue(next);
    } else if (oldWidget.maxLength != input.maxLength ||
        oldWidget.pattern != input.pattern ||
        oldWidget.inputTransformer != input.inputTransformer) {
      final next = _sanitize(_controller.text);
      if (next != _controller.text) _replace(next);
      setValue(next);
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
    _lastText = text;
    _syncing = false;
  }

  @override
  void didChange(String? value) {
    final next = _sanitize(value ?? '');
    super.didChange(next);
    if (_controller.text != next) _replace(next);
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
    _controller.removeListener(_editingChanged);
    _focus.removeListener(_focusChanged);
    _ownedController?.dispose();
    _ownedFocus?.dispose();
    super.dispose();
  }

  void _selectFromPointer(PointerEvent event, double width, TextDirection dir) {
    if (!input.enabled || input.readOnly || width <= 0) return;
    final logicalX = dir == TextDirection.rtl
        ? width - event.localPosition.dx
        : event.localPosition.dx;
    final offset = (logicalX / width * input.maxLength).floor().clamp(
      0,
      _controller.text.length,
    );
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.selection = TextSelection.collapsed(offset: offset);
    });
  }

  void _pointerDown(PointerDownEvent event) {
    _primaryPointerDown = event.buttons == 1 ? event.position : null;
  }

  void _pointerMove(PointerMoveEvent event) {
    final down = _primaryPointerDown;
    if (down != null && (event.position - down).distance > 4) {
      _primaryPointerDown = null;
    }
  }

  void _pointerUp(PointerUpEvent event, double width, TextDirection direction) {
    final down = _primaryPointerDown;
    _primaryPointerDown = null;
    if (down != null && (event.position - down).distance <= 4) {
      _selectFromPointer(event, width, direction);
    }
  }

  Widget _build() {
    final direction = Directionality.of(context);
    final invalid = input.invalid || errorText != null;
    final visualChildren =
        input.children ??
        [
          DInputOTPGroup(
            children: List.generate(
              input.maxLength,
              (index) => DInputOTPSlot(index: index),
            ),
          ),
        ];
    final scope = _DInputOTPScope(
      value: _controller.value,
      maxLength: input.maxLength,
      focused: _focus.hasFocus,
      enabled: input.enabled,
      invalid: invalid,
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: visualChildren),
      ),
    );

    return Opacity(
      opacity: input.enabled ? 1 : .5,
      child: MergeSemantics(
        child: Semantics(
          container: true,
          label: input.semanticLabel,
          hint: input.semanticHint,
          enabled: input.enabled,
          readOnly: input.readOnly,
          validationResult: invalid
              ? SemanticsValidationResult.invalid
              : SemanticsValidationResult.none,
          child: Builder(
            builder: (context) => Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _pointerDown,
                    onPointerMove: _pointerMove,
                    onPointerCancel: (_) => _primaryPointerDown = null,
                    onPointerUp: (event) =>
                        _pointerUp(event, context.size?.width ?? 0, direction),
                    child: TextSelectionTheme(
                      data: const TextSelectionThemeData(
                        cursorColor: Colors.transparent,
                        selectionColor: Colors.transparent,
                        selectionHandleColor: Colors.transparent,
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        enabled: input.enabled,
                        readOnly: input.readOnly,
                        autofocus: input.autofocus,
                        showCursor: false,
                        style: const TextStyle(color: Colors.transparent),
                        cursorColor: Colors.transparent,
                        keyboardType:
                            input.keyboardType ?? TextInputType.number,
                        textInputAction: input.textInputAction,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        enableSuggestions: false,
                        enableInteractiveSelection: true,
                        maxLines: 1,
                        inputFormatters: [_formatter],
                        autofillHints: input.autofillHints,
                        contextMenuBuilder: input.contextMenuBuilder,
                        onSubmitted: input.onSubmitted,
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(child: scope),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DInputOTPFormatter extends TextInputFormatter {
  const _DInputOTPFormatter({
    required this.maxLength,
    this.pattern,
    this.transformer,
  });

  final int maxLength;
  final RegExp? pattern;
  final DInputOTPTransformer? transformer;

  static String filter(
    String proposed, {
    required int maxLength,
    RegExp? pattern,
    DInputOTPTransformer? transformer,
  }) {
    final transformed = transformer?.call(proposed) ?? proposed;
    final output = StringBuffer();
    var count = 0;
    for (final rune in transformed.runes) {
      if (count == maxLength) break;
      final character = String.fromCharCode(rune);
      if (pattern == null || pattern.hasMatch(character)) {
        output.write(character);
        count++;
      }
    }
    return output.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = filter(
      newValue.text,
      maxLength: maxLength,
      pattern: pattern,
      transformer: transformer,
    );
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _DInputOTPScope extends InheritedWidget {
  const _DInputOTPScope({
    required this.value,
    required this.maxLength,
    required this.focused,
    required this.enabled,
    required this.invalid,
    required super.child,
  });

  final TextEditingValue value;
  final int maxLength;
  final bool focused;
  final bool enabled;
  final bool invalid;

  static _DInputOTPScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DInputOTPScope>();

  @override
  bool updateShouldNotify(_DInputOTPScope oldWidget) =>
      value != oldWidget.value ||
      maxLength != oldWidget.maxLength ||
      focused != oldWidget.focused ||
      enabled != oldWidget.enabled ||
      invalid != oldWidget.invalid;
}

class _DInputOTPGroupScope extends InheritedWidget {
  const _DInputOTPGroupScope({
    required this.position,
    required this.count,
    required super.child,
  });
  final int position;
  final int count;
  static _DInputOTPGroupScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DInputOTPGroupScope>();
  @override
  bool updateShouldNotify(_DInputOTPGroupScope oldWidget) =>
      position != oldWidget.position || count != oldWidget.count;
}

/// Joins adjacent [DInputOTPSlot] borders into one rounded slot group.
class DInputOTPGroup extends StatelessWidget {
  const DInputOTPGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final invalid =
        _DInputOTPScope.maybeOf(context)?.invalid == true ||
        children.any((child) => child is DInputOTPSlot && child.invalid);
    final t = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ring = t.destructive.withValues(
      alpha: t.destructive.a * (dark ? .4 : .2),
    );
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: _OTPRingDecoration(
        color: invalid ? ring : ring.withValues(alpha: 0),
        radius: t.radius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < children.length; index++)
            _DInputOTPGroupScope(
              position: index,
              count: children.length,
              child: children[index],
            ),
        ],
      ),
    );
  }
}

/// A visual character slot backed by its ancestor [DInputOTP]'s editor.
class DInputOTPSlot extends StatelessWidget {
  const DInputOTPSlot({
    super.key,
    required this.index,
    this.invalid = false,
    this.width = 32,
    this.height = 32,
    this.fontSize = DiscourseTypography.sm,
    this.lineHeight,
  }) : assert(index >= 0),
       assert(width > 0),
       assert(height > 0),
       assert(lineHeight == null || lineHeight > 0);

  final int index;
  final bool invalid;
  final double width;
  final double height;
  final double fontSize;
  final double? lineHeight;

  @override
  Widget build(BuildContext context) {
    final scope = _DInputOTPScope.maybeOf(context);
    final group = _DInputOTPGroupScope.maybeOf(context);
    final t = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final direction = Directionality.of(context);
    final text = scope?.value.text ?? '';
    final selection = scope?.value.selection;
    final caretOffset = selection?.isValid == true
        ? selection!.extentOffset.clamp(0, text.length)
        : text.length;
    final active =
        scope?.focused == true &&
        (caretOffset == index ||
            (caretOffset == text.length &&
                text.length == scope?.maxLength &&
                index == text.length - 1));
    final showCaret = active && index >= text.length;
    final isInvalid = invalid || scope?.invalid == true;
    final char = index < text.length ? text[index] : '';
    final first = group == null || group.position == 0;
    final last = group == null || group.position == group.count - 1;
    final startRadius = first ? t.radius : 0.0;
    final endRadius = last ? t.radius : 0.0;
    final radius = direction == TextDirection.ltr
        ? BorderRadius.horizontal(
            left: Radius.circular(startRadius),
            right: Radius.circular(endRadius),
          )
        : BorderRadius.horizontal(
            left: Radius.circular(endRadius),
            right: Radius.circular(startRadius),
          );
    final borderColor = isInvalid
        ? t.destructive.withValues(alpha: t.destructive.a * (dark ? .5 : 1))
        : active
        ? t.focusRing
        : t.colors.outlineVariant;
    final ring = isInvalid
        ? t.destructive.withValues(alpha: t.destructive.a * (dark ? .4 : .2))
        : t.focusRing.withValues(alpha: t.focusRing.a * .5);
    final scaler = MediaQuery.textScalerOf(context);
    final resolvedLineHeight = lineHeight ?? fontSize * (20 / 14);
    final scaledLineHeight = scaler.scale(resolvedLineHeight);
    final effectiveHeight = math.max(height, scaledLineHeight + 12);
    // A Latin OTP glyph is roughly .6em wide. Preserve the 32/44px source
    // widths until the scaled glyph would actually collide with its inset.
    final effectiveWidth = math.max(width, scaler.scale(fontSize * .6) + 12);

    return AnimatedContainer(
      duration: DMotion.duration(context, const Duration(milliseconds: 150)),
      width: effectiveWidth,
      height: effectiveHeight,
      decoration: BoxDecoration(
        color: dark
            ? t.colors.outlineVariant.withValues(
                alpha: t.colors.outlineVariant.a * .3,
              )
            : Colors.transparent,
        borderRadius: radius,
        border: Border(
          top: BorderSide(color: borderColor),
          bottom: BorderSide(color: borderColor),
          left:
              first && direction == TextDirection.ltr ||
                  last && direction == TextDirection.rtl
              ? BorderSide(color: borderColor)
              : BorderSide.none,
          right: BorderSide(color: borderColor),
        ),
      ),
      foregroundDecoration: _OTPRingDecoration(
        color: active ? ring : ring.withValues(alpha: 0),
        radius: math.max(startRadius, endRadius),
      ),
      alignment: Alignment.center,
      child: char.isNotEmpty
          ? Text(
              char,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: t.foreground,
                fontSize: fontSize,
                height: resolvedLineHeight / fontSize,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            )
          : showCaret
          ? _DInputOTPCaret(color: t.foreground)
          : null,
    );
  }
}

class _DInputOTPCaret extends StatefulWidget {
  const _DInputOTPCaret({required this.color});
  final Color color;
  @override
  State<_DInputOTPCaret> createState() => _DInputOTPCaretState();
}

class _DInputOTPCaretState extends State<_DInputOTPCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _controller,
    child: SizedBox(
      width: 1,
      height: 16,
      child: ColoredBox(color: widget.color),
    ),
  );
}

/// The 16px shadcn minus separator between OTP groups.
class DInputOTPSeparator extends StatelessWidget {
  const DInputOTPSeparator({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Padding(
      padding: padding,
      child: CustomPaint(
        size: const Size.square(16),
        painter: _OTPSeparatorPainter(DTokens.of(context).foreground),
      ),
    ),
  );
}

class _OTPSeparatorPainter extends CustomPainter {
  const _OTPSeparatorPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(3, size.height / 2),
      Offset(size.width - 3, size.height / 2),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_OTPSeparatorPainter oldDelegate) =>
      color != oldDelegate.color;
}

class _OTPRingDecoration extends Decoration {
  const _OTPRingDecoration({required this.color, required this.radius});
  final Color color;
  final double radius;
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _OTPRingPainter(this);
}

class _OTPRingPainter extends BoxPainter {
  const _OTPRingPainter(this.decoration);
  final _OTPRingDecoration decoration;
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || decoration.color.a == 0) return;
    final outer = RRect.fromRectAndRadius(
      (offset - const Offset(3, 3)) & Size(size.width + 6, size.height + 6),
      Radius.circular(decoration.radius + 3),
    );
    final inner = RRect.fromRectAndRadius(
      offset & size,
      Radius.circular(decoration.radius),
    );
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outer)
      ..addRRect(inner);
    canvas.drawPath(path, Paint()..color = decoration.color);
  }
}
