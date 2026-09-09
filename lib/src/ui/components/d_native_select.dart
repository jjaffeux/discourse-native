import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_label.dart';

/// Plain text entries deliberately exclude custom rich/searchable Select UI.
sealed class DNativeSelectEntry<T> {
  const DNativeSelectEntry();
}

@immutable
class DNativeSelectOption<T> extends DNativeSelectEntry<T> {
  const DNativeSelectOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
}

@immutable
class DNativeSelectOptGroup<T> extends DNativeSelectEntry<T> {
  const DNativeSelectOptGroup({
    required this.label,
    required this.options,
    this.enabled = true,
  });

  final String label;
  final List<DNativeSelectOption<T>> options;
  final bool enabled;
}

enum DNativeSelectSize { small, standard }

/// A styled plain selection field using Flutter's menu overlay and keyboard
/// owner. The popup uses Flutter MenuAnchor conventions on iOS, macOS and Linux, not an
/// HTML select or an operating-system picker. See the component mapping document.
///
/// The ordinary constructor owns selection, initially [initialValue]. The
/// controlled constructor displays [value] and asks the caller to accept edits
/// through [onChanged]. In both modes Form.save/validate operate on the displayed
/// selection; Form.reset restores [initialValue] and notifies [onChanged]. In
/// controlled mode the caller must accept that reset notification as well.
/// Values must be unique, non-null, and present in [entries]. Null represents
/// the selectable [placeholder]. A null callback or [enabled] false disables
/// editing. Borrowed [focusNode] instances are never disposed.
class DNativeSelect<T extends Object> extends StatefulWidget {
  const DNativeSelect({
    super.key,
    required this.entries,
    required this.onChanged,
    this.initialValue,
    this.onSaved,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.forceErrorText,
    this.enabled = true,
    this.placeholder = 'Select an option',
    this.label,
    this.description,
    this.invalid = false,
    this.isRequired = false,
    this.size = DNativeSelectSize.standard,
    this.focusNode,
    this.autofocus = false,
  }) : value = null,
       _controlled = false;

  const DNativeSelect.controlled({
    super.key,
    required this.entries,
    required this.value,
    required this.onChanged,
    this.initialValue,
    this.onSaved,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.forceErrorText,
    this.enabled = true,
    this.placeholder = 'Select an option',
    this.label,
    this.description,
    this.invalid = false,
    this.isRequired = false,
    this.size = DNativeSelectSize.standard,
    this.focusNode,
    this.autofocus = false,
  }) : _controlled = true;

  final List<DNativeSelectEntry<T>> entries;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String placeholder;

  /// Visible, accessible name. Tapping it focuses the selection control.
  final String? label;
  final String? description;
  final bool invalid;
  final bool isRequired;
  final DNativeSelectSize size;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool _controlled;

  final T? initialValue;
  final FormFieldSetter<T>? onSaved;
  final FormFieldValidator<T>? validator;
  final AutovalidateMode autovalidateMode;
  final String? forceErrorText;
  final bool enabled;
  @override
  State<DNativeSelect<T>> createState() => _DNativeSelectHostState<T>();
}

class _DNativeSelectHostState<T extends Object>
    extends State<DNativeSelect<T>> {
  late final T? _initialValue = widget.initialValue;
  @override
  Widget build(BuildContext context) => _NativeSelectField<T>._(
    entries: widget.entries,
    onChanged: widget.onChanged,
    initialValue: _initialValue,
    value: widget.value,
    controlled: widget._controlled,
    onSaved: widget.onSaved == null
        ? null
        : (value) => widget.onSaved!(widget._controlled ? widget.value : value),
    validator: widget.validator == null
        ? null
        : (value) =>
              widget.validator!(widget._controlled ? widget.value : value),
    autovalidateMode: widget.autovalidateMode,
    forceErrorText: widget.forceErrorText,
    enabled: widget.enabled,
    placeholder: widget.placeholder,
    label: widget.label,
    description: widget.description,
    invalid: widget.invalid,
    isRequired: widget.isRequired,
    size: widget.size,
    focusNode: widget.focusNode,
    autofocus: widget.autofocus,
  );
}

