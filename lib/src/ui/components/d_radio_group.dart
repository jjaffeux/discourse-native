import 'package:flutter/material.dart';

import '../foundation/tokens.dart';
import 'd_label.dart';

/// A single selection with native radio roving focus and Form integration.
///
/// The default constructor owns selection initialized by [initialValue]. Use
/// [DRadioGroup.controlled] when a parent owns [groupValue]. Reset restores
/// [initialValue] and notifies [onChanged], including in controlled mode.
/// Children may be laid out freely and compose [DRadioGroupItem] with future
/// Field widgets. Item values must be distinct within the group.
class DRadioGroup<T> extends FormField<T> {
  DRadioGroup({
    super.key,
    super.initialValue,
    this.onChanged,
    required this.child,
    this.label,
    this.description,
    this.invalid = false,
    this.readOnly = false,
    this.required = false,
    super.enabled = true,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
    super.forceErrorText,
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
    this.description,
    this.invalid = false,
    this.readOnly = false,
    this.required = false,
    super.enabled = true,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
    super.forceErrorText,
  }) : _controlled = true,
       super(builder: (state) => (state as _DRadioGroupState<T>)._build());

  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget child;
  final Widget? label;
  final Widget? description;
  final bool invalid;

  /// Prevent user selection while retaining focus and arrow navigation.
  /// Individual items may override this inherited value.
  final bool readOnly;

  /// Announces the requirement. Supply [validator] for application-specific
  /// validation and localized error text; Form remains the validation owner.
  final bool required;
  final bool _controlled;

  @override
  FormFieldState<T> createState() => _DRadioGroupState<T>();
}

class _DRadioGroupState<T> extends FormFieldState<T> {
  final _items = <Object, ({T value, bool readOnly})>{};
  @override
  DRadioGroup<T> get widget => super.widget as DRadioGroup<T>;

  @override
  void initState() {
    super.initState();
    if (widget._controlled) setValue(widget.groupValue);
  }

  @override
  void didUpdateWidget(covariant DRadioGroup<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._controlled) setValue(widget.groupValue);
  }

  @override
  void reset() {
    super.reset();
    widget.onChanged?.call(widget.initialValue);
    if (widget._controlled && mounted) setValue(widget.groupValue);
  }

  Widget _build() {
    final tokens = DTokens.of(context);
    final enabled =
        widget.enabled &&
        (widget.readOnly || !widget._controlled || widget.onChanged != null);
    final selection = widget._controlled ? widget.groupValue : value;
    Widget result = _RadioScope<T>(
      items: _items,
      readOnly: widget.readOnly,
      required: widget.required,
      enabled: enabled,
      invalid: widget.invalid || hasError,
      child: RadioGroup<T>(
        groupValue: selection,
        onChanged: (next) {
          final target = next ?? selection;
          final item = _items.values
              .where((item) => item.value == target)
              .firstOrNull;
          if (!enabled || (item?.readOnly ?? widget.readOnly)) return;
          didChange(next);
          widget.onChanged?.call(next);
          if (widget._controlled && mounted) setValue(widget.groupValue);
        },
        child: widget.child,
      ),
    );
    if (widget.label != null || widget.description != null || hasError) {
      result = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.label != null) ...[
            DLabel(child: widget.label!),
            const SizedBox(height: 8),
          ],
          if (widget.description != null) ...[
            DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 14,
                height: 20 / 14,
                color: tokens.mutedForeground,
              ),
              child: widget.description!,
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
                style: TextStyle(fontSize: 14, color: tokens.destructive),
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
      child: result,
    );
  }
}

class _RadioScope<T> extends InheritedWidget {
  const _RadioScope({
    required this.enabled,
    required this.invalid,
    required this.readOnly,
    required this.required,
    required this.items,
    required super.child,
  });
  final bool enabled;
  final bool invalid;
  final bool readOnly;
  final bool required;
  final Map<Object, ({T value, bool readOnly})> items;
  @override
  bool updateShouldNotify(_RadioScope<T> oldWidget) =>
      enabled != oldWidget.enabled ||
      invalid != oldWidget.invalid ||
      readOnly != oldWidget.readOnly ||
      required != oldWidget.required ||
      items != oldWidget.items;
}

/// One radio, optionally with an associated label and description.
///
/// The entire label row activates the radio and has one focus/semantics owner.
/// Keep independent links outside [label] and [description]. A bare item needs
/// [semanticLabel]. Borrowed [focusNode] is never disposed by this widget.
/// Touch platforms keep transparent 48px bounds around the 16px visual.
class DRadioGroupItem<T> extends StatefulWidget {
  const DRadioGroupItem({
    super.key,
    required this.value,
    this.label,
    this.description,
    this.trailing,
    this.semanticLabel,
    this.enabled = true,
    this.invalid = false,
    this.focusNode,
    this.autofocus = false,
    this.card = false,
    this.toggleable = false,
    this.readOnly,
    this.required,
  }) : assert(label != null || semanticLabel != null);

