import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_input_group.dart';
import 'd_popover.dart';

bool _isComboboxTouchPlatform(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS ||
    Theme.of(context).platform == TargetPlatform.android;

enum DComboboxChangeReason {
  input,
  itemPress,
  clear,
  chipRemove,
  keyboard,
  triggerPress,
  outsidePress,
  escape,
  lifecycle,
  imperative,
  formReset,
  pointer,
}

typedef DComboboxFilter<T> = bool Function(T value, String query, String label);
typedef DComboboxValueChanged<T> =
    void Function(T? value, DComboboxChangeReason reason);
typedef DComboboxValuesChanged<T> =
    void Function(List<T> values, DComboboxChangeReason reason);
typedef DComboboxQueryChanged =
    void Function(String query, DComboboxChangeReason reason);
typedef DComboboxOpenChanged =
    void Function(bool open, DComboboxChangeReason reason);
typedef DComboboxHighlightChanged<T> =
    void Function(T? value, DComboboxChangeReason reason);
typedef DComboboxItemBuilder<T> =
    Widget Function(BuildContext context, DComboboxOption<T> option);
typedef DComboboxChipBuilder<T> =
    Widget Function(BuildContext context, T value);

@immutable
class DComboboxOption<T> {
  const DComboboxOption({
    required this.value,
    required this.label,
    this.enabled = true,
    this.searchText,
    this.itemKey,
  });

  final T value;
  final String label;
  final bool enabled;
  final String? searchText;
  final Key? itemKey;
}

@immutable
class DComboboxOptionGroup<T> {
  const DComboboxOptionGroup({required this.label, required this.options});

  final String label;
  final List<DComboboxOption<T>> options;
}

/// Imperative access to a mounted [DCombobox].
///
/// The caller owns and disposes a borrowed controller. Calls while detached are
/// intentionally ignored.
class DComboboxController<T> extends ChangeNotifier {
  _DComboboxState<T>? _owner;
  bool _disposed = false;

  List<T> get values => _owner?.selectedValues ?? const [];
  T? get value => values.firstOrNull;
  String get query => _owner?.query ?? '';
  bool get isOpen => _owner?.isOpen ?? false;
  T? get highlightedValue => _owner?.highlightedValue;

  void open() => _owner?._requestOpen(
    true,
    DComboboxChangeReason.imperative,
    focusInput: true,
  );

  void close() => _owner?._requestOpen(false, DComboboxChangeReason.imperative);

  void clear() => _owner?._clear(DComboboxChangeReason.imperative);

  void setQuery(String query) =>
      _owner?._requestQuery(query, DComboboxChangeReason.imperative);

  void highlight(T? value) =>
      _owner?._requestHighlight(value, DComboboxChangeReason.imperative);

  void _attach(_DComboboxState<T> owner) {
    if (_disposed) return;
    _owner = owner;
  }

  void _detach(_DComboboxState<T> owner) {
    if (identical(_owner, owner)) _owner = null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _owner = null;
    super.dispose();
  }
}

/// A filterable, shadcn/Base UI-style single or multiple selection field.
///
/// The ordinary constructor owns a single value. [DCombobox.controlled] gives
/// ownership to the parent, including a controlled null value. The equivalent
/// multiple-selection constructors are [DCombobox.multiple] and
/// [DCombobox.multipleControlled]. Query and popup state can independently be
/// controlled with [query]/[open]. Items may be replaced while an asynchronous
/// adapter is loading; selection is retained and stale highlights are removed.
/// Networking, debouncing and result authority remain outside this widget.
class DCombobox<T> extends FormField<List<T>> {
  // ignore: use_super_parameters, validator is adapted from T? to List<T>.
  DCombobox({
    super.key,
    required this.options,
    required this.anchor,
    required this.content,
    T? initialValue,
    this.groups = const [],
    this.onChanged,
    this.controller,
    this.textController,
    this.focusNode,
    this.query,
    this.initialQuery = '',
    this.onQueryChanged,
    this.open,
    this.defaultOpen = false,
    this.onOpenChanged,
    this.highlightedValue,
    this.highlightControlled = false,
    this.onHighlightChanged,
    this.autoHighlight = false,
    this.loopFocus = true,
    this.highlightItemOnHover = true,
    this.filterLocally = true,
    this.filter,
    this.equals,
    this.itemToStringLabel,
    this.limit,
    this.closeOnSelect = true,
    this.readOnly = false,
    super.enabled = true,
    FormFieldSetter<T?>? onSaved,
    super.onReset,
    FormFieldValidator<T?>? validator,
    super.autovalidateMode,
  }) : multiple = false,
       controlled = false,
       controlledValues = const [],
       initialValues = List<T>.unmodifiable([?initialValue]),
       onValuesChanged = null,
       singleValidator = validator,
       assert(options.isEmpty || groups.isEmpty),
       assert(textController == null || query == null),
       super(
         initialValue: List<T>.unmodifiable([?initialValue]),
         validator: validator == null
             ? null
             : (values) => validator(values?.firstOrNull),
         onSaved: onSaved == null
             ? null
             : (values) => onSaved(values?.firstOrNull),
         builder: (state) => (state as _DComboboxState<T>)._build(),
       );

  // ignore: use_super_parameters, validator is adapted from T? to List<T>.
  DCombobox.controlled({
    super.key,
    required T? value,
    required this.options,
    required this.anchor,
    required this.content,
    required this.onChanged,
    this.groups = const [],
    this.controller,
    this.textController,
    this.focusNode,
    this.query,
    this.initialQuery = '',
    this.onQueryChanged,
    this.open,
    this.defaultOpen = false,
    this.onOpenChanged,
    this.highlightedValue,
    this.highlightControlled = false,
    this.onHighlightChanged,
    this.autoHighlight = false,
    this.loopFocus = true,
    this.highlightItemOnHover = true,
    this.filterLocally = true,
    this.filter,
    this.equals,
    this.itemToStringLabel,
    this.limit,
    this.closeOnSelect = true,
    this.readOnly = false,
    super.enabled = true,
    FormFieldSetter<T?>? onSaved,
    super.onReset,
    FormFieldValidator<T?>? validator,
    super.autovalidateMode,
  }) : multiple = false,
       controlled = true,
       controlledValues = List<T>.unmodifiable([?value]),
       initialValues = List<T>.unmodifiable([?value]),
       onValuesChanged = null,
       singleValidator = validator,
       assert(options.isEmpty || groups.isEmpty),
       assert(textController == null || query == null),
       super(
         initialValue: List<T>.unmodifiable([?value]),
         validator: validator == null
             ? null
             : (values) => validator(values?.firstOrNull),
         onSaved: onSaved == null
             ? null
             : (values) => onSaved(values?.firstOrNull),
         builder: (state) => (state as _DComboboxState<T>)._build(),
       );

  // ignore: use_super_parameters, named constructor keeps the public API symmetric.
  DCombobox.multiple({
    super.key,
    required this.options,
    required this.anchor,
    required this.content,
    List<T> initialValue = const [],
    this.groups = const [],
    this.onValuesChanged,
    this.controller,
    this.textController,
    this.focusNode,
    this.query,
    this.initialQuery = '',
    this.onQueryChanged,
    this.open,
    this.defaultOpen = false,
    this.onOpenChanged,
    this.highlightedValue,
    this.highlightControlled = false,
    this.onHighlightChanged,
    this.autoHighlight = false,
    this.loopFocus = true,
    this.highlightItemOnHover = true,
    this.filterLocally = true,
    this.filter,
    this.equals,
    this.itemToStringLabel,
    this.limit,
    this.closeOnSelect = true,
    this.readOnly = false,
    super.enabled = true,
    super.onSaved,
    super.onReset,
    FormFieldValidator<List<T>>? validator,
    super.autovalidateMode,
  }) : multiple = true,
       controlled = false,
       controlledValues = const [],
       initialValues = List<T>.unmodifiable(initialValue),
       onChanged = null,
       singleValidator = null,
       assert(options.isEmpty || groups.isEmpty),
       assert(textController == null || query == null),
       super(
         initialValue: List<T>.unmodifiable(initialValue),
         validator: validator,
         builder: (state) => (state as _DComboboxState<T>)._build(),
       );

  // ignore: use_super_parameters, named constructor keeps the public API symmetric.
  DCombobox.multipleControlled({
    super.key,
    required List<T> value,
    required this.options,
    required this.anchor,
    required this.content,
    required this.onValuesChanged,
    this.groups = const [],
    this.controller,
    this.textController,
    this.focusNode,
    this.query,
    this.initialQuery = '',
    this.onQueryChanged,
    this.open,
    this.defaultOpen = false,
    this.onOpenChanged,
    this.highlightedValue,
    this.highlightControlled = false,
    this.onHighlightChanged,
    this.autoHighlight = false,
    this.loopFocus = true,
    this.highlightItemOnHover = true,
    this.filterLocally = true,
    this.filter,
    this.equals,
    this.itemToStringLabel,
    this.limit,
    this.closeOnSelect = true,
    this.readOnly = false,
    super.enabled = true,
    super.onSaved,
    super.onReset,
    FormFieldValidator<List<T>>? validator,
    super.autovalidateMode,
  }) : multiple = true,
       controlled = true,
       controlledValues = List<T>.unmodifiable(value),
       initialValues = List<T>.unmodifiable(value),
       onChanged = null,
       singleValidator = null,
       assert(options.isEmpty || groups.isEmpty),
       assert(textController == null || query == null),
       super(
         initialValue: List<T>.unmodifiable(value),
         validator: validator,
         builder: (state) => (state as _DComboboxState<T>)._build(),
       );

  final List<DComboboxOption<T>> options;
  final List<DComboboxOptionGroup<T>> groups;
  final Widget anchor;
  final DComboboxContent content;
  final bool multiple;
  final bool controlled;
  final List<T> controlledValues;
  final List<T> initialValues;
  final DComboboxValueChanged<T>? onChanged;
  final DComboboxValuesChanged<T>? onValuesChanged;
  final DComboboxController<T>? controller;
  final TextEditingController? textController;
  final FocusNode? focusNode;
  final String? query;
  final String initialQuery;
  final DComboboxQueryChanged? onQueryChanged;
  final bool? open;
  final bool defaultOpen;
  final DComboboxOpenChanged? onOpenChanged;
  final T? highlightedValue;
  final bool highlightControlled;
  final DComboboxHighlightChanged<T>? onHighlightChanged;
  final bool autoHighlight;
  final bool loopFocus;
  final bool highlightItemOnHover;
  final bool filterLocally;
  final DComboboxFilter<T>? filter;
  final bool Function(T left, T right)? equals;
  final String Function(T value)? itemToStringLabel;
  final int? limit;
  final bool closeOnSelect;
  final bool readOnly;
  final FormFieldValidator<T?>? singleValidator;

  @override
  FormFieldState<List<T>> createState() => _DComboboxState<T>();
}

class _DComboboxState<T> extends FormFieldState<List<T>> {
  late final DComboboxController<T> _ownedController;
  late final TextEditingController _ownedTextController;
  late final FocusNode _ownedFocusNode;
  late final DPopoverController _popoverController;
  final GlobalKey _anchorKey = GlobalKey();
  final Map<T, GlobalKey> _itemKeys = {};
  final Map<T, FocusNode> _chipFocusNodes = {};
  late final List<T> _resetValues;
  late final String _resetQuery;
  bool _open = false;
  T? _highlighted;
  bool _syncingText = false;
  double? _anchorWidth;

  DCombobox<T> get combobox => widget as DCombobox<T>;
  DComboboxController<T> get _controller =>
      combobox.controller ?? _ownedController;
  TextEditingController get textController =>
      combobox.textController ?? _ownedTextController;
  FocusNode get focusNode => combobox.focusNode ?? _ownedFocusNode;
  List<T> get selectedValues => List<T>.unmodifiable(
    combobox.controlled ? combobox.controlledValues : value ?? const [],
  );
  T? get highlightedValue =>
      combobox.highlightControlled ? combobox.highlightedValue : _highlighted;
  String get query => combobox.query ?? textController.text;
  bool get isOpen => combobox.open ?? _open;
  bool get enabled => combobox.enabled;
  bool get mutable => enabled && !combobox.readOnly;

  List<DComboboxOption<T>> get _allOptions => combobox.groups.isEmpty
      ? combobox.options
      : [for (final group in combobox.groups) ...group.options];

  bool _equal(T left, T right) =>
      combobox.equals?.call(left, right) ?? left == right;

  bool _contains(Iterable<T> values, T value) =>
      values.any((candidate) => _equal(candidate, value));

  DComboboxOption<T>? optionFor(T value) =>
      _allOptions.where((option) => _equal(option.value, value)).firstOrNull;

  String labelFor(T value) =>
      combobox.itemToStringLabel?.call(value) ??
      optionFor(value)?.label ??
      '$value';

  List<DComboboxOption<T>> get filteredOptions {
    final normalized = query.trim();
    var result = _allOptions
        .where((option) {
          if (!combobox.filterLocally || normalized.isEmpty) return true;
          final label = option.searchText ?? option.label;
          return combobox.filter?.call(option.value, normalized, label) ??
              label.toLowerCase().contains(normalized.toLowerCase());
        })
        .toList(growable: false);
    if (combobox.limit case final limit?
        when limit >= 0 && result.length > limit) {
      result = result.take(limit).toList(growable: false);
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _ownedController = DComboboxController<T>();
    _ownedTextController = TextEditingController(text: combobox.initialQuery);
    _ownedFocusNode = FocusNode(debugLabel: 'DCombobox input');
    _popoverController = DPopoverController();
    _open = combobox.defaultOpen;
    _highlighted = combobox.highlightedValue;
    _controller._attach(this);
    focusNode.addListener(_focusChanged);
    textController.addListener(_textChanged);
    final selected = selectedValues.firstOrNull;
    if (!combobox.multiple && textController.text.isEmpty && selected != null) {
      _replaceText(labelFor(selected));
    }
    _resetValues = List<T>.unmodifiable(selectedValues);
    _resetQuery = textController.text;
  }

  @override
  void didUpdateWidget(covariant DCombobox<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != combobox.controller) {
      (oldWidget.controller ?? _ownedController)._detach(this);
      _controller._attach(this);
    }
    if (oldWidget.focusNode != combobox.focusNode) {
      (oldWidget.focusNode ?? _ownedFocusNode).removeListener(_focusChanged);
      focusNode.addListener(_focusChanged);
    }
    if (oldWidget.textController != combobox.textController) {
      (oldWidget.textController ?? _ownedTextController).removeListener(
        _textChanged,
      );
      textController.addListener(_textChanged);
    }
    if (combobox.controlled &&
        !_sameValues(oldWidget.controlledValues, combobox.controlledValues)) {
      setValue(List<T>.unmodifiable(combobox.controlledValues));
      if (!combobox.multiple && combobox.query == null) {
        final selected = combobox.controlledValues.firstOrNull;
        _replaceText(selected == null ? '' : labelFor(selected));
      }
    }
    if (combobox.query case final controlledQuery?
        when controlledQuery != textController.text) {
      _replaceText(controlledQuery);
    }
    if (!combobox.enabled && oldWidget.enabled) {
      _requestOpen(false, DComboboxChangeReason.lifecycle);
      focusNode.unfocus();
    }
    final highlighted = highlightedValue;
    if (highlighted != null &&
        !filteredOptions.any(
          (o) => o.enabled && _equal(o.value, highlighted),
        )) {
      _requestHighlight(null, DComboboxChangeReason.input);
    }
    _itemKeys.removeWhere(
      (value, _) => !_allOptions.any((option) => _equal(option.value, value)),
    );
    _controller._changed();
  }

  bool _sameValues(List<T> left, List<T> right) =>
      left.length == right.length &&
      left.indexed.every((entry) => _equal(entry.$2, right[entry.$1]));

  void _replaceText(String text) {
    _syncingText = true;
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncingText = false;
  }

  void _textChanged() {
    if (!_syncingText && combobox.query == null) setState(() {});
  }

  void _focusChanged() {
    if (!mounted) return;
    setState(() {});
    if (focusNode.hasFocus && enabled) {
      _requestOpen(true, DComboboxChangeReason.input);
    }
  }

  void _measureAnchor() {
    final box = _anchorKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) _anchorWidth = box.size.width;
  }

  void _requestOpen(
    bool open,
    DComboboxChangeReason reason, {
    bool focusInput = false,
  }) {
    if (!mounted || (open && !enabled)) return;
    if (open == isOpen) {
      if (open && focusInput) _focusInputAfterBuild();
      return;
    }
    _measureAnchor();
    if (combobox.open == null) _open = open;
    combobox.onOpenChanged?.call(open, reason);
    if (open && combobox.autoHighlight && highlightedValue == null) {
      _highlightFirst(reason);
    }
    if (!open && reason == DComboboxChangeReason.escape && !combobox.multiple) {
      final selected = selectedValues.firstOrNull;
      _replaceText(selected == null ? '' : labelFor(selected));
    }
    setState(() {});
    _controller._changed();
    if (open && focusInput) _focusInputAfterBuild();
  }

  void _focusInputAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && isOpen && focusNode.canRequestFocus) {
        focusNode.requestFocus();
      }
    });
  }

  void _requestQuery(
    String next,
    DComboboxChangeReason reason, {
    bool openPopup = true,
  }) {
    if (!mutable) return;
    if (combobox.query == null && textController.text != next) {
      _replaceText(next);
    }
    combobox.onQueryChanged?.call(next, reason);
    if (openPopup) _requestOpen(true, reason);
    if (openPopup && combobox.autoHighlight) {
      _highlightFirst(reason);
    } else {
      _requestHighlight(null, reason);
    }
    setState(() {});
  }

  void _highlightFirst(DComboboxChangeReason reason) {
    final first = filteredOptions.where((option) => option.enabled).firstOrNull;
    _requestHighlight(first?.value, reason);
  }

  void _requestHighlight(T? value, DComboboxChangeReason reason) {
    if (value != null && !(optionFor(value)?.enabled ?? false)) return;
    if (!combobox.highlightControlled) _highlighted = value;
    combobox.onHighlightChanged?.call(value, reason);
    if (mounted) setState(() {});
    _controller._changed();
    if (value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final itemContext = _entryFor(_itemKeys, value)?.value.currentContext;
        if (mounted && isOpen && itemContext != null) {
          Scrollable.ensureVisible(
            itemContext,
            alignment: .5,
            duration: DMotion.duration(
              context,
              const Duration(milliseconds: 100),
            ),
          );
        }
      });
    }
  }

  void _moveHighlight(int delta) {
    final candidates = filteredOptions
        .where((option) => option.enabled)
        .toList();
    if (candidates.isEmpty) return;
    if (!isOpen) _requestOpen(true, DComboboxChangeReason.keyboard);
    final current = highlightedValue;
    var index = current == null
        ? (delta > 0 ? -1 : candidates.length)
        : candidates.indexWhere((option) => _equal(option.value, current));
    if (current != null &&
        ((delta > 0 && index == candidates.length - 1) ||
            (delta < 0 && index == 0))) {
      if (combobox.loopFocus) {
        _requestHighlight(null, DComboboxChangeReason.keyboard);
      }
      return;
    }
    final next = (index + delta).clamp(0, candidates.length - 1);
    _requestHighlight(candidates[next].value, DComboboxChangeReason.keyboard);
  }

  void _select(DComboboxOption<T> option, DComboboxChangeReason reason) {
    if (!mutable || !option.enabled) return;
    if (combobox.multiple) {
      final next = [...selectedValues];
      final index = next.indexWhere((value) => _equal(value, option.value));
      if (index < 0) {
        next.add(option.value);
      } else {
        next.removeAt(index);
      }
      _emitValues(next, reason);
      _requestQuery('', reason, openPopup: !combobox.closeOnSelect);
      if (combobox.closeOnSelect) _requestOpen(false, reason);
    } else {
      _emitValues([option.value], reason);
      if (!combobox.controlled) {
        _replaceText(option.label);
        combobox.onQueryChanged?.call(option.label, reason);
      }
      _requestOpen(!combobox.closeOnSelect, reason);
    }
    if (focusNode.canRequestFocus) focusNode.requestFocus();
  }

  void _emitValues(List<T> values, DComboboxChangeReason reason) {
    final frozen = List<T>.unmodifiable(values);
    if (!combobox.controlled) didChange(frozen);
    if (combobox.multiple) {
      combobox.onValuesChanged?.call(frozen, reason);
    } else {
      combobox.onChanged?.call(frozen.firstOrNull, reason);
    }
    _controller._changed();
    setState(() {});
  }

  void _remove(T value, DComboboxChangeReason reason) {
    if (!mutable) return;
    _emitValues(
      selectedValues.where((candidate) => !_equal(candidate, value)).toList(),
      reason,
    );
    focusNode.requestFocus();
  }

  void _clear(DComboboxChangeReason reason) {
    if (!mutable) return;
    _emitValues(const [], reason);
    _requestQuery('', reason);
    focusNode.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!enabled) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _moveHighlight(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveHighlight(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        final highlighted = highlightedValue;
        final option = highlighted == null ? null : optionFor(highlighted);
        if (isOpen && option != null) {
          _select(option, DComboboxChangeReason.keyboard);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.escape when isOpen:
        _requestOpen(false, DComboboxChangeReason.escape);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace
          when combobox.multiple && query.isEmpty && selectedValues.isNotEmpty:
        _remove(selectedValues.last, DComboboxChangeReason.keyboard);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  MapEntry<T, V>? _entryFor<V>(Map<T, V> entries, T value) =>
      entries.entries.where((entry) => _equal(entry.key, value)).firstOrNull;

  GlobalKey keyFor(T value) =>
      _entryFor(_itemKeys, value)?.value ?? (_itemKeys[value] = GlobalKey());

  void registerChip(T value, FocusNode focusNode) {
    final existing = _entryFor(_chipFocusNodes, value);
    if (existing != null && !identical(existing.key, value)) {
      _chipFocusNodes.remove(existing.key);
    }
    _chipFocusNodes[value] = focusNode;
  }

  void unregisterChip(T value, FocusNode focusNode) {
    final existing = _entryFor(_chipFocusNodes, value);
    if (existing != null && identical(existing.value, focusNode)) {
      _chipFocusNodes.remove(existing.key);
    }
  }

  FocusNode? chipFocusFor(T value) => _entryFor(_chipFocusNodes, value)?.value;

  @override
  void reset() {
    super.reset();
    if (!combobox.controlled) setValue(_resetValues);
    _replaceText(_resetQuery);
    combobox.onQueryChanged?.call(_resetQuery, DComboboxChangeReason.formReset);
    if (combobox.multiple) {
      combobox.onValuesChanged?.call(
        _resetValues,
        DComboboxChangeReason.formReset,
      );
    } else {
      combobox.onChanged?.call(
        _resetValues.firstOrNull,
        DComboboxChangeReason.formReset,
      );
    }
    _requestOpen(false, DComboboxChangeReason.formReset);
  }

  Widget _build() {
    final popupWidth = combobox.content.width ?? _anchorWidth ?? 320;
    return _DComboboxScope<T>(
      state: this,
      child: DPopover(
        controller: _popoverController,
        open: isOpen,
        focusContentOnOpen: false,
        onOpenChange: (open, reason) =>
            _requestOpen(open, _popoverReason(reason)),
        content: DPopoverContent(
          semanticLabel: combobox.content.semanticLabel ?? 'Suggestions',
          side: combobox.content.side,
          align: combobox.content.align,
          sideOffset: combobox.content.sideOffset,
          alignOffset: combobox.content.alignOffset,
          sideCollision: combobox.content.sideCollision,
          alignCollision: combobox.content.alignCollision,
          collisionPadding: combobox.content.collisionPadding,
          collisionBoundary: combobox.content.collisionBoundary,
          width: popupWidth,
          constraints: BoxConstraints(maxHeight: combobox.content.maxHeight),
          padding: EdgeInsets.zero,
          child: combobox.content,
        ),
        child: KeyedSubtree(key: _anchorKey, child: combobox.anchor),
      ),
    );
  }

  DComboboxChangeReason _popoverReason(DPopoverChangeReason reason) =>
      switch (reason) {
        DPopoverChangeReason.triggerPress => DComboboxChangeReason.triggerPress,
        DPopoverChangeReason.outsidePress => DComboboxChangeReason.outsidePress,
        DPopoverChangeReason.escape => DComboboxChangeReason.escape,
        DPopoverChangeReason.lifecycle => DComboboxChangeReason.lifecycle,
        DPopoverChangeReason.imperative => DComboboxChangeReason.imperative,
        DPopoverChangeReason.closePress => DComboboxChangeReason.triggerPress,
      };

  @override
  void dispose() {
    _controller._detach(this);
    focusNode.removeListener(_focusChanged);
    textController.removeListener(_textChanged);
    _ownedController.dispose();
    _ownedTextController.dispose();
    _ownedFocusNode.dispose();
    _popoverController.dispose();
    super.dispose();
  }
}

class _DComboboxScope<T> extends InheritedWidget {
  const _DComboboxScope({required this.state, required super.child});

  final _DComboboxState<T> state;

  static _DComboboxState<T> of<T>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DComboboxScope<T>>();
    assert(scope != null, 'Combobox parts require a matching DCombobox<$T>.');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(_DComboboxScope<T> oldWidget) => true;
}

class DComboboxInput<T> extends StatelessWidget {
  const DComboboxInput({
    super.key,
    this.placeholder,
    this.showTrigger = true,
    this.showClear = false,
    this.invalid = false,
    this.addons = const [],
    this.autofocus = false,
    this.registerAsAnchor = true,
    this.semanticLabel,
  });

  final String? placeholder;
  final bool showTrigger;
  final bool showClear;
  final bool invalid;
  final List<DInputGroupAddon> addons;
  final bool autofocus;
  final bool registerAsAnchor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final root = _DComboboxScope.of<T>(context);
    final isInvalid = invalid || root.hasError;
    final hasValue = root.selectedValues.isNotEmpty || root.query.isNotEmpty;
    final action = showClear && hasValue
        ? DInputGroupButton.icon(
            tooltip: 'Clear selection',
            icon: const DIcon(DIcons.xmark, size: 16),
            onPressed: root.mutable
                ? () => root._clear(DComboboxChangeReason.clear)
                : null,
          )
        : showTrigger
        ? Semantics(
            expanded: root.isOpen,
            child: DInputGroupButton.icon(
              tooltip: root.isOpen ? 'Close suggestions' : 'Open suggestions',
              icon: const DIcon(DIcons.chevronDown, size: 16),
              hasPopup: true,
              onPressed: () => root._requestOpen(
                !root.isOpen,
                DComboboxChangeReason.triggerPress,
                focusInput: true,
              ),
            ),
          )
        : null;
    final input = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: root._handleKey,
      child: DInputGroup(
        enabled: root.enabled,
        invalid: isInvalid,
        children: [
          DInputGroupControl(
            focusNode: root.focusNode,
            enabled: root.enabled,
            invalid: isInvalid,
            builder: (context, focusNode) => _ComboboxTextEditor<T>(
              focusNode: focusNode,
              placeholder: placeholder,
              autofocus: autofocus,
              semanticLabel: semanticLabel,
              invalid: isInvalid,
            ),
          ),
          ...addons,
          if (action != null)
            DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineEnd,
              child: action,
            ),
        ],
      ),
    );
    if (!registerAsAnchor) return input;
    return DPopoverTrigger(
      focusNode: root.focusNode,
      builder: (context, state) => input,
    );
  }
}