class _NativeSelectField<T extends Object> extends FormField<T> {
  _NativeSelectField._({
    required this.entries,
    required this.onChanged,
    required this.value,
    required this.controlled,
    super.initialValue,
    super.onSaved,
    super.validator,
    super.autovalidateMode,
    super.forceErrorText,
    super.enabled,
    required this.placeholder,
    this.label,
    this.description,
    required this.invalid,
    required this.isRequired,
    required this.size,
    this.focusNode,
    required this.autofocus,
  }) : super(
         builder: (state) => (state as _NativeSelectFieldState<T>)._build(),
       );

  final List<DNativeSelectEntry<T>> entries;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String placeholder;

  /// Visible, accessible name. Tapping it focuses the selection control.
  final String? label;
  final String? description;
  final bool invalid;
  final bool isRequired;
  final DNativeSelectSize size;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool controlled;

  @override
  FormFieldState<T> createState() => _NativeSelectFieldState<T>();
}

class _NativeSelectFieldState<T extends Object> extends FormFieldState<T> {
  FocusNode? _ownedFocus;
  bool _focused = false;
  bool _hovered = false;
  final _menu = MenuController();
  final _anchorKey = GlobalKey();
  double _menuWidth = 200;
  final _rowFocus = <int, FocusNode>{};

  @override
  _NativeSelectField<T> get widget => super.widget as _NativeSelectField<T>;
  @override
  T? get value => widget.controlled ? widget.value : super.value;
  FocusNode get _focus => widget.focusNode ?? (_ownedFocus ??= FocusNode());
  bool get _showFocus =>
      _focused &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
  void _highlightChanged(FocusHighlightMode mode) {
    if (mounted) setState(() {});
  }

