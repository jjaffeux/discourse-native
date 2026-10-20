import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_label.dart';

/// Complete reading-order choices for a radio group with lazily mounted rows.
///
/// [values] and [disabledValues] are immutable snapshots. Change [revision]
/// when a query or data owner changes even if the returned values are equal.
/// [reveal] mounts an offscreen value and completes after its layout. Check
/// `isCurrent()` before scrolling and after every await so superseded navigation
/// cannot move a replacement list. The group retains selection and focus policy.
class DRadioGroupNavigation<T> {
  DRadioGroupNavigation({
    required Iterable<T> values,
    required this.reveal,
    Iterable<T> disabledValues = const [],
    this.revision,
  }) : values = List.unmodifiable(values),
       disabledValues = Set.unmodifiable(disabledValues) {
    assert(this.values.toSet().length == this.values.length);
    assert(this.disabledValues.every(this.values.contains));
  }

  final List<T> values;
  final Set<T> disabledValues;
  final Object? revision;
  final Future<void> Function(T value, bool Function() isCurrent) reveal;
}

typedef _RadioItem<T> = ({
  T value,
  bool readOnly,
  bool enabled,
  bool toggleable,
  FocusNode focus,
});

/// A single selection with native radio roving focus and Form integration.
///
/// The default constructor owns selection initialized by [initialValue]. Use
/// [DRadioGroup.controlled] when a parent owns [groupValue]. Reset restores
/// the mounted [initialValue] and notifies [onChanged]. Controlled reset proposes
/// that baseline while Form continues to observe the accepted [groupValue].
/// Children may be laid out freely and compose [DRadioGroupItem] with Field
/// widgets; the reference root is a `grid gap-2`, so stack items with an
/// 8 logical pixel gap unless a Field composition supplies its own. Item
/// values must be distinct within the group.
class DRadioGroup<T> extends FormField<T> {
  DRadioGroup({
    super.key,
    super.initialValue,
    this.onChanged,
    required this.child,
    this.label,
    this.navigation,

    super.enabled = true,
  }) : groupValue = null,
       _controlled = false,
       super(builder: (state) => (state as _DRadioGroupState<T>)._build());

  DRadioGroup.controlled({
    super.key,
    required this.groupValue,
    required this.onChanged,
    required this.child,
    super.initialValue,
    this.label,
    this.navigation,

    super.enabled = true,
  }) : _controlled = true,
       super(builder: (state) => (state as _DRadioGroupState<T>)._build());

  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget child;
  final Widget? label;

  /// Optional complete choice metadata and reveal owner for a lazy viewport.
  /// Without it, mounted children retain Flutter's normal radio navigation.
  final DRadioGroupNavigation<T>? navigation;

  final bool _controlled;

  @override
  FormFieldState<T> createState() => _DRadioGroupState<T>();
}

class _DRadioGroupState<T> extends FormFieldState<T> {
  final _items = <Object, _RadioItem<T>>{};
  final _navigationFocus = FocusNode(debugLabel: 'DRadioGroup navigation');
  ({T value})? _cursor;
  int _navigationGeneration = 0;
  final _contentKey = GlobalKey();
  late final T? _initialValue;
  @override
  DRadioGroup<T> get widget => super.widget as DRadioGroup<T>;

  @override
  void initState() {
    super.initState();
    _initialValue = widget.initialValue;
    if (widget._controlled) setValue(widget.groupValue);
  }