class _ComboboxTextEditor<T> extends StatelessWidget {
  const _ComboboxTextEditor({
    required this.focusNode,
    this.placeholder,
    required this.autofocus,
    this.semanticLabel,
    required this.invalid,
  });

  final FocusNode focusNode;
  final String? placeholder;
  final bool autofocus;
  final String? semanticLabel;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final root = _DComboboxScope.of<T>(context);
    final tokens = DTokens.of(context);
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: tokens.foreground,
      fontSize: DiscourseTypography.sm,
      height: 20 / DiscourseTypography.sm,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      expanded: root.isOpen,
      validationResult: invalid
          ? SemanticsValidationResult.invalid
          : SemanticsValidationResult.none,
      child: TextField(
        controller: root.textController,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: root.enabled,
        readOnly: root.combobox.readOnly,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        style: style,
        cursorColor: tokens.foreground,
        decoration: InputDecoration.collapsed(
          hintText: placeholder,
          hintStyle: style.copyWith(color: tokens.mutedForeground),
        ),
        onChanged: (value) =>
            root._requestQuery(value, DComboboxChangeReason.input),
        onTap: () => root._requestOpen(true, DComboboxChangeReason.input),
      ),
    );
  }
}

class _ComboboxIconAction extends StatelessWidget {
  const _ComboboxIconAction({
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
  });