  final T value;
  final Widget? label;
  final Widget? description;
  final Widget? trailing;
  final String? semanticLabel;
  final bool enabled;
  final bool invalid;
  final FocusNode? focusNode;
  final bool autofocus;

  /// A clickable choice card, with content before the radio in reading order.
  final bool card;

  /// Allow deselection for domains such as withdrawing a Poll vote.
  final bool toggleable;

  /// Null inherits the group's readOnly value; false explicitly allows edits.
  final bool? readOnly;

  /// Null inherits the group's required announcement. The group validator
  /// owns validation, including when this item overrides the announcement.
  final bool? required;

  @override
  State<DRadioGroupItem<T>> createState() => _DRadioGroupItemState<T>();
}

class _DRadioGroupItemState<T> extends State<DRadioGroupItem<T>> {
  late FocusNode _focus;
  _RadioScope<T>? _scope;
  @override
  void initState() {
    super.initState();
    _attach();
    FocusManager.instance.addHighlightModeListener(_highlightChanged);
  }

  void _attach() {
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _highlightChanged(FocusHighlightMode mode) => _changed();
  void _detach() {
    _focus.removeListener(_changed);
    if (widget.focusNode == null) _focus.dispose();
  }

  @override
  void didUpdateWidget(covariant DRadioGroupItem<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _focus.removeListener(_changed);
      if (oldWidget.focusNode == null) _focus.dispose();
      _attach();
    }
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
    final scope = context.dependOnInheritedWidgetOfExactType<_RadioScope<T>>();
    if (_scope?.items != scope?.items) _scope?.items.remove(this);
    _scope = scope;
    final readOnly = widget.readOnly ?? scope?.readOnly ?? false;
    scope?.items[this] = (value: widget.value, readOnly: readOnly);
    final registry = RadioGroup.maybeOf<T>(context);
    assert(
      registry != null,
      'DRadioGroupItem requires a DRadioGroup of the same type.',
    );
    final enabled = widget.enabled && (scope?.enabled ?? true);
    final invalid = widget.invalid || (scope?.invalid ?? false);
    final tokens = DTokens.of(context);
    final checked = registry?.groupValue == widget.value;
    final focused =
        _focus.hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS ||
      TargetPlatform.android ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
    final border = checked
        ? tokens.primary
        : invalid
        ? tokens.destructive.withValues(alpha: dark ? 0.5 : 1)
        : focused
        ? tokens.focusRing
        : tokens.border;
    final ring = invalid
        ? tokens.destructive.withValues(alpha: dark ? 0.4 : 0.2)
        : tokens.focusRing.withValues(alpha: 0.5);
    final indicator = Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked
            ? tokens.primary
            : dark
            ? tokens.border.withValues(alpha: 0.3)
            : Colors.transparent,
        border: Border.all(color: border),
        boxShadow: invalid || focused
            ? [BoxShadow(color: ring, spreadRadius: 3)]
            : null,
      ),
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
            DLabel(child: widget.label!),
            if (widget.description != null) ...[
              const SizedBox(height: 6),
              DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  color: tokens.mutedForeground,
                ),
                child: widget.description!,
              ),
            ],
          ],
        ),
      );
      content = Row(
        children: [
          if (!widget.card) ...[indicator, const SizedBox(width: 12)],
          text,
          if (widget.trailing != null) ...[
            const SizedBox(width: 12),
            widget.trailing!,
          ],
          if (widget.card) ...[const SizedBox(width: 12), indicator],
        ],
      );
    }
    if (widget.card) {
      content = Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radius + 4),
          border: Border.all(color: checked ? tokens.primary : tokens.border),
          color: checked ? tokens.primary.withValues(alpha: 0.05) : null,
        ),
        child: content,
      );
    }
    return MergeSemantics(
      child: Semantics(
        container: true,
        label: widget.semanticLabel,
        readOnly: readOnly,
        isRequired: (widget.required ?? scope?.required ?? false) ? true : null,
        child: RawRadio<T>(
          value: widget.value,
          enabled: enabled,
          groupRegistry: registry,
          mouseCursor: WidgetStatePropertyAll(
            !enabled
                ? SystemMouseCursors.forbidden
                : readOnly
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
          ),
          toggleable: widget.toggleable,
          focusNode: _focus,
          autofocus: widget.autofocus,
          builder: (context, state) => Opacity(
            opacity: enabled ? 1 : 0.5,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: touch ? 48 : 40,
                minHeight: touch ? 48 : 32,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                heightFactor: 1,
                child: ColoredBox(color: Colors.transparent, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
