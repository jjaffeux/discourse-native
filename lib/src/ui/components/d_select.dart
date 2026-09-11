import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/control_style.dart';
import '../foundation/joined_control.dart';
import '../foundation/tokens.dart';
import 'd_popover.dart';
import 'd_scroll_area.dart';

enum DSelectSize { small, normal }

enum DSelectChangeReason { itemPress, keyboard, controller, formReset }

typedef DSelectValueChanged<T> =
    void Function(T? value, DSelectChangeReason reason);
typedef DMultiSelectValueChanged<T> =
    void Function(List<T> value, DSelectChangeReason reason);
typedef DSelectValueBuilder<T> =
    Widget Function(BuildContext context, T? value, DSelectItem<T>? item);
typedef DMultiSelectValueBuilder<T> =
    Widget Function(
      BuildContext context,
      List<T> value,
      List<DSelectItem<T>> items,
    );
typedef DSelectTriggerBuilder<T> =
    Widget Function(
      BuildContext context,
      DSelectTriggerState<T> state,
      Widget defaultTrigger,
    );

@immutable
class DSelectTriggerState<T> {
  const DSelectTriggerState({
    required this.open,
    required this.enabled,
    required this.readOnly,
    required this.invalid,
    required this.values,
    required this.focusNode,
    required this.toggle,
  });

  final bool open;
  final bool enabled;
  final bool readOnly;
  final bool invalid;
  final List<T?> values;
  final FocusNode focusNode;
  final VoidCallback toggle;
}

/// A typed entry in a rich [DSelect] popup.
sealed class DSelectEntry<T> {
  const DSelectEntry();
}

/// A selectable row. [textValue] owns typeahead and the fallback trigger text;
/// [child] may contain richer presentation. Values must be unique according to
/// the select's equality callback, including at most one null clearable value.
@immutable
class DSelectItem<T> extends DSelectEntry<T> {
  const DSelectItem({
    required this.value,
    required this.child,
    required this.textValue,
    this.enabled = true,
    this.semanticLabel,
  });

  final T? value;
  final Widget child;
  final String textValue;
  final bool enabled;
  final String? semanticLabel;
}

@immutable
class DSelectOption<T> extends DSelectItem<T> {
  const DSelectOption({
    required super.value,
    required super.child,
    required String label,
    super.enabled,
    super.semanticLabel,
  }) : super(textValue: label);
}

/// A labeled group of items. The label is associated through the group's
/// bounded semantics container; it is not an action or focus stop.
@immutable
class DSelectGroup<T> extends DSelectEntry<T> {
  const DSelectGroup({required this.children, this.label});

  final Widget? label;
  final List<DSelectItem<T>> children;
  List<DSelectItem<T>> get items => children;
}

/// A non-interactive horizontal rule between items or groups.
@immutable
class DSelectSeparator<T> extends DSelectEntry<T> {
  const DSelectSeparator();
}

List<DSelectEntry<T>> _entriesFromDropdownItems<T>(
  List<DropdownMenuItem<T>> items,
) => [
  for (final item in items)
    DSelectItem<T>(
      value: item.value,
      child: item.child,
      textValue: item.child is Text
          ? ((item.child as Text).data ?? '${item.value}')
          : '${item.value}',
      enabled: item.enabled,
    ),
];

/// A complete shadcn/Base UI-style single-value Select and Flutter FormField.
///
/// The default constructor owns its value, initialized by [initialValue]. Use
/// [DSelect.controlled] when a parent owns [value], including a controlled null
/// value. A borrowed [focusNode], [popoverController], or [scrollController] is
/// never disposed. Internally-created resources are disposed with the widget.
class DSelect<T> extends FormField<T> {
  DSelect({
    super.key,
    List<DSelectEntry<T>>? entries,
    List<DropdownMenuItem<T>>? items,
    this.value,
    super.initialValue,
    this.onChanged,
    this.onChangedWithReason,
    this.placeholder = 'Select an option',
    this.label,
    this.description,
    this.errorText,
    this.semanticLabel,
    this.valueBuilder,
    this.triggerBuilder,
    this.icon,
    this.indicator,
    this.size = DSelectSize.normal,
    this.width = 180,
    this.isExpanded = false,
    this.invalid = false,
    this.readOnly = false,
    this.required = false,
    this.highlightItemOnHover = true,
    this.loop = true,
    this.modal = true,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.onOpenChangeComplete,
    this.focusNode,
    this.popoverController,
    this.scrollController,
    this.autofocus = false,
    this.alignItemWithTrigger = true,
    this.side = DPopoverSide.bottom,
    this.align = DPopoverAlign.center,
    this.sideOffset = 4,
    this.alignOffset = 0,
    this.sideCollision = DPopoverCollision.flip,
    this.alignCollision = DPopoverCollision.shift,
    this.collisionPadding = 5,
    this.collisionBoundary,
    this.maxPopupHeight = 320,
    this.isItemEqualToValue,
    super.enabled = true,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
    super.forceErrorText,
  }) : assert(entries != null || items != null),
       assert(width > 0),
       assert(maxPopupHeight > 0),
       entries = entries ?? _entriesFromDropdownItems<T>(items!),
       _controlled = value != null,
       super(builder: (state) => (state as _DSelectFormState<T>)._build());

  DSelect.controlled({
    super.key,
    required this.entries,
    required this.value,
    required this.onChanged,
    this.onChangedWithReason,
    super.initialValue,
    this.placeholder = 'Select an option',
    this.label,
    this.description,
    this.errorText,
    this.semanticLabel,
    this.valueBuilder,
    this.triggerBuilder,
    this.icon,
    this.indicator,
    this.size = DSelectSize.normal,
    this.width = 180,
    this.isExpanded = false,
    this.invalid = false,
    this.readOnly = false,
    this.required = false,
    this.highlightItemOnHover = true,
    this.loop = true,
    this.modal = true,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.onOpenChangeComplete,
    this.focusNode,
    this.popoverController,
    this.scrollController,
    this.autofocus = false,
    this.alignItemWithTrigger = true,
    this.side = DPopoverSide.bottom,
    this.align = DPopoverAlign.center,
    this.sideOffset = 4,
    this.alignOffset = 0,
    this.sideCollision = DPopoverCollision.flip,
    this.alignCollision = DPopoverCollision.shift,
    this.collisionPadding = 5,
    this.collisionBoundary,
    this.maxPopupHeight = 320,
    this.isItemEqualToValue,
    super.enabled = true,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
    super.forceErrorText,
  }) : _controlled = true,
       assert(width > 0),
       assert(maxPopupHeight > 0),
       super(builder: (state) => (state as _DSelectFormState<T>)._build());

