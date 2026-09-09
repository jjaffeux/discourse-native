import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_calendar.dart';
import 'd_field.dart';
import 'd_input.dart';
import 'd_input_group.dart';
import 'd_popover.dart';

final _dateFormattingInitialization = initializeDateFormatting();

enum DDatePickerCloseBehavior { never, onSelection }

@immutable
class DDatePickerLabels {
  const DDatePickerLabels({
    this.placeholder = 'Pick a date',
    this.calendar = 'Select date',
  });

  final String placeholder;
  final String calendar;
}

/// A typed shadcn Date Picker composition built from Button, Popover and the
/// kalender-backed Calendar.
///
/// The unnamed constructor owns its value from [initialValue]. Use
/// [DDatePicker.controlled] when the parent owns [value]. Calendar and Popover
/// keep their own public controllers; a borrowed trigger [focusNode] is never
/// disposed. The selected value is a civil [DCalendarDate], not an instant.
class DDatePicker extends StatefulWidget {
  const DDatePicker({
    super.key,
    this.initialValue,
    this.onChanged,
    this.label,
    this.description,
    this.errorText,
    this.required = false,
    this.labels = const DDatePickerLabels(),
    this.enabled = true,
    this.width = 212,
    this.showChevron = true,
    this.closeBehavior = DDatePickerCloseBehavior.never,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.popoverController,
    this.calendarController,
    this.focusNode,
    this.locale,
    this.calendarLabels = const DCalendarLabels(),
    this.captionLayout = DCalendarCaptionLayout.label,
    this.initialDisplayedMonth,
    this.startMonth,
    this.endMonth,
    this.disabled,
    this.today,
    this.semanticLabel,
    this.dateCodec = const DIntlDateTextCodec(),
  }) : _controlled = false,
       value = null;

  const DDatePicker.controlled({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.errorText,
    this.required = false,
    this.labels = const DDatePickerLabels(),
    this.enabled = true,
    this.width = 212,
    this.showChevron = true,
    this.closeBehavior = DDatePickerCloseBehavior.never,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.popoverController,
    this.calendarController,
    this.focusNode,
    this.locale,
    this.calendarLabels = const DCalendarLabels(),
    this.captionLayout = DCalendarCaptionLayout.label,
    this.initialDisplayedMonth,
    this.startMonth,
    this.endMonth,
    this.disabled,
    this.today,
    this.semanticLabel,
    this.dateCodec = const DIntlDateTextCodec(),
  }) : _controlled = true,
       initialValue = null;

  final DCalendarDate? value;
  final DCalendarDate? initialValue;
  final ValueChanged<DCalendarDate?>? onChanged;
  final String? label;
  final String? description;
  final String? errorText;
  final bool required;
  final DDatePickerLabels labels;
  final bool enabled;
  final double width;
  final bool showChevron;
  final DDatePickerCloseBehavior closeBehavior;
  final bool? open;
  final bool defaultOpen;
  final DPopoverOpenChange? onOpenChange;
  final DPopoverController? popoverController;
  final DCalendarController? calendarController;
  final FocusNode? focusNode;
  final Locale? locale;
  final DCalendarLabels calendarLabels;
  final DCalendarCaptionLayout captionLayout;
  final DCalendarDate? initialDisplayedMonth;
  final DCalendarDate? startMonth;
  final DCalendarDate? endMonth;
  final DCalendarPredicate? disabled;
  final DCalendarDate? today;
  final String? semanticLabel;
  final DDateTextCodec dateCodec;
  final bool _controlled;

  @override
  State<DDatePicker> createState() => _DDatePickerState();
}

class _DDatePickerState extends State<DDatePicker> {
  late DCalendarDate? _value = widget.initialValue;
  late final DPopoverController _ownedPopover = DPopoverController();
  late final FocusNode _ownedFocus = FocusNode(
    debugLabel: 'DDatePicker trigger',
  );

  DCalendarDate? get _effectiveValue =>
      widget._controlled ? widget.value : _value;
  DPopoverController get _popover => widget.popoverController ?? _ownedPopover;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;