  final String semanticLabel;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final touch = _isComboboxTouchPlatform(context);
    final dimension = touch ? DSpacing.touchTarget : 24.0;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: IconButton(
        tooltip: '',
        visualDensity: touch ? VisualDensity.standard : VisualDensity.compact,
        constraints: BoxConstraints.tightFor(
          width: dimension,
          height: dimension,
        ),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: icon,
      ),
    );
  }
}

class DComboboxContent extends StatelessWidget {
  const DComboboxContent({
    super.key,
    required this.children,
    this.semanticLabel,
    this.side = DPopoverSide.bottom,
    this.align = DPopoverAlign.start,
    this.sideOffset = 6,
    this.alignOffset = 0,
    this.sideCollision = DPopoverCollision.flip,
    this.alignCollision = DPopoverCollision.shift,
    this.collisionPadding = 5,
    this.collisionBoundary,
    this.width,
    this.maxHeight = 288,
  });

  final List<Widget> children;
  final String? semanticLabel;
  final DPopoverSide side;
  final DPopoverAlign align;
  final double sideOffset;
  final double alignOffset;
  final DPopoverCollision sideCollision;
  final DPopoverCollision alignCollision;
  final double collisionPadding;
  final Rect? collisionBoundary;
  final double? width;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(DTokens.of(context).radius),
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}