  final List<DSelectEntry<T>> entries;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final DSelectValueChanged<T>? onChangedWithReason;
  final String placeholder;
  final Widget? label;
  final Widget? description;
  final String? errorText;
  final String? semanticLabel;
  final DSelectValueBuilder<T>? valueBuilder;
  final DSelectTriggerBuilder<T>? triggerBuilder;
  final Widget? icon;
  final Widget? indicator;
  final DSelectSize size;
  final double width;
  final bool isExpanded;
  final bool invalid;
  final bool readOnly;
  final bool required;
  final bool highlightItemOnHover;
  final bool loop;

  /// Keeps keyboard focus within the popup. Flutter pointer dismissal occurs
  /// before the underlying action; unlike the DOM no page scroll lock is added.
  final bool modal;
  final bool? open;
  final bool defaultOpen;
  final DPopoverOpenChange? onOpenChange;
  final ValueChanged<bool>? onOpenChangeComplete;
  final FocusNode? focusNode;
  final DPopoverController? popoverController;
  final ScrollController? scrollController;
  final bool autofocus;
  final bool alignItemWithTrigger;
  final DPopoverSide side;
  final DPopoverAlign align;
  final double sideOffset;
  final double alignOffset;
  final DPopoverCollision sideCollision;
  final DPopoverCollision alignCollision;
  final double collisionPadding;
  final Rect? collisionBoundary;
  final double maxPopupHeight;
  final bool Function(T? itemValue, T? value)? isItemEqualToValue;
  final bool _controlled;

  @override
  FormFieldState<T> createState() => _DSelectFormState<T>();
}

class _DSelectFormState<T> extends FormFieldState<T> {
  @override
  DSelect<T> get widget => super.widget as DSelect<T>;

  @override
  void initState() {
    super.initState();
    if (widget._controlled) setValue(widget.value);
  }

  @override
  void didUpdateWidget(covariant DSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._controlled) setValue(widget.value);
  }

  @override
  void reset() {
    super.reset();
    widget.onChanged?.call(widget.initialValue);
    widget.onChangedWithReason?.call(
      widget.initialValue,
      DSelectChangeReason.formReset,
    );
    if (widget._controlled && mounted) setValue(widget.value);
  }

  void _change(T? next, DSelectChangeReason reason) {
    if (!widget.enabled || widget.readOnly) return;
    didChange(next);
    widget.onChanged?.call(next);
    widget.onChangedWithReason?.call(next, reason);
    if (widget._controlled && mounted) setValue(widget.value);
  }

  Widget _build() => _DSelectBody<T>(
    entries: widget.entries,
    values: [widget._controlled ? widget.value : value],
    onItemChanged: (item, reason) => _change(item.value, reason),
    multiple: false,
    placeholder: widget.placeholder,
    label: widget.label,
    description: widget.description,
    errorText: widget.errorText ?? errorText,
    semanticLabel: widget.semanticLabel,
    valueBuilder: widget.valueBuilder,
    triggerBuilder: widget.triggerBuilder,
    icon: widget.icon,
    indicator: widget.indicator,
    size: widget.size,
    width: widget.width,
    isExpanded: widget.isExpanded,
    enabled: widget.enabled,
    invalid: widget.invalid || hasError,
    readOnly: widget.readOnly,
    required: widget.required,
    highlightItemOnHover: widget.highlightItemOnHover,
    loop: widget.loop,
    modal: widget.modal,
    open: widget.open,
    defaultOpen: widget.defaultOpen,
    onOpenChange: widget.onOpenChange,
    onOpenChangeComplete: widget.onOpenChangeComplete,
    focusNode: widget.focusNode,
    popoverController: widget.popoverController,
    scrollController: widget.scrollController,
    autofocus: widget.autofocus,
    alignItemWithTrigger: widget.alignItemWithTrigger,
    side: widget.side,
    align: widget.align,
    sideOffset: widget.sideOffset,
    alignOffset: widget.alignOffset,
    sideCollision: widget.sideCollision,
    alignCollision: widget.alignCollision,
    collisionPadding: widget.collisionPadding,
    collisionBoundary: widget.collisionBoundary,
    maxPopupHeight: widget.maxPopupHeight,
    equals: widget.isItemEqualToValue ?? (left, right) => left == right,
  );
}

/// Compatibility FormField adapter for callers that previously supplied
/// Flutter [DropdownMenuItem]s and [InputDecoration].
class DSelectField<T> extends StatelessWidget {
  const DSelectField({
    super.key,
    required this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.isExpanded = false,
    this.enabled = true,
    this.readOnly = false,
    this.required = false,
    this.size = DSelectSize.normal,
    this.alignItemWithTrigger = true,
    this.validator,
    this.onSaved,
    this.autovalidateMode,
    this.forceErrorText,
  });

  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;
  final bool enabled;
  final bool readOnly;
  final bool required;
  final DSelectSize size;
  final bool alignItemWithTrigger;
  final FormFieldValidator<T>? validator;
  final FormFieldSetter<T>? onSaved;
  final AutovalidateMode? autovalidateMode;
  final String? forceErrorText;

  @override
  Widget build(BuildContext context) => DSelect<T>(
    entries: _entriesFromDropdownItems(items),
    initialValue: initialValue,
    onChanged: onChanged,
    placeholder: decoration.hintText ?? 'Select an option',
    label: decoration.labelText == null ? null : Text(decoration.labelText!),
    description: decoration.helperText == null
        ? null
        : Text(decoration.helperText!),
    errorText: decoration.errorText,
    semanticLabel: decoration.labelText,
    isExpanded: isExpanded,
    enabled: enabled && onChanged != null,
    readOnly: readOnly,
    required: required,
    size: size,
    alignItemWithTrigger: alignItemWithTrigger,
    validator: validator,
    onSaved: onSaved,
    autovalidateMode: autovalidateMode,
    forceErrorText: forceErrorText,
  );
}