  @override
  void didUpdateWidget(covariant DRadioGroup<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._controlled) setValue(widget.groupValue);
    final previous = oldWidget.navigation;
    final next = widget.navigation;
    if (previous?.revision != next?.revision ||
        !listEquals(previous?.values, next?.values) ||
        !setEquals(previous?.disabledValues, next?.disabledValues) ||
        oldWidget.enabled != widget.enabled ||
        oldWidget._controlled != widget._controlled ||
        (oldWidget.onChanged == null) != (widget.onChanged == null) ||
        (widget._controlled &&
            oldWidget.groupValue != widget.groupValue &&
            (_cursor == null || widget.groupValue != _cursor!.value))) {
      _retireNavigation();
    }
  }

  @override
  void dispose() {
    _retireNavigation();
    _navigationFocus.dispose();
    super.dispose();
  }

  bool get _enabled =>
      widget.enabled && (!widget._controlled || widget.onChanged != null);
  T? get _selection => widget._controlled ? widget.groupValue : value;

  void _retireNavigation() {
    ++_navigationGeneration;
    _cursor = null;
  }

  void _itemFocused(T value) {
    if (_cursor?.value == value) return;
    _retireNavigation();
    _cursor = (value: value);
  }

  void _select(T? next, {bool navigating = false}) {
    final target = next ?? _selection;
    final item = _items.values
        .where((item) => item.value == target)
        .firstOrNull;
    final navigation = widget.navigation;
    if (!_enabled ||
        (item?.readOnly ?? false) ||
        (navigation != null &&
            (!navigation.values.contains(target) ||
                navigation.disabledValues.contains(target)))) {
      return;
    }
    if (!navigating) {
      _retireNavigation();
    }
    didChange(next);
    widget.onChanged?.call(next);
  }

  KeyEventResult _navigationKey(FocusNode node, KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed ||
        !_enabled) {
      return KeyEventResult.ignored;
    }
    final focused = _items.values
        .where((item) => item.focus.hasFocus)
        .firstOrNull;
    if (focused == null && !_navigationFocus.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final forward = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.arrowRight => true,
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.arrowLeft => false,
      _ => null,
    };
    if (forward == null) {
      if (event.logicalKey == LogicalKeyboardKey.space &&
          _navigationFocus.hasPrimaryFocus &&
          _cursor != null) {
        unawaited(_revealAndFocus(_cursor!.value, activate: true));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final navigation = widget.navigation!;
    final source = _cursor?.value ?? focused?.value ?? _selection;
    var index = navigation.values.indexWhere((value) => value == source);
    if (index < 0 && !forward) index = 0;
    for (var attempt = 0; attempt < navigation.values.length; attempt++) {
      index = (index + (forward ? 1 : -1)) % navigation.values.length;
      final target = navigation.values[index];
      if (navigation.disabledValues.contains(target)) continue;
      _cursor = (value: target);
      unawaited(_revealAndFocus(target, forward: forward));
      break;
    }
    return KeyEventResult.handled;
  }

  Future<void> _revealAndFocus(
    T target, {
    bool forward = true,
    bool activate = false,
  }) async {
    final generation = ++_navigationGeneration;
    bool current() =>
        mounted &&
        generation == _navigationGeneration &&
        _enabled &&
        _navigationFocus.hasFocus;
    final navigation = widget.navigation!;
    if (!activate) _select(target, navigating: true);
    if (!current()) return;
    var item = _items.values.where((item) => item.value == target).firstOrNull;
    if (item == null) {
      _navigationFocus.requestFocus();
      await navigation.reveal(target, current);
      if (!current()) return;
      item = _items.values.where((item) => item.value == target).firstOrNull;
    }
    final itemContext = item?.focus.context;
    if (item == null ||
        !item.enabled ||
        itemContext == null ||
        !itemContext.mounted) {
      return;
    }
    await Scrollable.ensureVisible(
      itemContext,
      alignmentPolicy: forward
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    if (!current()) return;
    item.focus.requestFocus();
    if (activate) {
      _select(item.toggleable && _selection == target ? null : target);
    }
  }

  @override
  void didChange(T? value) {
    // Form observers must never save or validate an unaccepted proposal.
    super.didChange(widget._controlled ? widget.groupValue : value);
  }

  @override
  void reset() {
    _retireNavigation();
    setValue(widget._controlled ? widget.groupValue : _initialValue);
    // Clear validation/interaction state and notify Form only after restoring
    // the accepted value. super.reset() would publish the latest initialValue.
    super.clearError();
    widget.onChanged?.call(_initialValue);
  }

  Widget _build() {
    final tokens = DTokens.of(context);
    final enabled = _enabled;
    final selection = _selection;
    Widget result = _RadioScope<T>(
      key: _contentKey,
      items: _items,
      onItemFocused: widget.navigation == null ? null : _itemFocused,
      enabled: enabled,
      invalid: (hasError),
      errorText: errorText,
      child: RadioGroup<T>(
        groupValue: selection,
        onChanged: _select,
        child: widget.navigation == null
            ? widget.child
            : Focus(
                focusNode: _navigationFocus,
                skipTraversal: true,
                onKeyEvent: _navigationKey,
                onFocusChange: (focused) {
                  if (!focused) _retireNavigation();
                },
                child: widget.child,
              ),
      ),
    );
    if ((widget.label != null) || hasError) {
      result = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.label != null) ...[
            DLabel(
              style: const TextStyle(height: 20 / 14),
              child: widget.label!,
            ),
            const SizedBox(height: 12),
          ],

          result,
          if (errorText case final message?) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: TextStyle(
                  fontSize: DiscourseTypography.sm,
                  color: tokens.destructive,
                ),
              ),
            ),
          ],
        ],
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      isRequired: null,
      child: result,
    );
  }
}