class DComboboxList<T> extends StatelessWidget {
  const DComboboxList({super.key, this.itemBuilder, this.groupLabelBuilder});

  final DComboboxItemBuilder<T>? itemBuilder;
  final Widget Function(BuildContext context, String label)? groupLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final root = _DComboboxScope.of<T>(context);
    final filtered = root.filteredOptions;
    if (filtered.isEmpty) return const SizedBox.shrink();
    final allowed = filtered.map((option) => option.value).toList();
    final children = <Widget>[];
    if (root.combobox.groups.isEmpty) {
      children.addAll(filtered.map((option) => _item(context, root, option)));
    } else {
      for (final group in root.combobox.groups) {
        final options = group.options
            .where((option) => root._contains(allowed, option.value))
            .toList();
        if (options.isEmpty) continue;
        if (children.isNotEmpty) children.add(const DComboboxSeparator());
        children.add(
          DComboboxGroup(
            label: group.label,
            labelWidget: groupLabelBuilder?.call(context, group.label),
            children: options
                .map((option) => _item(context, root, option))
                .toList(),
          ),
        );
      }
    }
    return Flexible(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(4),
        child: DComboboxCollection(children: children),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    _DComboboxState<T> root,
    DComboboxOption<T> option,
  ) => KeyedSubtree(
    key: root.keyFor(option.value),
    child: DComboboxItem<T>(
      key: option.itemKey,
      option: option,
      child: itemBuilder?.call(context, option) ?? Text(option.label),
    ),
  );
}