/// Multiple-selection counterpart to [DSelect]. Selecting an item keeps the
/// popup open so several values can be toggled in one keyboard/pointer session.
class DMultiSelect<T> extends FormField<List<T>> {
  DMultiSelect({
    super.key,
    required this.entries,
    List<T> initialValue = const [],
    this.onChanged,
    this.onChangedWithReason,
    this.placeholder = 'Select options',
    this.label,
    this.description,
    this.errorText,
    this.semanticLabel,
    this.valueBuilder,
    this.triggerBuilder,
    this.icon,
    this.indicator,
    this.size = DSelectSize.normal,
    this.width = 180,
    this.isExpanded = false,
    this.invalid = false,
    this.readOnly = false,
    this.required = false,
    this.highlightItemOnHover = true,
    this.loop = true,
    this.modal = true,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.onOpenChangeComplete,
    this.focusNode,
    this.popoverController,
    this.scrollController,
    this.autofocus = false,
    this.side = DPopoverSide.bottom,
    this.align = DPopoverAlign.center,
    this.sideOffset = 4,
    this.alignOffset = 0,
    this.sideCollision = DPopoverCollision.flip,
    this.alignCollision = DPopoverCollision.shift,
    this.collisionPadding = 5,
    this.collisionBoundary,
    this.maxPopupHeight = 320,
    this.isItemEqualToValue,
    super.enabled = true,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
    super.forceErrorText,
  }) : value = null,
       _controlled = false,
       assert(width > 0),
       assert(maxPopupHeight > 0),
       super(
         initialValue: List<T>.unmodifiable(initialValue),
         builder: (state) => (state as _DMultiSelectFormState<T>)._build(),
       );

  DMultiSelect.controlled({
    super.key,
    required this.entries,
    required List<T> value,
    required this.onChanged,
    this.onChangedWithReason,
    List<T> initialValue = const [],
    this.placeholder = 'Select options',
    this.label,
    this.description,
    this.errorText,
    this.semanticLabel,
    this.valueBuilder,
    this.triggerBuilder,
    this.icon,
    this.indicator,
    this.size = DSelectSize.normal,
    this.width = 180,
    this.isExpanded = false,
    this.invalid = false,
    this.readOnly = false,
    this.required = false,
    this.highlightItemOnHover = true,
    this.loop = true,
    this.modal = true,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.onOpenChangeComplete,
    this.focusNode,
    this.popoverController,
    this.scrollController,
    this.autofocus = false,
    this.side = DPopoverSide.bottom,
    this.align = DPopoverAlign.center,
    this.sideOffset = 4,
    this.alignOffset = 0,
    this.sideCollision = DPopoverCollision.flip,
    this.alignCollision = DPopoverCollision.shift,
    this.collisionPadding = 5,
    this.collisionBoundary,
    this.maxPopupHeight = 320,
    this.isItemEqualToValue,
    super.enabled = true,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
    super.forceErrorText,
  }) : value = List<T>.unmodifiable(value),
       _controlled = true,
       assert(width > 0),
       assert(maxPopupHeight > 0),
       super(
         initialValue: List<T>.unmodifiable(initialValue),
         builder: (state) => (state as _DMultiSelectFormState<T>)._build(),
       );

  final List<DSelectEntry<T>> entries;
  final List<T>? value;
  final ValueChanged<List<T>>? onChanged;
  final DMultiSelectValueChanged<T>? onChangedWithReason;
  final String placeholder;
  final Widget? label;
  final Widget? description;
  final String? errorText;
  final String? semanticLabel;
  final DMultiSelectValueBuilder<T>? valueBuilder;
  final DSelectTriggerBuilder<T>? triggerBuilder;
  final Widget? icon;
  final Widget? indicator;
  final DSelectSize size;
  final double width;
  final bool isExpanded;
  final bool invalid;
  final bool readOnly;
  final bool required;
  final bool highlightItemOnHover;
  final bool loop;
  final bool modal;
  final bool? open;
  final bool defaultOpen;
  final DPopoverOpenChange? onOpenChange;
  final ValueChanged<bool>? onOpenChangeComplete;
  final FocusNode? focusNode;
  final DPopoverController? popoverController;
  final ScrollController? scrollController;
  final bool autofocus;
  final DPopoverSide side;
  final DPopoverAlign align;
  final double sideOffset;
  final double alignOffset;
  final DPopoverCollision sideCollision;
  final DPopoverCollision alignCollision;
  final double collisionPadding;
  final Rect? collisionBoundary;
  final double maxPopupHeight;
  final bool Function(T? itemValue, T? value)? isItemEqualToValue;
  final bool _controlled;

  @override
  FormFieldState<List<T>> createState() => _DMultiSelectFormState<T>();
}

class _DMultiSelectFormState<T> extends FormFieldState<List<T>> {
  @override
  DMultiSelect<T> get widget => super.widget as DMultiSelect<T>;

  @override
  void initState() {
    super.initState();
    if (widget._controlled) setValue(widget.value);
  }