class _RadioScope<T> extends InheritedWidget {
  const _RadioScope({
    super.key,
    required this.enabled,
    required this.invalid,
    required this.errorText,

    required this.items,
    required this.onItemFocused,
    required super.child,
  });
  final bool enabled;
  final bool invalid;
  final String? errorText;

  final Map<Object, _RadioItem<T>> items;
  final ValueChanged<T>? onItemFocused;
  @override
  bool updateShouldNotify(_RadioScope<T> oldWidget) =>
      ((enabled != oldWidget.enabled ||
          invalid != oldWidget.invalid ||
          errorText != oldWidget.errorText)) ||
      items != oldWidget.items;
}

/// One radio, optionally with an associated label and description.
///
/// The entire label row activates the radio and has one focus/semantics owner.
/// Keep independent links outside [label] and [description]. A bare item needs
/// [semanticLabel]. Borrowed [focusNode] is never disposed by this widget.
/// A bare item's hit area is its 16px circle. An associated label or Field row
/// activates the complete visible choice. Like the reference, the pointer cursor
/// stays the default arrow, Space is the only activation key and Enter is
/// inert; label slots activate through [ActivateIntent] rather than a key.
class DRadioGroupItem<T> extends StatefulWidget {
  const DRadioGroupItem({
    super.key,
    required this.value,
    this.label,
    this.description,
    this.trailing,
    this.semanticLabel,
    this.enabled = true,

    this.card = false,
    this.toggleable = false,
  }) : assert(label != null || semanticLabel != null);

  final T value;
  final Widget? label;
  final Widget? description;
  final Widget? trailing;
  final String? semanticLabel;
  final bool enabled;

  /// A clickable choice card, with content before the radio in reading order.
  final bool card;

  /// Allow deselection for domains such as withdrawing a Poll vote.
  final bool toggleable;

  @override
  State<DRadioGroupItem<T>> createState() => _DRadioGroupItemState<T>();
}