class DComboboxItem<T> extends StatefulWidget {
  const DComboboxItem({super.key, required this.option, required this.child});

  final DComboboxOption<T> option;
  final Widget child;

  @override
  State<DComboboxItem<T>> createState() => _DComboboxItemState<T>();
}

class _DComboboxItemState<T> extends State<DComboboxItem<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final root = _DComboboxScope.of<T>(context);
    final tokens = DTokens.of(context);
    final itemEnabled = root.mutable && widget.option.enabled;
    final selected = root._contains(root.selectedValues, widget.option.value);
    final highlightedValue = root.highlightedValue;
    final highlighted =
        highlightedValue != null &&
        root._equal(highlightedValue, widget.option.value);
    final active =
        highlighted || (_hovered && root.combobox.highlightItemOnHover);
    Widget item = MouseRegion(
      cursor: itemEnabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        setState(() => _hovered = true);
        if (root.combobox.highlightItemOnHover && itemEnabled) {
          root._requestHighlight(
            widget.option.value,
            DComboboxChangeReason.pointer,
          );
        }
      },
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        selected: selected,
        enabled: itemEnabled,
        label: widget.option.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: itemEnabled
              ? () =>
                    root._select(widget.option, DComboboxChangeReason.itemPress)
              : null,
          child: AnimatedContainer(
            duration: DMotion.duration(
              context,
              const Duration(milliseconds: 100),
            ),
            constraints: const BoxConstraints(minHeight: 28),
            padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 8, 4),
            decoration: BoxDecoration(
              color: active ? tokens.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(tokens.radius * .8),
            ),
            foregroundDecoration: itemEnabled
                ? null
                : BoxDecoration(
                    color: tokens.surface.withValues(
                      alpha: tokens.surface.a * .5,
                    ),
                  ),
            child: Row(
              children: [
                Expanded(child: widget.child),
                const SizedBox(width: 8),
                SizedBox(
                  width: 16,
                  child: selected
                      ? DIcon(DIcons.check, size: 16, color: tokens.foreground)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (_isComboboxTouchPlatform(context)) {
      item = SizedBox(
        height: DSpacing.touchTarget,
        child: Center(child: item),
      );
    }
    return item;
  }
}

class DComboboxGroup extends StatelessWidget {
  const DComboboxGroup({
    super.key,
    required this.label,
    required this.children,
    this.labelWidget,
  });

  final String label;
  final Widget? labelWidget;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    explicitChildNodes: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [labelWidget ?? DComboboxLabel(label), ...children],
    ),
  );
}