  @override
  void didUpdateWidget(covariant DMultiSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._controlled) setValue(widget.value);
  }

  @override
  void reset() {
    super.reset();
    final reset = List<T>.unmodifiable(widget.initialValue ?? const []);
    widget.onChanged?.call(reset);
    widget.onChangedWithReason?.call(reset, DSelectChangeReason.formReset);
    if (widget._controlled && mounted) setValue(widget.value);
  }

  void _toggle(DSelectItem<T> item, DSelectChangeReason reason) {
    if (!widget.enabled || widget.readOnly || item.value == null) return;
    final equals =
        widget.isItemEqualToValue ?? (T? left, T? right) => left == right;
    final next = List<T>.of(widget._controlled ? widget.value! : value ?? []);
    final index = next.indexWhere((value) => equals(item.value, value));
    if (index < 0) {
      next.add(item.value as T);
    } else {
      next.removeAt(index);
    }
    final frozen = List<T>.unmodifiable(next);
    didChange(frozen);
    widget.onChanged?.call(frozen);
    widget.onChangedWithReason?.call(frozen, reason);
    if (widget._controlled && mounted) setValue(widget.value);
  }

  Widget _build() {
    final selected = widget._controlled
        ? widget.value!
        : value ?? List<T>.empty();
    return _DSelectBody<T>(
      entries: widget.entries,
      values: selected.cast<T?>(),
      onItemChanged: _toggle,
      multiple: true,
      placeholder: widget.placeholder,
      label: widget.label,
      description: widget.description,
      errorText: widget.errorText ?? errorText,
      semanticLabel: widget.semanticLabel,
      multiValueBuilder: widget.valueBuilder,
      triggerBuilder: widget.triggerBuilder,
      icon: widget.icon,
      indicator: widget.indicator,
      size: widget.size,
      width: widget.width,
      isExpanded: widget.isExpanded,
      enabled: widget.enabled,
      invalid: widget.invalid || hasError,
      readOnly: widget.readOnly,
      required: widget.required,
      highlightItemOnHover: widget.highlightItemOnHover,
      loop: widget.loop,
      modal: widget.modal,
      open: widget.open,
      defaultOpen: widget.defaultOpen,
      onOpenChange: widget.onOpenChange,
      onOpenChangeComplete: widget.onOpenChangeComplete,
      focusNode: widget.focusNode,
      popoverController: widget.popoverController,
      scrollController: widget.scrollController,
      autofocus: widget.autofocus,
      alignItemWithTrigger: false,
      side: widget.side,
      align: widget.align,
      sideOffset: widget.sideOffset,
      alignOffset: widget.alignOffset,
      sideCollision: widget.sideCollision,
      alignCollision: widget.alignCollision,
      collisionPadding: widget.collisionPadding,
      collisionBoundary: widget.collisionBoundary,
      maxPopupHeight: widget.maxPopupHeight,
      equals: widget.isItemEqualToValue ?? (left, right) => left == right,
    );
  }
}

class _DSelectBody<T> extends StatefulWidget {
  const _DSelectBody({
    required this.entries,
    required this.values,
    required this.onItemChanged,
    required this.multiple,
    required this.placeholder,
    required this.label,
    required this.description,
    required this.errorText,
    required this.semanticLabel,
    required this.size,
    required this.width,
    required this.isExpanded,
    required this.enabled,
    required this.invalid,
    required this.readOnly,
    required this.required,
    required this.highlightItemOnHover,
    required this.loop,
    required this.modal,
    required this.open,
    required this.defaultOpen,
    required this.onOpenChange,
    required this.onOpenChangeComplete,
    required this.focusNode,
    required this.popoverController,
    required this.scrollController,
    required this.autofocus,
    required this.alignItemWithTrigger,
    required this.side,
    required this.align,
    required this.sideOffset,
    required this.alignOffset,
    required this.sideCollision,
    required this.alignCollision,
    required this.collisionPadding,
    required this.collisionBoundary,
    required this.maxPopupHeight,
    required this.equals,
    this.valueBuilder,
    this.multiValueBuilder,
    this.triggerBuilder,
    this.icon,
    this.indicator,
  });

  final List<DSelectEntry<T>> entries;
  final List<T?> values;
  final void Function(DSelectItem<T>, DSelectChangeReason) onItemChanged;
  final bool multiple;
  final String placeholder;
  final Widget? label;
  final Widget? description;
  final String? errorText;
  final String? semanticLabel;
  final DSelectValueBuilder<T>? valueBuilder;
  final DMultiSelectValueBuilder<T>? multiValueBuilder;
  final DSelectTriggerBuilder<T>? triggerBuilder;
  final Widget? icon;
  final Widget? indicator;
  final DSelectSize size;
  final double width;
  final bool isExpanded;
  final bool enabled;
  final bool invalid;
  final bool readOnly;
  final bool required;
  final bool highlightItemOnHover;
  final bool loop;
  final bool modal;
  final bool? open;
  final bool defaultOpen;
  final DPopoverOpenChange? onOpenChange;
  final ValueChanged<bool>? onOpenChangeComplete;
  final FocusNode? focusNode;
  final DPopoverController? popoverController;
  final ScrollController? scrollController;
  final bool autofocus;
  final bool alignItemWithTrigger;
  final DPopoverSide side;
  final DPopoverAlign align;
  final double sideOffset;
  final double alignOffset;
  final DPopoverCollision sideCollision;
  final DPopoverCollision alignCollision;
  final double collisionPadding;
  final Rect? collisionBoundary;
  final double maxPopupHeight;
  final bool Function(T?, T?) equals;

  @override
  State<_DSelectBody<T>> createState() => _DSelectBodyState<T>();
}

class _DSelectBodyState<T> extends State<_DSelectBody<T>> {
  late final DPopoverController _ownedPopover;
  late final ScrollController _ownedScroll;
  late final FocusNode _ownedFocus;
  final List<FocusNode> _optionFocus = [];
  bool _localOpen = false;
  bool _pointerHighlight = false;
  int? _hoveredIndex;
  bool _triggerFocused = false;
  bool _triggerHovered = false;
  bool _openedWithTouch = false;
  String _typeahead = '';
  Timer? _typeaheadTimer;
  Duration? _lastTypedAt;
  int? _lastTypeaheadMatch;

  DPopoverController get _popover => widget.popoverController ?? _ownedPopover;
  ScrollController get _scroll => widget.scrollController ?? _ownedScroll;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  List<DSelectItem<T>> get _items => [
    for (final entry in widget.entries)
      if (entry case DSelectItem<T> item)
        item
      else if (entry case DSelectGroup<T> group)
        ...group.items,
  ];