  bool get _enabled => widget.enabled && widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightChanged);
    if (widget.controlled) setValue(widget.value);
  }

  @override
  void didUpdateWidget(covariant _NativeSelectField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controlled && widget.value != super.value) {
      setValue(widget.value);
    }
  }

  @override
  void reset() {
    super.reset();
    if (widget.controlled) setValue(widget.value);
    widget.onChanged?.call(widget.initialValue);
  }

  void _change(T? next) {
    if (!_enabled) return;
    didChange(widget.controlled ? widget.value : next);
    widget.onChanged?.call(next);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightChanged);
    for (final node in _rowFocus.values) {
      node.dispose();
    }
    _ownedFocus?.dispose();
    super.dispose();
  }

  Widget _build() {
    final tokens = DTokens.of(context);
    final input = tokens.colors.outlineVariant;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final error = widget.invalid || hasError;
    final small = widget.size == DNativeSelectSize.small;
    final radius = small
        ? math.min(math.max(0.0, tokens.radius * 0.8), 10.0)
        : tokens.radius;
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: DiscourseTypography.lineHeightSmall,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: tokens.foreground,
    );
    final rows = <({T? value, String label, bool enabled, bool heading})>[
      (value: null, label: widget.placeholder, enabled: true, heading: false),
    ];
    final values = <T>{};
    for (final entry in widget.entries) {
      switch (entry) {
        case DNativeSelectOption<T>():
          assert(
            values.add(entry.value),
            'Native Select values must be unique',
          );
          rows.add((
            value: entry.value,
            label: entry.label,
            enabled: entry.enabled,
            heading: false,
          ));
        case DNativeSelectOptGroup<T>():
          rows.add((
            value: null,
            label: entry.label,
            enabled: false,
            heading: true,
          ));
          for (final option in entry.options) {
            assert(
              values.add(option.value),
              'Native Select values must be unique',
            );
            rows.add((
              value: option.value,
              label: option.label,
              enabled: entry.enabled && option.enabled,
              heading: false,
            ));
          }
      }
    }
    final selected = value == null
        ? 0
        : rows.indexWhere((row) => !row.heading && row.value == value);
    assert(selected >= 0, 'Native Select value must be present in entries');
    final border = error
        ? tokens.destructive.withValues(alpha: dark ? 0.5 : 1)
        : _showFocus
        ? tokens.focusRing
        : input;
    final ring = error
        ? tokens.destructive.withValues(alpha: dark ? 0.4 : 0.2)
        : tokens.focusRing.withValues(alpha: 0.5);
    final height = math.max(
      small ? 28.0 : 32.0,
      MediaQuery.textScalerOf(context).scale(14) * (20 / 14) + (small ? 6 : 10),
    );
    final touch =
        Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.android;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label case final label?) ...[
          GestureDetector(
            onTap: _enabled ? _focus.requestFocus : null,
            excludeFromSemantics: true,
            child: ExcludeSemantics(
              child: DLabel(enabled: _enabled, child: Text(label)),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Builder(
          builder: (context) {
            final width = _menuWidth;
            void open() {
              if (!_enabled) return;
              if (_menu.isOpen) {
                _menu.close();
                return;
              }
              final box =
                  _anchorKey.currentContext?.findRenderObject() as RenderBox?;
              if (box != null && box.hasSize) {
                setState(() => _menuWidth = box.size.width);
              }
              _menu.open();
              final index = selected >= 0 && rows[selected].enabled
                  ? selected
                  : rows.indexWhere((row) => row.enabled);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _menu.isOpen) _rowFocus[index]?.requestFocus();
              });
            }

            return MenuAnchor(
              controller: _menu,
              childFocusNode: _focus,
              consumeOutsideTap: true,
              crossAxisUnconstrained: false,
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(tokens.background),
                surfaceTintColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                minimumSize: WidgetStatePropertyAll(Size(width, 0)),
                maximumSize: WidgetStatePropertyAll(Size(width, 360)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 4),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
                alignment: AlignmentDirectional.bottomStart,
              ),
              menuChildren: [
                for (var i = 0; i < rows.length; i++)
                  Semantics(
                    header: rows[i].heading,
                    selected: rows[i].heading ? null : i == selected,
                    child: MenuItemButton(
                      focusNode: _rowFocus.putIfAbsent(i, () => FocusNode()),
                      onPressed: rows[i].enabled && _enabled
                          ? () => _change(rows[i].value)
                          : null,
                      style: ButtonStyle(
                        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        textStyle: WidgetStatePropertyAll(
                          style.copyWith(
                            fontWeight: rows[i].heading
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        foregroundColor: WidgetStatePropertyAll(
                          rows[i].enabled
                              ? tokens.foreground
                              : tokens.mutedForeground,
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) =>
                              states.contains(WidgetState.focused) ||
                                  states.contains(WidgetState.hovered)
                              ? tokens.hover
                              : Colors.transparent,
                        ),
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                      ),
                      child: SizedBox(
                        width: math.max(0, width - 24),
                        child: Text(rows[i].label),
                      ),
                    ),
                  ),
              ],
              builder: (context, controller, child) => Semantics(
                label: widget.label,
                value: rows[selected < 0 ? 0 : selected].label,
                button: true,
                expanded: controller.isOpen,
                enabled: _enabled,
                isRequired: widget.isRequired,
                validationResult: error
                    ? SemanticsValidationResult.invalid
                    : SemanticsValidationResult.none,
                onTap: _enabled ? open : null,
                child: FocusableActionDetector(
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  enabled: _enabled,
                  onShowFocusHighlight: (focused) =>
                      setState(() => _focused = focused),
                  onShowHoverHighlight: (hovered) =>
                      setState(() => _hovered = hovered),
                  mouseCursor: _enabled
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.forbidden,
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.arrowDown):
                        ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.arrowUp):
                        ActivateIntent(),
                  },
                  actions: {
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) {
                        open();
                        return null;
                      },
                    ),
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: _enabled ? open : null,
                    child: Opacity(
                      opacity: _enabled ? 1 : 0.5,
                      child: SizedBox(
                        key: _anchorKey,
                        height: touch ? math.max(48, height) : height,
                        child: Center(
                          child: Container(
                            height: height,
                            decoration: BoxDecoration(
                              color: dark
                                  ? input.withValues(
                                      alpha:
                                          input.a *
                                          (_hovered && _enabled ? 0.5 : 0.3),
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(radius),
                              border: Border.all(color: border),
                              boxShadow: [
                                if (error || _showFocus)
                                  BoxShadow(color: ring, spreadRadius: 3),
                              ],
                            ),
                            padding: const EdgeInsetsDirectional.only(
                              start: 9,
                              end: 9,
                            ),
                            child: ExcludeSemantics(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      rows[selected < 0 ? 0 : selected].label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: style,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  CustomPaint(
                                    size: const Size(16, 16),
                                    painter: _ChevronPainter(
                                      tokens.mutedForeground,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (errorText ?? widget.description case final detail?) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: hasError,
            child: Text(
              detail,
              style: style.copyWith(
                color: hasError ? tokens.destructive : tokens.mutedForeground,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16 / 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(4, 6)
        ..lineTo(8, 10)
        ..lineTo(12, 6),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => color != oldDelegate.color;
}