class DComboboxLabel extends StatelessWidget {
  const DComboboxLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontSize: DiscourseTypography.xs,
        height: 16 / DiscourseTypography.xs,
        color: DTokens.of(context).mutedForeground,
      ),
    ),
  );
}

class DComboboxCollection extends StatelessWidget {
  const DComboboxCollection({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}

class DComboboxEmpty<T> extends StatelessWidget {
  const DComboboxEmpty({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final empty = _DComboboxScope.of<T>(context).filteredOptions.isEmpty;
    return Semantics(
      liveRegion: true,
      child: empty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Center(
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: DTokens.of(context).mutedForeground),
                  child: child,
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class DComboboxStatus extends StatelessWidget {
  const DComboboxStatus({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(liveRegion: true, container: true, child: child);
}

class DComboboxSeparator extends StatelessWidget {
  const DComboboxSeparator({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: -4, vertical: 4),
    color: DTokens.of(context).border,
  );
}

class DComboboxChips<T> extends StatelessWidget {
  const DComboboxChips({
    super.key,
    required this.input,
    this.chipBuilder,
    this.invalid = false,
  });

  final DComboboxChipsInput<T> input;
  final DComboboxChipBuilder<T>? chipBuilder;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final root = _DComboboxScope.of<T>(context);
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final focused = root.focusNode.hasFocus;
    final isInvalid = invalid || root.hasError;
    final border = isInvalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .5 : 1),
          )
        : focused
        ? tokens.focusRing
        : tokens.colors.outlineVariant;
    final ring = isInvalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .4 : .2),
          )
        : tokens.focusRing.withValues(alpha: tokens.focusRing.a * .5);
    final surface = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: root._handleKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: root.enabled
            ? () {
                root.focusNode.requestFocus();
                root._requestOpen(true, DComboboxChangeReason.input);
              }
            : null,
        child: AnimatedContainer(
          duration: DMotion.duration(
            context,
            const Duration(milliseconds: 150),
          ),
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          decoration: BoxDecoration(
            color: dark
                ? tokens.colors.outlineVariant.withValues(
                    alpha: tokens.colors.outlineVariant.a * .3,
                  )
                : Colors.transparent,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(tokens.radius),
          ),
          foregroundDecoration: _ComboboxRingDecoration(
            color: isInvalid || focused ? ring : Colors.transparent,
            radius: tokens.radius,
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final value in root.selectedValues)
                chipBuilder?.call(context, value) ??
                    DComboboxChip<T>(
                      value: value,
                      child: Text(root.labelFor(value)),
                    ),
              input,
            ],
          ),
        ),
      ),
    );
    return Opacity(
      opacity: root.enabled ? 1 : .5,
      child: DPopoverTrigger(
        focusNode: root.focusNode,
        builder: (_, _) => surface,
      ),
    );
  }
}