  bool get _isOpen => widget.open ?? _localOpen;
  bool get _touch => switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    _ownedPopover = DPopoverController();
    _ownedScroll = ScrollController();
    _ownedFocus = FocusNode(debugLabel: 'DSelect trigger');
    _scroll.addListener(_scrollChanged);
    _localOpen = widget.defaultOpen;
    _syncNodes();
  }

  @override
  void didUpdateWidget(covariant _DSelectBody<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      (oldWidget.scrollController ?? _ownedScroll).removeListener(
        _scrollChanged,
      );
      _scroll.addListener(_scrollChanged);
    }
    if (_items.length != _optionFocus.length) {
      _syncNodes();
    } else if (oldWidget.open != widget.open) {
      _setOptionFocusability(_isOpen);
      if (_isOpen) _focusInitial();
    }
    if (!_isOpen &&
        _lastTypeaheadMatch != null &&
        _selectedIndex != _lastTypeaheadMatch) {
      _resetTypeahead();
    }
  }

  void _scrollChanged() {
    if (mounted) setState(() {});
  }

  void _syncNodes() {
    for (final node in _optionFocus) {
      node.dispose();
    }
    _optionFocus
      ..clear()
      ..addAll(
        List.generate(
          _items.length,
          (index) => FocusNode(
            debugLabel: 'DSelect option $index',
            canRequestFocus: _isOpen,
            skipTraversal: !_isOpen,
          ),
        ),
      );
  }

  void _setOptionFocusability(bool open) {
    for (final node in _optionFocus) {
      node.canRequestFocus = open;
      node.skipTraversal = !open;
    }
  }

  bool _selected(DSelectItem<T> item) =>
      widget.values.any((value) => widget.equals(item.value, value));

  int get _selectedIndex => _items.indexWhere(_selected);

  int _enabledFrom(int start, int delta, {bool includeStart = false}) {
    final items = _items;
    if (items.isEmpty) return -1;
    var index = start;
    for (var count = 0; count < items.length; count++) {
      if (!includeStart || count > 0) index += delta;
      if (widget.loop) {
        index %= items.length;
      } else if (index < 0 || index >= items.length) {
        return -1;
      }
      if (items[index].enabled) return index;
    }
    return -1;
  }

  void _focusIndex(int index) {
    if (index < 0 || index >= _optionFocus.length) return;
    _optionFocus[index].requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final context = _optionFocus[index].context;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: DMotion.duration(context, const Duration(milliseconds: 80)),
        );
      }
    });
  }

  void _focusInitial({bool last = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isOpen) return;
      final selected = _selectedIndex;
      final index = selected >= 0 && _items[selected].enabled
          ? selected
          : _enabledFrom(
              last ? _items.length - 1 : 0,
              last ? -1 : 1,
              includeStart: true,
            );
      _focusIndex(index);
    });
  }

  void _openWith(DPopoverTriggerState trigger, {bool last = false}) {
    if (!widget.enabled) return;
    _openedWithTouch = false;
    trigger.openPopover(DPopoverInteraction.keyboard);
    _focusInitial(last: last);
  }

  KeyEventResult _triggerKey(DPopoverTriggerState trigger, KeyEvent event) {
    if (event is! KeyDownEvent || !widget.enabled) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _openWith(trigger);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _openWith(trigger, last: true);
      return KeyEventResult.handled;
    }
    if (!widget.readOnly &&
        !widget.multiple &&
        _handleTypeahead(event, current: _selectedIndex, commit: true)) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _openedWithTouch = false;
      trigger.toggle(DPopoverInteraction.keyboard);
      if (!_isOpen) _focusInitial();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _popupKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_pointerHighlight) setState(() => _pointerHighlight = false);
    final current = _optionFocus.indexWhere((node) => node.hasPrimaryFocus);
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final delta = event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
      _focusIndex(
        current < 0
            ? _enabledFrom(
                delta > 0 ? 0 : _items.length - 1,
                delta,
                includeStart: true,
              )
            : _enabledFrom(current, delta),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _focusIndex(_enabledFrom(0, 1, includeStart: true));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _focusIndex(_enabledFrom(_items.length - 1, -1, includeStart: true));
      return KeyEventResult.handled;
    }
    if (widget.modal && event.logicalKey == LogicalKeyboardKey.tab) {
      final backwards = HardwareKeyboard.instance.isShiftPressed;
      _focusIndex(
        _enabledFrom(
          current < 0 ? (backwards ? _items.length - 1 : 0) : current,
          backwards ? -1 : 1,
          includeStart: current < 0,
        ),
      );
      return KeyEventResult.handled;
    }
    if (_handleTypeahead(event, current: current, commit: false)) {
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) &&
        current >= 0) {
      _choose(_items[current], DSelectChangeReason.keyboard);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _handleTypeahead(
    KeyEvent event, {
    required int current,
    required bool commit,
  }) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return false;
    }
    final recent =
        _lastTypedAt != null &&
        event.timeStamp - _lastTypedAt! < const Duration(milliseconds: 700);
    final character = event.logicalKey == LogicalKeyboardKey.space
        ? ' '
        : event.character;
    if (character == null ||
        character.length != 1 ||
        (character.trim().isEmpty && (!recent || _typeahead.isEmpty))) {
      return false;
    }

    _typeaheadTimer?.cancel();
    final letter = character.toLowerCase();
    final repeated =
        letter.trim().isNotEmpty &&
        recent &&
        _typeahead.isNotEmpty &&
        _typeahead.runes.every((rune) => String.fromCharCode(rune) == letter);
    _typeahead = recent && !repeated ? '$_typeahead$letter' : letter;
    _lastTypedAt = event.timeStamp;
    _typeaheadTimer = Timer(const Duration(milliseconds: 700), () {
      _typeahead = '';
    });
    final items = _items;
    final start = recent && !repeated
        ? (_lastTypeaheadMatch ?? current)
        : ((recent ? (_lastTypeaheadMatch ?? current) : current) + 1);
    for (var step = 0; step < items.length; step++) {
      final index = (math.max(0, start) + step) % items.length;
      if (items[index].enabled &&
          items[index].textValue.toLowerCase().startsWith(_typeahead)) {
        _lastTypeaheadMatch = index;
        if (commit) {
          widget.onItemChanged(items[index], DSelectChangeReason.keyboard);
        } else {
          _focusIndex(index);
        }
        break;
      }
    }
    return true;
  }

  void _resetTypeahead() {
    _typeaheadTimer?.cancel();
    _typeahead = '';
    _lastTypedAt = null;
    _lastTypeaheadMatch = null;
  }

  void _choose(DSelectItem<T> item, DSelectChangeReason reason) {
    if (!widget.enabled || widget.readOnly || !item.enabled) return;
    if (!widget.multiple) _popover.close();
    widget.onItemChanged(item, reason);
  }

  void _openChanged(bool open, DPopoverChangeReason reason) {
    if (widget.open == null) setState(() => _localOpen = open);
    _setOptionFocusability(open);
    if (!open && _optionFocus.any((node) => node.hasFocus)) {
      _focus.requestFocus();
    }
    if (!open) {
      _pointerHighlight = false;
      _hoveredIndex = null;
      _resetTypeahead();
    }
    widget.onOpenChange?.call(open, reason);
    if (open) _focusInitial();
  }

  Widget _value() {
    final items = _items.where(_selected).toList(growable: false);
    if (widget.multiple) {
      if (widget.multiValueBuilder != null) {
        return widget.multiValueBuilder!(
          context,
          widget.values.whereType<T>().toList(growable: false),
          items,
        );
      }
      if (items.isEmpty) return Text(widget.placeholder);
      final first = items.first.textValue;
      return Text(
        items.length == 1 ? first : '$first (+${items.length - 1} more)',
      );
    }
    final item = items.firstOrNull;
    final value = widget.values.firstOrNull;
    if (widget.valueBuilder != null) {
      return widget.valueBuilder!(context, value, item);
    }
    return Text(item?.textValue ?? widget.placeholder);
  }

  double _naturalHeight(double itemHeight, double labelHeight) {
    var height = 0.0;
    for (final entry in widget.entries) {
      height += switch (entry) {
        DSelectItem<T>() => itemHeight,
        DSelectGroup<T>(:final label, :final items) =>
          8 + (label == null ? 0 : labelHeight) + items.length * itemHeight,
        DSelectSeparator<T>() => 9,
      };
    }
    return height;
  }

  double? _selectedCenter(
    double itemHeight,
    double labelHeight,
    double viewportHeight, {
    required bool scrollable,
    required bool arrows,
  }) {
    if (!widget.alignItemWithTrigger || widget.multiple) return null;
    final selected = _selectedIndex;
    if (selected < 0) return null;
    if (scrollable) {
      final arrowHeight = arrows ? 24.0 : 0.0;
      return arrowHeight + (viewportHeight - arrowHeight * 2) / 2;
    }
    var offset = 0.0;
    var index = 0;
    for (final entry in widget.entries) {
      if (entry is DSelectItem<T>) {
        if (index == selected) break;
        offset += itemHeight;
        index++;
      } else if (entry case DSelectGroup<T> group) {
        offset += 4 + (group.label == null ? 0 : labelHeight);
        for (final _ in group.items) {
          if (index == selected) {
            return offset + itemHeight / 2;
          }
          offset += itemHeight;
          index++;
        }
        offset += 4;
      } else {
        offset += 9;
      }
    }
    return offset + itemHeight / 2;
  }

  Widget _entry(
    DSelectEntry<T> entry,
    double itemHeight,
    double labelHeight,
    Iterator<int> indices,
  ) {
    if (entry case DSelectItem<T> item) {
      indices.moveNext();
      final index = indices.current;
      return _DSelectOptionRow<T>(
        pointerHighlighted: _pointerHighlight ? _hoveredIndex == index : null,
        onHover: (hovered) {
          if (!widget.highlightItemOnHover) return;
          if (_pointerHighlight && _hoveredIndex == (hovered ? index : null)) {
            return;
          }
          setState(() {
            _pointerHighlight = true;
            if (hovered) {
              _hoveredIndex = index;
            } else if (_hoveredIndex == index) {
              _hoveredIndex = null;
            }
          });
        },
        item: item,
        index: indices.current,
        focusNode: _optionFocus[indices.current],
        selected: _selected(item),
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        multiple: widget.multiple,
        highlightItemOnHover: widget.highlightItemOnHover,
        height: itemHeight,
        indicator: widget.indicator,
        onChoose: _choose,
      );
    }
    if (entry case DSelectGroup<T> group) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (group.label != null)
                SizedBox(
                  height: labelHeight,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 6,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: DiscourseTypography.xs,
                          height: DiscourseTypography.lineHeightCaption,
                          color: DTokens.of(context).mutedForeground,
                        ),
                        child: group.label!,
                      ),
                    ),
                  ),
                ),
              for (final item in group.items)
                _entry(item, itemHeight, labelHeight, indices),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ExcludeSemantics(
        child: SizedBox(
          height: 1,
          child: ColoredBox(color: DTokens.of(context).border),
        ),
      ),
    );
  }

  DPopoverContent _popup(double popupWidth) {
    final touch = _touch;
    final scaler = MediaQuery.textScalerOf(context);
    final scaledLineHeight =
        scaler.scale(DiscourseTypography.sm) *
        DiscourseTypography.lineHeightSmall;
    final itemHeight = math.max(
      touch ? DSpacing.touchTarget : 28.0,
      scaledLineHeight + 8,
    );
    final labelHeight = math.max(
      24.0,
      scaler.scale(DiscourseTypography.xs) *
              DiscourseTypography.lineHeightCaption +
          8,
    );
    final naturalHeight = _naturalHeight(itemHeight, labelHeight);
    final viewportHeight = math.max(0.0, widget.maxPopupHeight - 8);
    final height = math.min(viewportHeight, naturalHeight);
    final overflows = naturalHeight > viewportHeight;
    final arrows = overflows && !touch;
    final selectedCenter = _selectedCenter(
      itemHeight,
      labelHeight,
      height,
      scrollable: overflows,
      arrows: arrows,
    );
    final indices = Iterable<int>.generate(_items.length).iterator;
    final list = Focus(
      onKeyEvent: (_, event) => _popupKey(event),
      child: DScrollArea(
        controller: _scroll,
        thumbVisibility: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in widget.entries)
              _entry(entry, itemHeight, labelHeight, indices),
          ],
        ),
      ),
    );
    final canScrollUp = _scroll.hasClients && _scroll.offset > 0.5;
    final canScrollDown =
        overflows &&
        (!_scroll.hasClients ||
            _scroll.offset < _scroll.position.maxScrollExtent - 0.5);
    final content = arrows
        ? Column(
            children: [
              _DSelectScrollArrow(
                controller: _scroll,
                up: true,
                enabled: canScrollUp,
              ),
              Expanded(child: list),
              _DSelectScrollArrow(
                controller: _scroll,
                up: false,
                enabled: canScrollDown,
              ),
            ],
          )
        : list;
    return DPopoverContent(
      semanticLabel: widget.semanticLabel ?? 'Select options',
      width: popupWidth,
      constraints: BoxConstraints(maxHeight: widget.maxPopupHeight),
      padding: const EdgeInsets.all(4),
      scrollable: false,
      side: widget.side,
      align: widget.align,
      sideOffset: widget.sideOffset,
      alignOffset: widget.alignOffset,
      sideCollision: widget.sideCollision,
      alignCollision: widget.alignCollision,
      collisionPadding: widget.collisionPadding,
      collisionBoundary: widget.collisionBoundary,
      placementResolver: selectedCenter != null && !_openedWithTouch
          ? (placement) {
              if (_openedWithTouch ||
                  placement.target.top - placement.boundary.top < 20 ||
                  placement.boundary.bottom - placement.target.bottom < 20) {
                return null;
              }
              final top = placement.target.center.dy - selectedCenter - 4;
              if (top < placement.boundary.top ||
                  top + placement.contentSize.height >
                      placement.boundary.bottom) {
                return null;
              }
              return Offset(placement.defaultOffset.dx, top);
            }
          : null,
      child: SizedBox(height: height, child: content),
    );
  }

  Widget _trigger(DPopoverTriggerState trigger, double popupWidth) {
    final tokens = DTokens.of(context);
    final invalid = widget.invalid || widget.errorText != null;
    final small = widget.size == DSelectSize.small;
    final controlSize = small ? DControlSize.small : DControlSize.regular;
    final visualHeight = math.max(
      DControlStyle.height(controlSize),
      MediaQuery.textScalerOf(context).scale(DiscourseTypography.sm) *
              DiscourseTypography.lineHeightSmall +
          (small ? 6 : 10),
    );
    final baseRadius = DControlStyle.radius(tokens, controlSize);
    final joined = DJoinedControlScope.maybeOf(context);
    final radius =
        joined?.resolveRadius(
          BorderRadius.circular(baseRadius),
          Directionality.of(context),
        ) ??
        BorderRadius.circular(baseRadius);
    final foreground =
        widget.values.any(
          (value) => _items.any((item) => widget.equals(item.value, value)),
        )
        ? tokens.foreground
        : tokens.mutedForeground;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final input = tokens.colors.outlineVariant;
    final background = DControlStyle.outlineFill(
      tokens,
      dark: dark,
      field: true,
      hovered: _triggerHovered && widget.enabled,
    );
    final border = invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? 0.5 : 1),
          )
        : input;
    final visual = AnimatedContainer(
      key: const Key('d-select-trigger-visual'),
      duration: DMotion.duration(context, DControlStyle.duration),
      curve: Curves.ease,
      height: visualHeight,
      width: popupWidth,
      padding: const EdgeInsetsDirectional.only(
        start: 11,
        end: 9,
        top: 1,
        bottom: 1,
      ),
      decoration: DControlDecoration(
        color: background,
        borderColor: border,
        borderRadius: radius,
        joinedAxis: (joined?.omitsLeadingBorder ?? false) ? joined?.axis : null,
        ringColor: DControlStyle.alpha(
          invalid ? tokens.destructive : tokens.focusRing,
          invalid ? (dark ? .4 : .2) : .5,
        ),
        ringWidth: _triggerFocused || invalid ? 3 : 0,
      ),
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle.merge(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: DiscourseTypography.sm,
                height: DiscourseTypography.lineHeightSmall,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
              child: _value(),
            ),
          ),
          const SizedBox(width: DControlStyle.gap),
          IconTheme(
            data: IconThemeData(
              color: tokens.foreground,
              size: DControlStyle.iconSize,
            ),
            child:
                widget.icon ??
                const DIcon(DIcons.chevronDown, size: DControlStyle.iconSize),
          ),
        ],
      ),
    );
    final semanticsLabel =
        widget.semanticLabel ??
        (widget.label is Text ? (widget.label as Text).data : null) ??
        widget.placeholder;
    Widget action = Semantics(
      button: true,
      enabled: widget.enabled,
      readOnly: widget.readOnly ? true : null,
      expanded: trigger.open,
      validationResult: invalid
          ? SemanticsValidationResult.invalid
          : SemanticsValidationResult.none,
      label: semanticsLabel,
      value: _items.where(_selected).map((item) => item.textValue).join(', '),
      onTap: widget.enabled ? trigger.toggle : null,
      child: ExcludeSemantics(child: visual),
    );
    action = Focus(
      focusNode: trigger.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      skipTraversal: !widget.enabled,
      onFocusChange: (value) => setState(() => _triggerFocused = value),
      onKeyEvent: (_, event) => _triggerKey(trigger, event),
      child: MouseRegion(
        onEnter: (_) => setState(() => _triggerHovered = true),
        onExit: (_) => setState(() => _triggerHovered = false),
        child: Listener(
          onPointerDown: (event) {
            _openedWithTouch = event.kind == PointerDeviceKind.touch;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? trigger.toggle : null,
            child: action,
          ),
        ),
      ),
    );
    if (!widget.enabled) action = Opacity(opacity: 0.5, child: action);
    if (_touch && visualHeight < DSpacing.touchTarget) {
      action = SizedBox(
        height: DSpacing.touchTarget,
        child: Center(child: action),
      );
    }
    final state = DSelectTriggerState<T>(
      open: trigger.open,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      invalid: invalid,
      values: List<T?>.unmodifiable(widget.values),
      focusNode: trigger.focusNode,
      toggle: trigger.toggle,
    );
    return widget.triggerBuilder?.call(context, state, action) ?? action;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : widget.width;
        final popupWidth = widget.isExpanded
            ? math.max(0, available)
            : math.min(widget.width, math.max(0, available));
        Widget select = DPopover(
          open: _isOpen,
          controller: _popover,
          focusContentOnOpen: false,
          onOpenChange: _openChanged,
          onOpenChangeComplete: widget.onOpenChangeComplete,
          content: _popup(math.max(144, popupWidth).toDouble()),
          child: DPopoverTrigger(
            focusNode: _focus,
            builder: (context, trigger) =>
                _trigger(trigger, popupWidth.toDouble()),
          ),
        );
        final tokens = DTokens.of(context);
        if (widget.label != null ||
            widget.description != null ||
            widget.errorText != null) {
          select = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.label != null) ...[
                GestureDetector(
                  onTap: widget.enabled ? _focus.requestFocus : null,
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(
                      fontSize: DiscourseTypography.sm,
                      height: DiscourseTypography.lineHeightSmall,
                      fontWeight: FontWeight.w500,
                    ),
                    child: widget.label!,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              select,
              if (widget.description != null) ...[
                const SizedBox(height: 6),
                DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: DiscourseTypography.sm,
                    height: DiscourseTypography.lineHeightSmall,
                    color: tokens.mutedForeground,
                  ),
                  child: widget.description!,
                ),
              ],
              if (widget.errorText case final error?) ...[
                const SizedBox(height: 6),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(
                      fontSize: DiscourseTypography.sm,
                      height: DiscourseTypography.lineHeightSmall,
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
          isRequired: widget.required ? true : null,
          child: select,
        );
      },
    );
  }

  @override
  void dispose() {
    _typeaheadTimer?.cancel();
    for (final node in _optionFocus) {
      node.dispose();
    }
    _scroll.removeListener(_scrollChanged);
    _ownedPopover.dispose();
    _ownedScroll.dispose();
    _ownedFocus.dispose();
    super.dispose();
  }
}