  void _select(DCalendarSelection selection, DCalendarSelectReason reason) {
    final date = (selection as DCalendarSingleSelection).date;
    if (!widget._controlled) setState(() => _value = date);
    widget.onChanged?.call(date);
    if (widget.closeBehavior == DDatePickerCloseBehavior.onSelection &&
        date != null) {
      _popover.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = _effectiveValue;
    final locale = widget.locale ?? Localizations.localeOf(context);
    final calendarGeometry = _calendarGeometry(context);
    final picker = DPopover(
      controller: _popover,
      open: widget.enabled ? widget.open : false,
      defaultOpen: widget.enabled && widget.defaultOpen,
      onOpenChange: widget.onOpenChange,
      content: DPopoverContent(
        width: calendarGeometry.popoverWidth,
        padding: EdgeInsets.zero,
        align: DPopoverAlign.start,
        semanticLabel: widget.calendarLabels.calendar,
        child: _calendarViewport(
          calendarGeometry,
          DCalendar(
            mode: DCalendarSelectionMode.single,
            selection: DCalendarSingleSelection(date),
            onSelectionChanged: _select,
            controller: widget.calendarController,
            locale: locale,
            labels: widget.calendarLabels,
            captionLayout: widget.captionLayout,
            initialDisplayedMonth: widget.initialDisplayedMonth ?? date,
            startMonth: widget.startMonth,
            endMonth: widget.endMonth,
            disabled: widget.disabled,
            today: widget.today,
          ),
        ),
      ),
      child: DPopoverTrigger(
        focusNode: _focus,
        builder: (context, trigger) => SizedBox(
          width: widget.width,
          child: DButton(
            label: Row(
              children: [
                Expanded(
                  child: date == null
                      ? Text(
                          widget.labels.placeholder,
                          style: TextStyle(
                            color: DTokens.of(context).mutedForeground,
                          ),
                        )
                      : Text(widget.dateCodec.format(date.dateTimeUtc, locale)),
                ),
                if (widget.showChevron) ...[
                  const SizedBox(width: 8),
                  const ExcludeSemantics(
                    child: DIcon(DIcons.chevronDown, size: 16),
                  ),
                ],
              ],
            ),
            variant: DButtonVariant.outline,
            invalid: widget.errorText != null,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
            semanticLabel: widget.semanticLabel ?? widget.label,
            expanded: trigger.open,
            hasPopup: true,
            focusNode: trigger.focusNode,
            onPressed: widget.enabled ? trigger.toggle : null,
          ),
        ),
      ),
    );
    if (widget.label == null) return picker;
    return SizedBox(
      width: widget.width,
      child: DField(
        enabled: widget.enabled,
        invalid: widget.errorText != null,
        children: [
          DFieldLabel(
            focusNode: _focus,
            excludeSemantics: true,
            child: Text(widget.label!),
          ),
          DFieldControl(
            label: widget.label!,
            description: widget.description,
            errors: [widget.errorText],
            required: widget.required,
            child: picker,
          ),
          if (widget.description != null)
            DFieldDescription(child: Text(widget.description!)),
          if (widget.errorText != null) DFieldError(errors: [widget.errorText]),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ownedPopover.dispose();
    _ownedFocus.dispose();
    super.dispose();
  }
}

/// Flutter Form integration for a typed civil date.
///
/// Reset restores [initialValue], clears normal Form interaction/error state,
/// and notifies [onChanged]. The controlled factory keeps the externally
/// accepted value authoritative during synchronous validation and save calls.
class DDatePickerFormField extends FormField<DCalendarDate?> {
  factory DDatePickerFormField.controlled({
    Key? key,
    required DCalendarDate? value,
    required ValueChanged<DCalendarDate?>? onChanged,
    DCalendarDate? initialValue,
    String? label,
    String? description,
    bool isRequired = false,
    DDatePickerLabels labels = const DDatePickerLabels(),
    bool enabled = true,
    double width = 212,
    bool showChevron = true,
    DDatePickerCloseBehavior closeBehavior = DDatePickerCloseBehavior.never,
    DPopoverController? popoverController,
    DCalendarController? calendarController,
    FocusNode? focusNode,
    Locale? locale,
    DCalendarLabels calendarLabels = const DCalendarLabels(),
    DCalendarCaptionLayout captionLayout = DCalendarCaptionLayout.label,
    DCalendarDate? initialDisplayedMonth,
    DCalendarDate? startMonth,
    DCalendarDate? endMonth,
    DCalendarPredicate? disabled,
    DCalendarDate? today,
    String? semanticLabel,
    DDateTextCodec dateCodec = const DIntlDateTextCodec(),
    FormFieldSetter<DCalendarDate?>? onSaved,
    FormFieldValidator<DCalendarDate?>? validator,
    AutovalidateMode autovalidateMode = AutovalidateMode.disabled,
  }) => _ControlledDatePickerFormField(
    key: key,
    value: value,
    resetValue: initialValue,
    onChanged: onChanged,
    label: label,
    description: description,
    isRequired: isRequired,
    labels: labels,
    enabled: enabled,
    width: width,
    showChevron: showChevron,
    closeBehavior: closeBehavior,
    popoverController: popoverController,
    calendarController: calendarController,
    focusNode: focusNode,
    locale: locale,
    calendarLabels: calendarLabels,
    captionLayout: captionLayout,
    initialDisplayedMonth: initialDisplayedMonth,
    startMonth: startMonth,
    endMonth: endMonth,
    disabled: disabled,
    today: today,
    semanticLabel: semanticLabel,
    dateCodec: dateCodec,
    onSaved: onSaved,
    validator: validator,
    autovalidateMode: autovalidateMode,
  );

  DDatePickerFormField({
    Key? key,
    DCalendarDate? initialValue,
    ValueChanged<DCalendarDate?>? onChanged,
    String? label,
    String? description,
    bool isRequired = false,
    DDatePickerLabels labels = const DDatePickerLabels(),
    bool enabled = true,
    double width = 212,
    bool showChevron = true,
    DDatePickerCloseBehavior closeBehavior = DDatePickerCloseBehavior.never,
    DPopoverController? popoverController,
    DCalendarController? calendarController,
    FocusNode? focusNode,
    Locale? locale,
    DCalendarLabels calendarLabels = const DCalendarLabels(),
    DCalendarCaptionLayout captionLayout = DCalendarCaptionLayout.label,
    DCalendarDate? initialDisplayedMonth,
    DCalendarDate? startMonth,
    DCalendarDate? endMonth,
    DCalendarPredicate? disabled,
    DCalendarDate? today,
    String? semanticLabel,
    DDateTextCodec dateCodec = const DIntlDateTextCodec(),
    FormFieldSetter<DCalendarDate?>? onSaved,
    FormFieldValidator<DCalendarDate?>? validator,
    AutovalidateMode autovalidateMode = AutovalidateMode.disabled,
  }) : this._(
         key: key,
         initialValue: initialValue,
         resetValue: initialValue,
         onChanged: onChanged,
         label: label,
         description: description,
         isRequired: isRequired,
         labels: labels,
         enabled: enabled,
         width: width,
         showChevron: showChevron,
         closeBehavior: closeBehavior,
         popoverController: popoverController,
         calendarController: calendarController,
         focusNode: focusNode,
         locale: locale,
         calendarLabels: calendarLabels,
         captionLayout: captionLayout,
         initialDisplayedMonth: initialDisplayedMonth,
         startMonth: startMonth,
         endMonth: endMonth,
         disabled: disabled,
         today: today,
         semanticLabel: semanticLabel,
         dateCodec: dateCodec,
         onSaved: onSaved,
         validator: validator,
         autovalidateMode: autovalidateMode,
       );

  DDatePickerFormField._({
    required DCalendarDate? resetValue,
    required ValueChanged<DCalendarDate?>? onChanged,
    required String? label,
    required String? description,
    required bool isRequired,
    required DDatePickerLabels labels,
    required super.enabled,
    required double width,
    required bool showChevron,
    required DDatePickerCloseBehavior closeBehavior,
    required DPopoverController? popoverController,
    required DCalendarController? calendarController,
    required FocusNode? focusNode,
    required Locale? locale,
    required DCalendarLabels calendarLabels,
    required DCalendarCaptionLayout captionLayout,
    required DCalendarDate? initialDisplayedMonth,
    required DCalendarDate? startMonth,
    required DCalendarDate? endMonth,
    required DCalendarPredicate? disabled,
    required DCalendarDate? today,
    required String? semanticLabel,
    required DDateTextCodec dateCodec,
    super.key,
    super.initialValue,
    super.onSaved,
    super.validator,
    super.autovalidateMode,
  }) : super(
         onReset: () => onChanged?.call(resetValue),
         builder: (field) => DDatePicker.controlled(
           value: field.value,
           onChanged: enabled
               ? (value) {
                   field.didChange(value);
                   onChanged?.call(value);
                 }
               : null,
           label: label,
           description: description,
           errorText: field.errorText,
           required: isRequired,
           labels: labels,
           enabled: enabled,
           width: width,
           showChevron: showChevron,
           closeBehavior: closeBehavior,
           popoverController: popoverController,
           calendarController: calendarController,
           focusNode: focusNode,
           locale: locale,
           calendarLabels: calendarLabels,
           captionLayout: captionLayout,
           initialDisplayedMonth: initialDisplayedMonth,
           startMonth: startMonth,
           endMonth: endMonth,
           disabled: disabled,
           today: today,
           semanticLabel: semanticLabel,
           dateCodec: dateCodec,
         ),
       );
}

class _ControlledDatePickerFormField extends DDatePickerFormField {
  _ControlledDatePickerFormField({
    super.key,
    required this.value,
    required super.resetValue,
    required super.onChanged,
    required super.label,
    required super.description,
    required super.isRequired,
    required super.labels,
    required super.enabled,
    required super.width,
    required super.showChevron,
    required super.closeBehavior,
    required super.popoverController,
    required super.calendarController,
    required super.focusNode,
    required super.locale,
    required super.calendarLabels,
    required super.captionLayout,
    required super.initialDisplayedMonth,
    required super.startMonth,
    required super.endMonth,
    required super.disabled,
    required super.today,
    required super.semanticLabel,
    required super.dateCodec,
    super.onSaved,
    super.validator,
    super.autovalidateMode,
  }) : super._(initialValue: value);

  final DCalendarDate? value;

  @override
  FormFieldState<DCalendarDate?> createState() =>
      _ControlledDatePickerFormFieldState();
}

class _ControlledDatePickerFormFieldState
    extends FormFieldState<DCalendarDate?> {
  @override
  void didChange(DCalendarDate? value) {
    super.didChange((widget as _ControlledDatePickerFormField).value);
  }

  @override
  void didUpdateWidget(covariant _ControlledDatePickerFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget as _ControlledDatePickerFormField;
    if (next.value != value) setValue(next.value);
  }
}

/// Two-month range variant of [DDatePicker]. Incomplete ranges display their
/// start date and remain open so the end can be chosen.
class DDateRangePicker extends StatefulWidget {
  const DDateRangePicker({
    super.key,
    this.initialValue,
    this.onChanged,
    this.label = 'Date Picker Range',
    this.labels = const DDatePickerLabels(),
    this.enabled = true,
    this.width = 240,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.popoverController,
    this.calendarController,
    this.focusNode,
    this.locale,
    this.calendarLabels = const DCalendarLabels(),
    this.initialDisplayedMonth,
    this.startMonth,
    this.endMonth,
    this.disabled,
    this.minRangeDays,
    this.maxRangeDays,
    this.excludeDisabledInRange = false,
    this.today,
    this.semanticLabel,
  }) : _controlled = false,
       value = null;

  const DDateRangePicker.controlled({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Date Picker Range',
    this.labels = const DDatePickerLabels(),
    this.enabled = true,
    this.width = 240,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.popoverController,
    this.calendarController,
    this.focusNode,
    this.locale,
    this.calendarLabels = const DCalendarLabels(),
    this.initialDisplayedMonth,
    this.startMonth,
    this.endMonth,
    this.disabled,
    this.minRangeDays,
    this.maxRangeDays,
    this.excludeDisabledInRange = false,
    this.today,
    this.semanticLabel,
  }) : _controlled = true,
       initialValue = null;

  final DCalendarRange? value;
  final DCalendarRange? initialValue;
  final ValueChanged<DCalendarRange?>? onChanged;
  final String? label;
  final DDatePickerLabels labels;
  final bool enabled;
  final double width;
  final bool? open;
  final bool defaultOpen;
  final DPopoverOpenChange? onOpenChange;
  final DPopoverController? popoverController;
  final DCalendarController? calendarController;
  final FocusNode? focusNode;
  final Locale? locale;
  final DCalendarLabels calendarLabels;
  final DCalendarDate? initialDisplayedMonth;
  final DCalendarDate? startMonth;
  final DCalendarDate? endMonth;
  final DCalendarPredicate? disabled;
  final int? minRangeDays;
  final int? maxRangeDays;
  final bool excludeDisabledInRange;
  final DCalendarDate? today;
  final String? semanticLabel;
  final bool _controlled;

  @override
  State<DDateRangePicker> createState() => _DDateRangePickerState();
}

class _DDateRangePickerState extends State<DDateRangePicker> {
  late DCalendarRange? _value = widget.initialValue;
  late final DPopoverController _ownedPopover = DPopoverController();
  late final FocusNode _ownedFocus = FocusNode(
    debugLabel: 'DDateRangePicker trigger',
  );

  DCalendarRange? get _effectiveValue =>
      widget._controlled ? widget.value : _value;
  DPopoverController get _popover => widget.popoverController ?? _ownedPopover;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;

  void _select(DCalendarSelection selection, DCalendarSelectReason reason) {
    final range = (selection as DCalendarRangeSelection).range;
    if (!widget._controlled) setState(() => _value = range);
    widget.onChanged?.call(range);
  }

  @override
  Widget build(BuildContext context) {
    final range = _effectiveValue;
    final locale = widget.locale ?? Localizations.localeOf(context);
    final calendarGeometry = _calendarGeometry(context, numberOfMonths: 2);
    final picker = DPopover(
      controller: _popover,
      open: widget.enabled ? widget.open : false,
      defaultOpen: widget.enabled && widget.defaultOpen,
      onOpenChange: widget.onOpenChange,
      content: DPopoverContent(
        width: calendarGeometry.popoverWidth,
        padding: EdgeInsets.zero,
        align: DPopoverAlign.start,
        semanticLabel: widget.calendarLabels.calendar,
        child: _calendarViewport(
          calendarGeometry,
          DCalendar(
            mode: DCalendarSelectionMode.range,
            selection: DCalendarRangeSelection(range),
            onSelectionChanged: _select,
            controller: widget.calendarController,
            locale: locale,
            labels: widget.calendarLabels,
            numberOfMonths: 2,
            initialDisplayedMonth: widget.initialDisplayedMonth ?? range?.from,
            startMonth: widget.startMonth,
            endMonth: widget.endMonth,
            disabled: widget.disabled,
            minRangeDays: widget.minRangeDays,
            maxRangeDays: widget.maxRangeDays,
            excludeDisabledInRange: widget.excludeDisabledInRange,
            today: widget.today,
          ),
        ),
      ),
      child: DPopoverTrigger(
        focusNode: _focus,
        builder: (context, trigger) => SizedBox(
          width: widget.width,
          child: DButton(
            label: Text(
              _formatRange(range, locale, widget.labels.placeholder),
              style: range == null
                  ? TextStyle(color: DTokens.of(context).mutedForeground)
                  : null,
            ),
            icon: const DIcon(_calendarIcon, size: 16),
            variant: DButtonVariant.outline,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
            semanticLabel: widget.semanticLabel ?? widget.label,
            expanded: trigger.open,
            hasPopup: true,
            focusNode: trigger.focusNode,
            onPressed: widget.enabled ? trigger.toggle : null,
          ),
        ),
      ),
    );
    if (widget.label == null) return picker;
    return SizedBox(
      width: widget.width,
      child: DField(
        enabled: widget.enabled,
        children: [
          DFieldLabel(
            focusNode: _focus,
            excludeSemantics: true,
            child: Text(widget.label!),
          ),
          DFieldControl(label: widget.label!, child: picker),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ownedPopover.dispose();
    _ownedFocus.dispose();
    super.dispose();
  }
}

/// An editable Date Picker composed from Input Group, Popover and Calendar.
/// Invalid non-empty text stays editable while the last valid date is kept.
class DDatePickerInput extends StatefulWidget {
  const DDatePickerInput({
    super.key,
    this.initialValue,
    this.onChanged,
    this.controller,
    this.focusNode,
    this.popoverController,
    this.calendarController,
    this.label,
    this.description,
    this.errorText,
    this.placeholder = 'June 01, 2025',
    this.labels = const DDatePickerLabels(),
    this.calendarLabels = const DCalendarLabels(),
    this.semanticLabel,
    this.enabled = true,
    this.width = 288,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.locale,
    this.dateCodec = const DIntlDateTextCodec(),
    this.naturalDateParser,
    this.referenceDate,
    this.startMonth,
    this.endMonth,
    this.disabled,
    this.today,
  }) : assert(
         naturalDateParser == null || referenceDate != null,
         'Natural-language parsing requires an explicit referenceDate.',
       ),
       _controlled = false,
       value = null;

  const DDatePickerInput.controlled({
    super.key,
    required this.value,
    required this.onChanged,
    this.controller,
    this.focusNode,
    this.popoverController,
    this.calendarController,
    this.label,
    this.description,
    this.errorText,
    this.placeholder = 'June 01, 2025',
    this.labels = const DDatePickerLabels(),
    this.calendarLabels = const DCalendarLabels(),
    this.semanticLabel,
    this.enabled = true,
    this.width = 288,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.locale,
    this.dateCodec = const DIntlDateTextCodec(),
    this.naturalDateParser,
    this.referenceDate,
    this.startMonth,
    this.endMonth,
    this.disabled,
    this.today,
  }) : assert(
         naturalDateParser == null || referenceDate != null,
         'Natural-language parsing requires an explicit referenceDate.',
       ),
       _controlled = true,
       initialValue = null;

  final DCalendarDate? value, initialValue;
  final ValueChanged<DCalendarDate?>? onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final DPopoverController? popoverController;
  final DCalendarController? calendarController;
  final String? label, description, errorText, semanticLabel;
  final String placeholder;
  final DDatePickerLabels labels;
  final DCalendarLabels calendarLabels;
  final bool enabled;
  final double width;
  final bool? open;
  final bool defaultOpen;
  final DPopoverOpenChange? onOpenChange;
  final Locale? locale;
  final DDateTextCodec dateCodec;
  final DNaturalDateParser? naturalDateParser;
  final DateTime? referenceDate;
  final DCalendarDate? startMonth, endMonth, today;
  final DCalendarPredicate? disabled;
  final bool _controlled;

  @override
  State<DDatePickerInput> createState() => _DDatePickerInputState();
}

class _DDatePickerInputState extends State<DDatePickerInput> {
  TextEditingController? _ownedController;
  FocusNode? _ownedFocus;
  DPopoverController? _ownedPopover;
  DCalendarController? _ownedCalendar;
  DCalendarDate? _value;
  bool _invalidText = false;

  TextEditingController get _text => widget.controller ?? _ownedController!;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus!;
  DPopoverController get _popover => widget.popoverController ?? _ownedPopover!;
  DCalendarController get _calendar =>
      widget.calendarController ?? _ownedCalendar!;
  DCalendarDate? get _effectiveValue =>
      widget._controlled ? widget.value : _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    if (widget.controller == null) _ownedController = TextEditingController();
    if (widget.focusNode == null) {
      _ownedFocus = FocusNode(debugLabel: 'DDatePickerInput editor');
    }
    if (widget.popoverController == null) _ownedPopover = DPopoverController();
    if (widget.calendarController == null) {
      _ownedCalendar = DCalendarController();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_text.text.isEmpty && _effectiveValue != null) {
      _syncText(_effectiveValue!);
    }
  }

  @override
  void didUpdateWidget(DDatePickerInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final previousOwned = _ownedController;
      final previousText =
          oldWidget.controller?.text ?? previousOwned?.text ?? '';
      if (widget.controller == null) {
        _ownedController = TextEditingController(text: previousText);
      } else {
        _ownedController = null;
      }
      if (previousOwned != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => previousOwned.dispose(),
        );
      }
    }
    if (oldWidget.focusNode != widget.focusNode) {
      final previousOwned = _ownedFocus;
      _ownedFocus = widget.focusNode == null
          ? FocusNode(debugLabel: 'DDatePickerInput editor')
          : null;
      if (previousOwned != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => previousOwned.dispose(),
        );
      }
    }
    if (oldWidget.popoverController != widget.popoverController) {
      _ownedPopover?.dispose();
      _ownedPopover = widget.popoverController == null
          ? DPopoverController()
          : null;
    }
    if (oldWidget.calendarController != widget.calendarController) {
      _ownedCalendar?.dispose();
      _ownedCalendar = widget.calendarController == null
          ? DCalendarController()
          : null;
    }
    if (oldWidget.value != widget.value && widget._controlled) {
      final next = widget.value;
      if (next == null) {
        _replaceText('');
      } else {
        _syncText(next);
        _calendar.showMonth(next);
      }
      _invalidText = false;
    }
  }

  void _replaceText(String text) {
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _syncText(DCalendarDate value) {
    final locale = widget.locale ?? Localizations.localeOf(context);
    _replaceText(widget.dateCodec.format(value.dateTimeUtc, locale));
  }

  DCalendarDate? _parse(String raw) {
    final locale = widget.locale ?? Localizations.localeOf(context);
    final parsed =
        widget.naturalDateParser?.tryParse(
          raw,
          reference: widget.referenceDate!,
          locale: locale,
        ) ??
        widget.dateCodec.tryParse(raw, locale);
    return parsed == null ? null : DCalendarDate.fromDateTime(parsed);
  }

  void _typed(String raw) {
    if (_text.value.composing.isValid && !_text.value.composing.isCollapsed) {
      return;
    }
    if (raw.trim().isEmpty) {
      setState(() {
        _invalidText = false;
        if (!widget._controlled) _value = null;
      });
      widget.onChanged?.call(null);
      return;
    }
    final next = _parse(raw);
    final invalid =
        next == null ||
        (widget.startMonth != null && next.isBefore(widget.startMonth!)) ||
        (widget.endMonth != null && next.isAfter(widget.endMonth!)) ||
        (widget.disabled?.call(next) ?? false);
    if (invalid) {
      setState(() => _invalidText = true);
      return;
    }
    setState(() {
      _invalidText = false;
      if (!widget._controlled) _value = next;
    });
    _calendar.showMonth(next);
    widget.onChanged?.call(next);
  }

  void _selected(DCalendarSelection selection, DCalendarSelectReason reason) {
    final next = (selection as DCalendarSingleSelection).date;
    if (next == null) return;
    setState(() {
      _invalidText = false;
      if (!widget._controlled) _value = next;
    });
    _syncText(next);
    widget.onChanged?.call(next);
    _popover.close();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _popover.open(DPopoverInteraction.keyboard);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final value = _effectiveValue;
    final locale = widget.locale ?? Localizations.localeOf(context);
    final geometry = _calendarGeometry(context);
    final invalid = _invalidText || widget.errorText != null;
    final picker = DPopover(
      controller: _popover,
      open: widget.enabled ? widget.open : false,
      defaultOpen: widget.enabled && widget.defaultOpen,
      onOpenChange: widget.onOpenChange,
      content: DPopoverContent(
        width: geometry.popoverWidth,
        padding: EdgeInsets.zero,
        align: DPopoverAlign.end,
        alignOffset: -8,
        sideOffset: 10,
        semanticLabel: widget.calendarLabels.calendar,
        child: _calendarViewport(
          geometry,
          DCalendar(
            mode: DCalendarSelectionMode.single,
            selection: DCalendarSingleSelection(value),
            onSelectionChanged: _selected,
            controller: _calendar,
            locale: locale,
            labels: widget.calendarLabels,
            initialDisplayedMonth: value,
            startMonth: widget.startMonth,
            endMonth: widget.endMonth,
            disabled: widget.disabled,
            today: widget.today,
          ),
        ),
      ),
      child: DPopoverTrigger(
        focusNode: _focus,
        builder: (context, trigger) => Focus(
          onKeyEvent: _key,
          child: DInputGroup(
            invalid: invalid,
            enabled: widget.enabled,
            semanticLabel: widget.semanticLabel ?? widget.label,
            children: [
              DInputGroupInput(
                controller: _text,
                focusNode: _focus,
                semanticLabel: widget.semanticLabel ?? widget.label ?? 'Date',
                hintText: widget.placeholder,
                invalid: invalid,
                enabled: widget.enabled,
                onChanged: _typed,
              ),
              DInputGroupAddon(
                alignment: DInputGroupAddonAlignment.inlineEnd,
                child: Semantics(
                  button: true,
                  enabled: widget.enabled,
                  expanded: trigger.open,
                  label: widget.labels.calendar,
                  onTap: widget.enabled ? trigger.toggle : null,
                  child: ExcludeSemantics(
                    child: DInputGroupButton.icon(
                      icon: const DIcon(_calendarIcon, size: 16),
                      tooltip: widget.labels.calendar,
                      onPressed: widget.enabled ? trigger.toggle : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (widget.label == null) {
      return SizedBox(width: widget.width, child: picker);
    }
    final errors = <String?>[
      widget.errorText,
      if (_invalidText) 'Enter a valid date',
    ];
    return SizedBox(
      width: widget.width,
      child: DField(
        enabled: widget.enabled,
        invalid: invalid,
        children: [
          DFieldLabel(focusNode: _focus, child: Text(widget.label!)),
          DFieldControl(
            label: widget.label!,
            description: widget.description,
            errors: errors,
            child: picker,
          ),
          if (widget.description != null)
            DFieldDescription(child: Text(widget.description!)),
          if (invalid) DFieldError(errors: errors),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    _ownedFocus?.dispose();
    _ownedPopover?.dispose();
    _ownedCalendar?.dispose();
    super.dispose();
  }
}

/// Strict wall-clock editor for a Date Picker date/time composition.
class DTimeInput extends StatefulWidget {
  const DTimeInput({
    super.key,
    this.initialValue,
    this.onChanged,
    this.label,
    this.enabled = true,
    this.includeSeconds = true,
    this.width = 112,
  });
  final DTimeValue? initialValue;
  final ValueChanged<DTimeValue?>? onChanged;
  final String? label;
  final bool enabled, includeSeconds;
  final double width;
  @override
  State<DTimeInput> createState() => _DTimeInputState();
}

class _DTimeInputState extends State<DTimeInput> {
  late final TextEditingController _controller = TextEditingController(
    text:
        widget.initialValue?.format(includeSeconds: widget.includeSeconds) ??
        '',
  );
  bool _invalid = false;
  void _changed(String text) {
    final value = text.trim().isEmpty ? null : DTimeValue.tryParse(text);
    setState(() => _invalid = text.trim().isNotEmpty && value == null);
    if (!_invalid) widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    child: DInput(
      controller: _controller,
      labelText: widget.label,
      semanticLabel: widget.label ?? 'Time',
      hintText: widget.includeSeconds ? 'HH:mm:ss' : 'HH:mm',
      keyboardType: TextInputType.datetime,
      invalid: _invalid,
      errorText: _invalid ? 'Enter a valid time' : null,
      enabled: widget.enabled,
      onChanged: _changed,
    ),
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

({double popoverWidth, double calendarWidth}) _calendarGeometry(
  BuildContext context, {
  int numberOfMonths = 1,
}) {
  final platform = Theme.of(context).platform;
  final touch =
      platform == TargetPlatform.iOS || platform == TargetPlatform.android;
  final scaledText = MediaQuery.textScalerOf(context).scale(14);
  final cell = [
    28.0,
    scaledText + 12,
    if (touch) DSpacing.touchTarget,
  ].reduce(math.max);
  final monthWidth = 16 + 7 * cell;
  final horizontalWidth =
      16 + numberOfMonths * 7 * cell + (numberOfMonths - 1) * 16;
  final available = math.max(1.0, MediaQuery.sizeOf(context).width - 10);
  final calendarWidth = horizontalWidth <= available
      ? horizontalWidth
      : monthWidth;
  return (
    popoverWidth: math.min(calendarWidth, available),
    calendarWidth: calendarWidth,
  );
}

Widget _calendarViewport(
  ({double popoverWidth, double calendarWidth}) geometry,
  Widget calendar,
) {
  final sized = SizedBox(width: geometry.calendarWidth, child: calendar);
  if (geometry.calendarWidth <= geometry.popoverWidth) return sized;
  return SingleChildScrollView(scrollDirection: Axis.horizontal, child: sized);
}

String _formatRange(DCalendarRange? range, Locale locale, String placeholder) {
  if (range == null) return placeholder;
  final format = DateFormat('MMM dd, y', _localeName(locale));
  final from = format.format(range.from.dateTimeUtc);
  final to = range.to;
  return to == null ? from : '$from - ${format.format(to.dateTimeUtc)}';
}

const _calendarIcon = DIconData(
  'lucide-calendar',
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 2v4M16 2v4M3 10h18"/><rect width="18" height="18" x="3" y="4" rx="2"/></svg>',
);

/// Converts between a displayed date string and a date-only [DateTime].
///
/// Implementations must return a local civil date with its time fields cleared.
/// A date-only value is not an instant and must not be converted with
/// [DateTime.toUtc]. Application adapters remain responsible for resolving a
/// chosen day and time in the site's timezone, including daylight-saving gaps.
abstract interface class DDateTextCodec {
  const DDateTextCodec();

  String format(DateTime date, Locale locale);

  DateTime? tryParse(String text, Locale locale);
}

/// Locale-aware strict date formatting for editable date-picker fields.
///
/// The default display matches the documented shadcn input example
/// (`June 01, 2025`). Parsing also accepts the locale's short date form and an
/// unambiguous ISO civil date. Impossible dates such as February 29, 2025 are
/// rejected instead of being normalized into March.
class DIntlDateTextCodec implements DDateTextCodec {
  const DIntlDateTextCodec({
    this.formatPattern = 'MMMM dd, y',
    this.additionalParsePatterns = const <String>[],
    this.useLocaleDateOrder = true,
  });

  final String formatPattern;
  final List<String> additionalParsePatterns;
  final bool useLocaleDateOrder;

  @override
  String format(DateTime date, Locale locale) {
    _ensureDateFormattingInitialized();
    final localeName = _localeName(locale);
    final format = useLocaleDateOrder && locale.languageCode != 'en'
        ? DateFormat.yMMMMd(localeName)
        : DateFormat(formatPattern, localeName);
    return format.format(_dateOnly(date));
  }

  @override
  DateTime? tryParse(String text, Locale locale) {
    _ensureDateFormattingInitialized();
    final value = text.trim();
    if (value.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$').hasMatch(value)) {
      return _tryParseIsoCivil(value);
    }
    final localeName = _localeName(locale);
    final formats = <DateFormat>[
      DateFormat(formatPattern, localeName),
      DateFormat.yMd(localeName),
      DateFormat('MMM dd, y', localeName),
      for (final pattern in additionalParsePatterns)
        DateFormat(pattern, localeName),
    ];
    for (final format in formats) {
      try {
        return _dateOnly(format.parseStrict(value));
      } on FormatException {
        // Try the next explicitly supported representation.
      }
    }
    return null;
  }
}

DateTime? _tryParseIsoCivil(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (year < 1 || month < 1 || month > 12 || day < 1) return null;
  final parsed = DateTime(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day
      ? parsed
      : null;
}

/// Parses natural-language input relative to an explicit clock value.
///
/// Requiring [reference] makes examples and tests deterministic. Results are
/// civil dates; parsers do not invent a timezone or preserve a wall-clock time.
abstract interface class DNaturalDateParser {
  const DNaturalDateParser();

  DateTime? tryParse(
    String text, {
    required DateTime reference,
    required Locale locale,
  });
}

/// A deterministic English natural-date adapter with strict explicit-date
/// fallback.
///
/// Supported phrases are `today`, `tomorrow`, `yesterday`, `next week`,
/// `next month`, `next year`, `in N days/weeks/months/years`, and
/// `this|next <weekday>`. Applications needing a richer vocabulary or another
/// language can supply their own [DNaturalDateParser] without changing picker
/// state or presentation.
class DEnglishNaturalDateParser implements DNaturalDateParser {
  const DEnglishNaturalDateParser({
    this.explicitDateCodec = const DIntlDateTextCodec(),
  });

  final DDateTextCodec explicitDateCodec;

  @override
  DateTime? tryParse(
    String text, {
    required DateTime reference,
    required Locale locale,
  }) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    final explicit = explicitDateCodec.tryParse(raw, locale);
    if (explicit != null) return explicit;
    if (locale.languageCode.toLowerCase() != 'en') return null;

    final input = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[,!.]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final today = _dateOnly(reference);
    switch (input) {
      case 'today':
        return today;
      case 'tomorrow':
        return _addDays(today, 1);
      case 'day after tomorrow':
        return _addDays(today, 2);
      case 'yesterday':
        return _addDays(today, -1);
      case 'next week':
        return _addDays(today, 7);
      case 'next month':
        return _addMonths(today, 1);
      case 'next year':
        return _addYears(today, 1);
    }

    final relative = RegExp(
      r'^in\s+(\d+)\s+(day|days|week|weeks|month|months|year|years)$',
    ).firstMatch(input);
    if (relative != null) {
      final amount = int.parse(relative.group(1)!);
      if (amount > 10000) return null;
      final result = switch (relative.group(2)!) {
        'day' || 'days' => _addDays(today, amount),
        'week' || 'weeks' => _addDays(today, amount * 7),
        'month' || 'months' => _addMonths(today, amount),
        'year' || 'years' => _addYears(today, amount),
        _ => null,
      };
      return result != null && result.year <= 9999 ? result : null;
    }

    final weekday = RegExp(
      r'^(this|next)\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)$',
    ).firstMatch(input);
    if (weekday != null) {
      final target = _weekdays[weekday.group(2)!]!;
      var days = (target - today.weekday) % 7;
      if (weekday.group(1) == 'next' && days == 0) days = 7;
      return _addDays(today, days);
    }
    return null;
  }
}

/// A validated wall-clock time used by Date Picker's time composition.
///
/// It intentionally contains no date or timezone. Resolve it in an application
/// timezone adapter so nonexistent and ambiguous daylight-saving times can be
/// handled using domain policy rather than silently normalized by [DateTime].
@immutable
class DTimeValue {
  const DTimeValue({required this.hour, required this.minute, this.second = 0})
    : assert(hour >= 0 && hour <= 23),
      assert(minute >= 0 && minute <= 59),
      assert(second >= 0 && second <= 59);

  factory DTimeValue.fromTimeOfDay(TimeOfDay value, {int second = 0}) =>
      DTimeValue(hour: value.hour, minute: value.minute, second: second);

  static DTimeValue? tryParse(String text) {
    final match = RegExp(
      r'^(?:([01]\d|2[0-3])):([0-5]\d)(?::([0-5]\d))?$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    return DTimeValue(
      hour: int.parse(match.group(1)!),
      minute: int.parse(match.group(2)!),
      second: int.tryParse(match.group(3) ?? '') ?? 0,
    );
  }

  final int hour;
  final int minute;
  final int second;

  TimeOfDay get timeOfDay => TimeOfDay(hour: hour, minute: minute);

  String format({bool includeSeconds = true}) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(hour)}:${two(minute)}'
        '${includeSeconds ? ':${two(second)}' : ''}';
  }

  @override
  bool operator ==(Object other) =>
      other is DTimeValue &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(hour, minute, second);
}

String _localeName(Locale locale) =>
    locale.toLanguageTag().replaceAll('-', '_');

void _ensureDateFormattingInitialized() {
  // initializeDateFormatting installs the bundled symbol tables synchronously;
  // its Future only preserves the cross-platform loader contract.
  unawaited(_dateFormattingInitialization);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

DateTime _addMonths(DateTime date, int months) {
  final zeroBased = date.month - 1 + months;
  final year = date.year + zeroBased ~/ 12;
  final month = zeroBased % 12 + 1;
  final day = date.day.clamp(1, _daysInMonth(year, month));
  return DateTime(year, month, day);
}

DateTime _addYears(DateTime date, int years) {
  final year = date.year + years;
  final day = date.day.clamp(1, _daysInMonth(year, date.month));
  return DateTime(year, date.month, day);
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

const _weekdays = <String, int>{
  'monday': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'friday': DateTime.friday,
  'saturday': DateTime.saturday,
  'sunday': DateTime.sunday,
};