class DComboboxChip<T> extends StatefulWidget {
  const DComboboxChip({
    super.key,
    required this.value,
    required this.child,
    this.showRemove = true,
  });

  final T value;
  final Widget child;
  final bool showRemove;

  @override
  State<DComboboxChip<T>> createState() => _DComboboxChipState<T>();
}

class _DComboboxChipState<T> extends State<DComboboxChip<T>> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'DCombobox chip');
  _DComboboxState<T>? _root;
  bool _focused = false;

  KeyEventResult _onKey(
    _DComboboxState<T> root,
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (!root.mutable) return KeyEventResult.ignored;
      root._remove(widget.value, DComboboxChangeReason.keyboard);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final towardEnd = event.logicalKey == LogicalKeyboardKey.arrowRight;
      final delta = towardEnd == rtl ? -1 : 1;
      final values = root.selectedValues;
      final index = values.indexWhere(
        (value) => root._equal(value, widget.value),
      );
      final next = index + delta;
      if (next < 0 || next >= values.length) {
        root.focusNode.requestFocus();
      } else {
        root.chipFocusFor(values[next])?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _root = _DComboboxScope.of<T>(context)
      ..registerChip(widget.value, _focusNode);
  }

  @override
  void didUpdateWidget(covariant DComboboxChip<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final root = _DComboboxScope.of<T>(context);
    if (!root._equal(oldWidget.value, widget.value)) {
      root.unregisterChip(oldWidget.value, _focusNode);
      root.registerChip(widget.value, _focusNode);
    } else if (!identical(oldWidget.value, widget.value)) {
      root.unregisterChip(oldWidget.value, _focusNode);
      root.registerChip(widget.value, _focusNode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final root = _DComboboxScope.of<T>(context);
    final tokens = DTokens.of(context);
    final canRemove = widget.showRemove && root.mutable;
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: root.enabled,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (node, event) => _onKey(root, node, event),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: root.enabled ? _focusNode.requestFocus : null,
        child: Semantics(
          container: true,
          button: canRemove,
          label: root.labelFor(widget.value),
          hint: canRemove ? 'Press Delete or Backspace to remove' : null,
          child: AnimatedContainer(
            duration: DMotion.duration(
              context,
              const Duration(milliseconds: 100),
            ),
            constraints: const BoxConstraints(minHeight: 21),
            padding: EdgeInsetsDirectional.only(
              start: 6,
              end: canRemove ? 1 : 6,
            ),
            decoration: BoxDecoration(
              color: tokens.muted,
              borderRadius: BorderRadius.circular(tokens.radius * .6),
              border: Border.all(
                color: _focused ? tokens.focusRing : Colors.transparent,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 184),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(
                        fontSize: DiscourseTypography.xs,
                        height: 16 / DiscourseTypography.xs,
                        fontWeight: FontWeight.w500,
                        overflow: TextOverflow.ellipsis,
                      ),
                      child: widget.child,
                    ),
                  ),
                  if (canRemove)
                    _ComboboxIconAction(
                      semanticLabel: 'Remove ${root.labelFor(widget.value)}',
                      icon: const DIcon(DIcons.xmark, size: 16),
                      onPressed: () => root._remove(
                        widget.value,
                        DComboboxChangeReason.chipRemove,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _root?.unregisterChip(widget.value, _focusNode);
    _focusNode.dispose();
    super.dispose();
  }
}

class DComboboxChipsInput<T> extends StatelessWidget {
  const DComboboxChipsInput({
    super.key,
    this.placeholder,
    this.autofocus = false,
  });
  final String? placeholder;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final root = _DComboboxScope.of<T>(context);
    final tokens = DTokens.of(context);
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / DiscourseTypography.sm,
      color: tokens.foreground,
    );
    return SizedBox(
      width: root.selectedValues.isEmpty ? 160 : 100,
      child: TextField(
        key: key,
        controller: root.textController,
        focusNode: root.focusNode,
        enabled: root.enabled,
        readOnly: root.combobox.readOnly,
        autofocus: autofocus,
        autocorrect: false,
        enableSuggestions: false,
        style: style,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: placeholder,
          hintStyle: style.copyWith(color: tokens.mutedForeground),
        ),
        onTap: () => root._requestOpen(true, DComboboxChangeReason.input),
        onChanged: (value) =>
            root._requestQuery(value, DComboboxChangeReason.input),
      ),
    );
  }
}

typedef DComboboxTriggerBuilder<T> =
    Widget Function(BuildContext context, DComboboxTriggerState<T> state);

@immutable
class DComboboxTriggerState<T> {
  const DComboboxTriggerState({
    required this.open,
    required this.value,
    required this.values,
    required this.focusNode,
    required this.toggle,
  });
  final bool open;
  final T? value;
  final List<T> values;
  final FocusNode focusNode;
  final VoidCallback toggle;
}

class DComboboxTrigger<T> extends StatelessWidget {
  const DComboboxTrigger({super.key, required this.builder});
  final DComboboxTriggerBuilder<T> builder;

  @override
  Widget build(BuildContext context) {
    final root = _DComboboxScope.of<T>(context);
    return DPopoverTrigger(
      builder: (context, popover) => builder(
        context,
        DComboboxTriggerState<T>(
          open: root.isOpen,
          value: root.selectedValues.firstOrNull,
          values: root.selectedValues,
          focusNode: popover.focusNode,
          toggle: () => root._requestOpen(
            !root.isOpen,
            DComboboxChangeReason.triggerPress,
            focusInput: true,
          ),
        ),
      ),
    );
  }
}

class DComboboxValue<T> extends StatelessWidget {
  const DComboboxValue({super.key, this.placeholder, this.builder});
  final String? placeholder;
  final Widget Function(BuildContext context, List<T> values)? builder;

  @override
  Widget build(BuildContext context) {
    final root = _DComboboxScope.of<T>(context);
    if (builder != null) return builder!(context, root.selectedValues);
    final value = root.selectedValues.firstOrNull;
    return Text(value == null ? placeholder ?? '' : root.labelFor(value));
  }
}

class _ComboboxRingDecoration extends Decoration {
  const _ComboboxRingDecoration({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _ComboboxRingPainter(this);
}

class _ComboboxRingPainter extends BoxPainter {
  _ComboboxRingPainter(this.decoration);
  final _ComboboxRingDecoration decoration;

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