class _DRadioGroupItemState<T> extends State<DRadioGroupItem<T>>
    with AutomaticKeepAliveClientMixin {
  late FocusNode _focus;
  bool _hovered = false;
  _RadioScope<T>? _scope;
  @override
  void initState() {
    super.initState();
    _attach();
    FocusManager.instance.addHighlightModeListener(_highlightChanged);
  }

  void _attach() {
    _focus = (FocusNode());
    _focus.addListener(_focusChanged);
  }

  @override
  bool get wantKeepAlive => _scope?.onItemFocused != null && _focus.hasFocus;

  void _focusChanged() {
    updateKeepAlive();
    if (_focus.hasFocus) _scope?.onItemFocused?.call(widget.value);
    _changed();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _highlightChanged(FocusHighlightMode mode) => _changed();
  void _detach() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
  }

  @override
  void didUpdateWidget(covariant DRadioGroupItem<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightChanged);
    _scope?.items.remove(this);
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scope = context.dependOnInheritedWidgetOfExactType<_RadioScope<T>>();
    if (_scope?.items != scope?.items) _scope?.items.remove(this);
    _scope = scope;
    const readOnly = false;
    scope?.items[this] = (
      value: widget.value,
      readOnly: readOnly,
      enabled: widget.enabled,
      toggleable: widget.toggleable,
      focus: _focus,
    );
    final registry = RadioGroup.maybeOf<T>(context);
    assert(
      registry != null,
      'DRadioGroupItem requires a DRadioGroup of the same type.',
    );
    final enabled = widget.enabled && (scope?.enabled ?? true);
    final invalid = ((scope?.invalid ?? false));
    final tokens = DTokens.of(context);
    final checked = registry?.groupValue == widget.value;
    final focused =
        _focus.hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = checked
        ? tokens.primary
        : invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? 0.5 : 1),
          )
        : focused
        ? tokens.focusRing
        : tokens.colors.outlineVariant;
    final ring = invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? 0.4 : 0.2),
          )
        : tokens.focusRing.withValues(alpha: tokens.focusRing.a * 0.5);
    final indicator = Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked
            ? tokens.primary
            : dark
            ? tokens.colors.outlineVariant.withValues(
                alpha: tokens.colors.outlineVariant.a * 0.3,
              )
            : Colors.transparent,
        border: Border.all(color: border),
      ),
      foregroundDecoration: invalid || focused
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ring,
                width: 3,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            )
          : null,
      child: checked
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.primaryForeground,
                ),
              ),
            )
          : null,
    );
    Widget content = indicator;
    if (widget.label != null) {
      final text = Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DLabel(
              style: TextStyle(
                height: widget.card
                    ? 20 / 14
                    : widget.description != null
                    ? 1.375
                    : 1,
                color: invalid ? tokens.destructive : null,
              ).merge(null),
              child: widget.label!,
            ),
            if (widget.description != null) ...[
              const SizedBox(height: 2),
              DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: DiscourseTypography.sm,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                  color: tokens.mutedForeground,
                ),
                child: widget.description!,
              ),
            ],
          ],
        ),
      );
      final radio = widget.description != null || widget.card
          ? Padding(padding: const EdgeInsets.only(top: 1), child: indicator)
          : indicator;
      final gap = ((widget.description != null || widget.card ? 8.0 : 12.0));
      content = Row(
        crossAxisAlignment: widget.description != null || widget.card
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (!widget.card) ...[radio, SizedBox(width: gap)],
          text,
          if (widget.trailing != null) ...[
            const SizedBox(width: 12),
            widget.trailing!,
          ],
          if (widget.card) ...[SizedBox(width: gap), radio],
        ],
      );
    }
    if (widget.card) {
      // Hovering a card that a click would select previews the selected
      // treatment at half strength, so the target reads as a choice rather
      // than a surface; the selected card keeps its own tint.
      final previewing = (enabled) && !checked && _hovered;
      content = Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radius),
          border: Border.all(
            color: focused
                ? tokens.focusRing
                : checked || previewing
                ? tokens.primary.withValues(
                    alpha: tokens.primary.a * (dark ? 0.2 : 0.3),
                  )
                : tokens.border,
          ),
          color: checked || previewing
              ? tokens.primary.withValues(
                  alpha:
                      tokens.primary.a *
                      (dark ? 0.1 : 0.05) *
                      (previewing ? 0.5 : 1),
                )
              : null,
        ),
        foregroundDecoration: focused
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.radius),
                border: Border.all(
                  color: tokens.focusRing.withValues(
                    alpha: tokens.focusRing.a * 0.5,
                  ),
                  width: 3,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              )
            : null,
        child: content,
      );
    }
    final Widget radio = MergeSemantics(
      child: Semantics(
        container: true,
        label: widget.semanticLabel,
        hint: scope?.errorText,
        validationResult: invalid
            ? SemanticsValidationResult.invalid
            : SemanticsValidationResult.none,
        readOnly: readOnly,
        isRequired: null,
        // Base UI activates a radio with Space only and prevents Enter's
        // default, so Enter must not reach the toggleable's ActivateIntent.
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): DoNothingIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): DoNothingIntent(),
          },
          child: RawRadio<T>(
            value: widget.value,
            enabled: enabled,
            groupRegistry: registry,
            mouseCursor: WidgetStatePropertyAll(
              enabled ? SystemMouseCursors.basic : SystemMouseCursors.forbidden,
            ),
            toggleable: widget.toggleable,
            focusNode: _focus,
            autofocus: false,
            builder: (context, state) => Opacity(
              opacity: enabled ? 1 : 0.5,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                // A choice card fills the height it is given, so cards side by
                // side in a row share the tallest one's height, as grid items
                // stretch on the web.
                child: widget.card
                    ? ColoredBox(color: Colors.transparent, child: content)
                    : Align(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: 1,
                        heightFactor: 1,
                        child: ColoredBox(
                          color: Colors.transparent,
                          child: content,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    // Only the choice card has a hover treatment; plain items must not rebuild
    // on every pointer crossing.
    if (!widget.card) return radio;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: radio,
    );
  }
}