class _DSelectOptionRow<T> extends StatefulWidget {
  const _DSelectOptionRow({
    required this.item,
    required this.index,
    required this.pointerHighlighted,
    required this.onHover,
    required this.focusNode,
    required this.selected,
    required this.enabled,
    required this.readOnly,
    required this.multiple,
    required this.highlightItemOnHover,
    required this.height,
    required this.indicator,
    required this.onChoose,
  });

  final DSelectItem<T> item;
  final int index;
  final bool? pointerHighlighted;
  final ValueChanged<bool> onHover;
  final FocusNode focusNode;
  final bool selected;
  final bool enabled;
  final bool readOnly;
  final bool multiple;
  final bool highlightItemOnHover;
  final double height;
  final Widget? indicator;
  final void Function(DSelectItem<T>, DSelectChangeReason) onChoose;

  @override
  State<_DSelectOptionRow<T>> createState() => _DSelectOptionRowState<T>();
}

class _DSelectOptionRowState<T> extends State<_DSelectOptionRow<T>> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final enabled = widget.enabled && widget.item.enabled;
    // Pointer feedback remains visible even if another control takes focus.
    // Keyboard input restores focus-based highlighting for the whole menu.
    final highlighted = enabled && (widget.pointerHighlighted ?? _focused);
    final foreground = highlighted
        ? tokens.selectedForeground
        : tokens.foreground;
    // Highlight changes are atomic. Animating two independent row backgrounds
    // makes the previous and next options appear highlighted at the same time.
    Widget row = Container(
      key: ValueKey(('d-select-item', widget.item.value)),
      height: widget.height,
      padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 8, 4),
      decoration: BoxDecoration(
        color: highlighted ? Theme.of(context).hoverColor : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radius * 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle.merge(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: DiscourseTypography.sm,
                height: DiscourseTypography.lineHeightSmall,
                fontWeight: FontWeight.w400,
              ),
              child: widget.item.child,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 16,
            child: Opacity(
              opacity: widget.selected ? 1 : 0,
              child: IconTheme.merge(
                data: IconThemeData(
                  color: highlighted ? foreground : tokens.mutedForeground,
                  size: 16,
                ),
                child: widget.indicator ?? const DIcon(DIcons.check, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
    row = Semantics(
      container: true,
      button: !widget.multiple,
      checked: widget.multiple ? widget.selected : null,
      selected: widget.multiple ? null : widget.selected,
      inMutuallyExclusiveGroup: widget.multiple ? null : true,
      enabled: enabled,
      readOnly: widget.readOnly ? true : null,
      label: widget.item.semanticLabel ?? widget.item.textValue,
      onTap: enabled && !widget.readOnly
          ? () => widget.onChoose(widget.item, DSelectChangeReason.itemPress)
          : null,
      child: ExcludeSemantics(child: row),
    );
    return MouseRegion(
      onEnter: (_) {
        if (enabled && widget.highlightItemOnHover) {
          widget.onHover(true);
          widget.focusNode.requestFocus();
        }
      },
      onHover: (_) {
        if (enabled && widget.highlightItemOnHover) widget.onHover(true);
      },
      onExit: (_) => widget.onHover(false),
      child: Focus(
        focusNode: widget.focusNode,
        canRequestFocus: enabled,
        onFocusChange: (value) => setState(() => _focused = value),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled && !widget.readOnly
              ? () =>
                    widget.onChoose(widget.item, DSelectChangeReason.itemPress)
              : null,
          child: Opacity(opacity: enabled ? 1 : 0.5, child: row),
        ),
      ),
    );
  }
}

class _DSelectScrollArrow extends StatefulWidget {
  const _DSelectScrollArrow({
    required this.controller,
    required this.up,
    required this.enabled,
  });

  final ScrollController controller;
  final bool up;
  final bool enabled;

  @override
  State<_DSelectScrollArrow> createState() => _DSelectScrollArrowState();
}

class _DSelectScrollArrowState extends State<_DSelectScrollArrow> {
  Timer? _timer;

  void _scroll([double distance = 36]) {
    if (!widget.enabled || !widget.controller.hasClients) return;
    final position = widget.controller.position;
    final next = (position.pixels + (widget.up ? -distance : distance)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    widget.controller.animateTo(
      next.toDouble(),
      duration: DMotion.duration(context, const Duration(milliseconds: 80)),
      curve: Curves.easeOut,
    );
  }

  void _start() {
    _scroll(16);
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 60),
      (_) => _scroll(8),
    );
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didUpdateWidget(covariant _DSelectScrollArrow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _stop();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: widget.enabled ? (_) => _start() : null,
    onExit: (_) => _stop(),
    child: Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.up ? 'Scroll options up' : 'Scroll options down',
      onTap: widget.enabled ? _scroll : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _scroll : null,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0,
          child: SizedBox(
            height: 24,
            child: Center(
              child: Transform.rotate(
                angle: widget.up ? math.pi : 0,
                child: const DIcon(DIcons.chevronDown, size: 16),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
