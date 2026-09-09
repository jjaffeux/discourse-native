import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_label.dart';

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
  }

  @override
  void didChange(T? value) {
    // Form observers must never save or validate an unaccepted proposal.
    super.didChange(widget._controlled ? widget.groupValue : value);
  }

  @override
  void reset() {
    setValue(widget._controlled ? widget.groupValue : _initialValue);
    // Clear validation/interaction state and notify Form only after restoring
    // the accepted value. super.reset() would publish the latest initialValue.
    super.clearError();
    widget.onChanged?.call(_initialValue);
  }

  Widget _build() {
    final tokens = DTokens.of(context);
    final enabled =
        widget.enabled &&
        (widget.readOnly || !widget._controlled || widget.onChanged != null);
    final selection = widget._controlled ? widget.groupValue : value;
    Widget result = _RadioScope<T>(
      key: _contentKey,
      items: _items,
      readOnly: widget.readOnly,
      required: widget.required,
      enabled: enabled,
      invalid: widget.invalid || hasError,
      errorText: errorText,
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
            DLabel(
              style: const TextStyle(height: 20 / 14),
              child: widget.label!,
            ),
            SizedBox(height: widget.description != null ? 2 : 12),
          ],
          if (widget.description != null) ...[
            DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: DiscourseTypography.sm,
                height: 1.5,
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
      isRequired: widget.required ? true : null,
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
    required this.readOnly,
    required this.required,
    required this.items,
    required super.child,
  });
  final bool enabled;
  final bool invalid;
  final String? errorText;
  final bool readOnly;
  final bool required;
  final Map<Object, ({T value, bool readOnly})> items;
  @override
  bool updateShouldNotify(_RadioScope<T> oldWidget) =>
      enabled != oldWidget.enabled ||
      invalid != oldWidget.invalid ||
      errorText != oldWidget.errorText ||
      readOnly != oldWidget.readOnly ||
      required != oldWidget.required ||
      items != oldWidget.items;
}

/// One radio, optionally with an associated label and description.
///
/// The entire label row activates the radio and has one focus/semantics owner.
/// Keep independent links outside [label] and [description]. A bare item needs
/// [semanticLabel]. Borrowed [focusNode] is never disposed by this widget.
/// Touch platforms keep transparent 48px bounds around the 16px visual; a
/// pointer layout keeps the reference's compact bounds, so a bare item's hit
/// area is its 16px circle and an associated label or Field row supplies the
/// larger target. Like the reference `<span role="radio">`, the pointer cursor
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
    this.invalid = false,
    this.focusNode,
    this.autofocus = false,
    this.card = false,
    this.toggleable = false,
    this.readOnly,
    this.required,
    this.contentGap,
    this.labelStyle,
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

  /// Overrides the label typography or indicator-to-content gap for composition.
  final TextStyle? labelStyle;
  final double? contentGap;

  @override
  State<DRadioGroupItem<T>> createState() => _DRadioGroupItemState<T>();
}

class _DRadioGroupItemState<T> extends State<DRadioGroupItem<T>> {
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
              ).merge(widget.labelStyle),
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
      final gap =
          widget.contentGap ??
          (widget.description != null || widget.card ? 8.0 : 12.0);
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
      content = Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radius),
          border: Border.all(
            color: focused
                ? tokens.focusRing
                : checked
                ? tokens.primary.withValues(
                    alpha: tokens.primary.a * (dark ? 0.2 : 0.3),
                  )
                : tokens.border,
          ),
          color: enabled && _hovered
              ? tokens.muted.withValues(alpha: tokens.muted.a * 0.5)
              : checked
              ? tokens.primary.withValues(
                  alpha: tokens.primary.a * (dark ? 0.1 : 0.05),
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
        isRequired: (widget.required ?? scope?.required ?? false) ? true : null,
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
            autofocus: widget.autofocus,
            builder: (context, state) => Opacity(
              opacity: enabled ? 1 : 0.5,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: touch ? 48 : 16,
                  minHeight: touch ? 48 : 16,
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
