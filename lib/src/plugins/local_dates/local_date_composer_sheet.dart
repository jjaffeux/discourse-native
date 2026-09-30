import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../composer_sheet_layout.dart';
import 'local_date.dart';
import 'local_date_composer_editor.dart';
import 'local_date_environment.dart';

enum LocalDateComposerSheetActionType { apply, remove }

@immutable
class LocalDateComposerSheetAction {
  const LocalDateComposerSheetAction._(this.type, this.draft);

  const LocalDateComposerSheetAction.apply(LocalDateComposerDraft draft)
    : this._(LocalDateComposerSheetActionType.apply, draft);

  const LocalDateComposerSheetAction.remove()
    : this._(LocalDateComposerSheetActionType.remove, null);

  final LocalDateComposerSheetActionType type;
  final LocalDateComposerDraft? draft;
}

Future<LocalDateComposerSheetAction?> showLocalDateComposerSheet({
  required BuildContext context,
  required LocalDateComposerDraft draft,
  required List<String> siteFormats,
  bool Function()? isCurrent,
}) {
  final title = draft.isNew
      ? appL10n.insertDateAndTime
      : appL10n.editDateAndTime;
  Widget editor(BuildContext context) => LocalDateComposerSheet(
    mobileLayout: context.isTouch,
    draft: draft,
    siteFormats: siteFormats,
    isCurrent: isCurrent,
  );
  if (context.isTouch) {
    return showDSheet<LocalDateComposerSheetAction>(
      context: context,
      side: DSheetSide.bottom,
      inset: true,
      fillAvailableHeight: true,
      builder: (context, sheet) => DSheetContent(
        side: DSheetSide.bottom,
        semanticLabel: title,
        showCloseButton: false,
        topBottomMaxHeightFactor: 1,
        scrollWholeSheet: false,
        children: [Expanded(child: editor(context))],
      ),
    );
  }
  return showDialog<LocalDateComposerSheetAction>(
    context: context,
    builder: (dialogContext) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DText(title, variant: DTextVariant.h4, headingLevel: 1),
                        const SizedBox(height: 4),
                        Text(
                          appL10n.chooseTheDateThenCheckHowItWillAppear,
                          style: Theme.of(dialogContext).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  DButton.iconOnly(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    variant: DButtonVariant.ghost,
                    tooltip: appL10n.close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            DSeparator(color: Theme.of(dialogContext).shell.divider, space: 1),
            Flexible(
              child: SingleChildScrollView(child: editor(dialogContext)),
            ),
          ],
        ),
      ),
    ),
  );
}

class LocalDateComposerSheet extends StatefulWidget {
  const LocalDateComposerSheet({
    super.key,
    required this.draft,
    required this.siteFormats,
    this.isCurrent,
    this.mobileLayout = false,
  });

  final LocalDateComposerDraft draft;
  final List<String> siteFormats;
  final bool Function()? isCurrent;
  final bool mobileLayout;

  @override
  State<LocalDateComposerSheet> createState() => _LocalDateComposerSheetState();
}

enum _CalendarMode { automatic, on, off }

class _LocalDateComposerSheetState extends State<LocalDateComposerSheet> {
  late final TextEditingController _startDate;
  late final TextEditingController _startTime;
  late final TextEditingController _endDate;
  late final TextEditingController _endTime;
  late final TextEditingController _recurring;
  late final TextEditingController _format;
  late String _timezone;
  String? _displayedTimezone;
  late bool _hasStartTime;
  late bool _hasEnd;
  late bool _hasEndTime;
  late bool _countdown;
  late _CalendarMode _calendar;
  late List<String> _previewTimezones;
  String? _previewCandidate;
  String? _error;

  late final List<String> _zones;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _zones = {
      ...LocalDateEnvironment.aliases.keys,
      ...draft.environment.timezoneNames,
    }.toList()..sort();
    _startDate = TextEditingController(text: draft.startDate);
    _startTime = TextEditingController(text: draft.startTime ?? '09:00:00');
    _endDate = TextEditingController(text: draft.endDate ?? draft.startDate);
    _endTime = TextEditingController(text: draft.endTime ?? '10:00:00');
    _recurring = TextEditingController(text: draft.recurring ?? '');
    _format = TextEditingController(text: draft.format ?? '');
    for (final controller in [
      _startDate,
      _startTime,
      _endDate,
      _endTime,
      _recurring,
      _format,
    ]) {
      controller.addListener(_changed);
    }
    _timezone = draft.timezone;
    _displayedTimezone = draft.displayedTimezone;
    _hasStartTime = draft.startTime != null;
    _hasEnd = draft.endDate != null;
    _hasEndTime = draft.endTime != null;
    _countdown = draft.countdown;
    _calendar = switch (draft.calendar) {
      true => _CalendarMode.on,
      false => _CalendarMode.off,
      null => _CalendarMode.automatic,
    };
    _previewTimezones = List.of(draft.previewTimezones);
  }

  @override
  void dispose() {
    for (final controller in [
      _startDate,
      _startTime,
      _endDate,
      _endTime,
      _recurring,
      _format,
    ]) {
      controller
        ..removeListener(_changed)
        ..dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error == null
        ? null
        : Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              _error!,
              key: const ValueKey('local-date-sheet-error'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          );
    final fields = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.mobileLayout ? DSpacing.lg : DSpacing.xl,
        vertical: widget.mobileLayout ? DSpacing.sm : DSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DCard(
            size: DCardSize.small,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DCardTitle(child: Text(context.l10n.when)),
                  const SizedBox(height: 12),
                  _dateTimeRow(
                    date: _startDate,
                    time: _startTime,
                    label: context.l10n.start,
                    hasTime: _hasStartTime,
                    onTimeEnabled: (value) =>
                        setState(() => _hasStartTime = value),
                  ),
                  const SizedBox(height: 12),
                  DSeparator(color: theme.shell.divider, space: 1),
                  DSwitchTile(
                    contentPadding: EdgeInsets.zero,
                    title: DLabel(child: Text(context.l10n.addEndDateAndTime)),
                    value: _hasEnd,
                    onChanged: (value) => setState(() {
                      _hasEnd = value;
                      if (!value) _hasEndTime = false;
                    }),
                  ),
                  if (_hasEnd) ...[
                    const SizedBox(height: 8),
                    _dateTimeRow(
                      date: _endDate,
                      time: _endTime,
                      label: context.l10n.end,
                      hasTime: _hasEndTime,
                      onTimeEnabled: (value) =>
                          setState(() => _hasEndTime = value),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          DCard(
            size: DCardSize.small,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DCardTitle(child: Text(context.l10n.timezone)),
                  const SizedBox(height: 12),
                  _TimezoneMenu(
                    key: const ValueKey('local-date-source-timezone'),
                    label: context.l10n.sourceTimezone,
                    zones: _zones,
                    initial: _timezone,
                    onSelected: (zone) {
                      if (zone != null) setState(() => _timezone = zone);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.thisIsTheTimezoneInWhichTheDateAndTimeWere,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _preview(),
          const SizedBox(height: 12),
          DCollapsible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DCollapsibleTrigger(
                  builder: (context, state) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(child: Text(context.l10n.displayOptions)),
                        Icon(
                          state.open ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
                DCollapsibleContent(
                  keepMounted: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_hasEnd) ...[
                        DInput(
                          controller: _recurring,
                          labelText: context.l10n.recurrenceOptional,
                          hintText: context.l10n.recurrenceExample,
                        ),
                        const SizedBox(height: 8),
                        DSwitchTile(
                          contentPadding: EdgeInsets.zero,
                          title: DLabel(child: Text(context.l10n.countdown)),
                          value: _countdown,
                          onChanged: (value) =>
                              setState(() => _countdown = value),
                        ),
                      ],
                      _TimezoneMenu(
                        key: const ValueKey('local-date-displayed-timezone'),
                        label: context.l10n.displayedTimezoneOptional,
                        zones: _zones,
                        initial: _displayedTimezone,
                        optional: true,
                        onSelected: (zone) =>
                            setState(() => _displayedTimezone = zone),
                      ),
                      const SizedBox(height: 12),
                      DSelect<_CalendarMode>.controlled(
                        isExpanded: true,
                        value: _calendar,
                        label: Text(context.l10n.relativeDay),
                        entries: [
                          DSelectOption(
                            value: _CalendarMode.automatic,
                            label: context.l10n.automatic,
                            child: Text(context.l10n.automatic),
                          ),
                          DSelectOption(
                            value: _CalendarMode.on,
                            label: context.l10n.alwaysOn,
                            child: Text(context.l10n.alwaysOn),
                          ),
                          DSelectOption(
                            value: _CalendarMode.off,
                            label: context.l10n.off,
                            child: Text(context.l10n.off),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _calendar = value ?? _CalendarMode.automatic,
                        ),
                        initialValue: _calendar,
                      ),
                      const SizedBox(height: 12),
                      DInput(
                        controller: _format,
                        labelText: context.l10n.momentFormatOptional,
                        hintText:
                            widget.siteFormats.firstOrNull ??
                            context.l10n.dateFormatExample,
                        helperText: widget.siteFormats.isEmpty
                            ? context.l10n.forExampleLLLOrYYYYMMDDAtHHMm
                            : context.l10n.siteFormats(
                                (widget.siteFormats.join(', ')).toString(),
                              ),
                      ),
                      if (widget.siteFormats.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final format in widget.siteFormats)
                              ActionChip(
                                label: Text(format),
                                onPressed: () => _format.text = format,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.previewTimezones,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final zone in _previewTimezones)
                            InputChip(
                              label: Text(LocalDateFormatter.zoneLabel(zone)),
                              onDeleted: () => setState(
                                () => _previewTimezones.remove(zone),
                              ),
                            ),
                        ],
                      ),
                      if (_previewTimezones.length < 5) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _TimezoneMenu(
                                key: ValueKey(
                                  'local-date-preview-${_previewTimezones.length}',
                                ),
                                label: context.l10n.addPreviewTimezone,
                                zones: _zones
                                    .where(
                                      (zone) =>
                                          !_previewTimezones.contains(zone),
                                    )
                                    .toList(),
                                initial: null,
                                optional: true,
                                onSelected: (zone) =>
                                    setState(() => _previewCandidate = zone),
                              ),
                            ),
                            const SizedBox(width: DSpacing.controlGap),
                            DButton.iconOnly(
                              onPressed: _previewCandidate == null
                                  ? null
                                  : () => setState(() {
                                      _previewTimezones.add(_previewCandidate!);
                                      _previewCandidate = null;
                                    }),
                              variant: DButtonVariant.secondary,
                              tooltip: context.l10n.addTimezone,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!widget.mobileLayout && error != null) ...[
            const SizedBox(height: DSpacing.md),
            error,
          ],
          if (!widget.mobileLayout) ...[
            const SizedBox(height: 20),
            DSeparator(color: theme.shell.divider, space: 1),
            const SizedBox(height: 16),
            _actions(),
          ],
        ],
      ),
    );
    if (!widget.mobileLayout) return fields;
    return ComposerSheetLayout(
      title: widget.draft.isNew
          ? context.l10n.insertDateAndTime
          : context.l10n.editDateAndTime,
      onApply: _apply,
      onRemove: widget.draft.isNew ? null : _remove,
      removeLabel: context.l10n.removeLocaldatecomposersheet,
      error: error,
      child: fields,
    );
  }

  Widget _dateTimeRow({
    required TextEditingController date,
    required TextEditingController time,
    required String label,
    required bool hasTime,
    required ValueChanged<bool> onTimeEnabled,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          Widget dateField(double width) => DDatePickerInput(
            controller: date,
            initialValue: _civilDate(date.text),
            label: appL10n.dateLocaldatecomposersheet((label).toString()),
            width: width,
            startMonth: DCalendarDate(1900, 1, 1),
            endMonth: DCalendarDate(2200, 12, 31),
            dateCodec: const DIntlDateTextCodec(
              formatPattern: 'yyyy-MM-dd',
              useLocaleDateOrder: false,
            ),
          );
          final timeField = Row(
            children: [
              Expanded(
                child: DInput(
                  controller: time,
                  keyboardType: TextInputType.datetime,
                  labelText: appL10n.timeLocaldatecomposersheet(
                    (label).toString(),
                  ),
                  hintText: '09:00:00',
                ),
              ),
              DButton.iconOnly(
                onPressed: () => unawaited(_pickTime(time)),
                variant: DButtonVariant.ghost,
                tooltip: appL10n.chooseTime((label).toString()),
                icon: const Icon(Icons.schedule),
              ),
            ],
          );
          if (constraints.maxWidth < 430) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                dateField(constraints.maxWidth),
                if (hasTime) ...[const SizedBox(height: 12), timeField],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: LayoutBuilder(
                  builder: (context, size) => dateField(size.maxWidth),
                ),
              ),
              if (hasTime) ...[
                const SizedBox(width: 12),
                Expanded(flex: 2, child: timeField),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: 8),
      DCheckbox(
        contentPadding: EdgeInsets.zero,
        title: DLabel(
          child: Text(appL10n.includeTime((label.toLowerCase()).toString())),
        ),
        value: hasTime,
        onChanged: (value) => onTimeEnabled(value ?? false),
      ),
    ],
  );

  Widget _preview() {
    final draft = _draft();
    final validation = draft.validate(locale: Localizations.localeOf(context));
    final text = validation.isValid
        ? _previewText(draft)
        : validation.firstError ?? appL10n.completeTheDateToSeeAPreview;
    return DCard(
      size: DCardSize.small,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            const SizedBox(height: 2),
            Text(
              appL10n.previewOfTheRenderedDate,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _previewText(LocalDateComposerDraft draft) {
    final locale = Localizations.localeOf(context);
    final formatter = LocalDateFormatter(environment: draft.environment);
    final start = formatter.resolve(
      LocalDateSpec(
        date: draft.startDate,
        time: draft.startTime,
        timezone: draft.timezone,
        format: draft.format,
        calendar: draft.calendar,
        recurring: draft.recurring,
        countdown: draft.countdown,
        displayedTimezone: draft.displayedTimezone,
        fallbackText: '',
      ),
      locale: locale,
    );
    if (start == null) return appL10n.thatWallTimeDoesNotExist;
    if (!draft.isRange) return start.formatted;
    final end = formatter.resolve(
      LocalDateSpec(
        date: draft.endDate!,
        time: draft.endTime,
        timezone: draft.timezone,
        format: draft.format,
        calendar: draft.calendar,
        displayedTimezone: draft.displayedTimezone,
        fallbackText: '',
      ),
      locale: locale,
    );
    return end == null
        ? start.formatted
        : '${start.formatted} → ${end.formatted}';
  }

  Widget _actions() => Wrap(
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: DSpacing.controlGap,
    runSpacing: 8,
    children: [
      if (!widget.draft.isNew) ...[
        DButton(
          label: Text(appL10n.removeLocaldatecomposersheet),
          onPressed: _remove,
          variant: DButtonVariant.destructive,
        ),
      ],
      DButton(
        label: Text(appL10n.cancel),
        onPressed: () => Navigator.of(context).pop(),
      ),
      DButton(
        label: Text(appL10n.apply),
        onPressed: _apply,
        variant: DButtonVariant.primary,
      ),
    ],
  );

  void _remove() =>
      Navigator.of(context).pop(const LocalDateComposerSheetAction.remove());

  LocalDateComposerDraft _draft() => widget.draft.copyWith(
    startDate: _startDate.text.trim(),
    startTime: _hasStartTime ? _startTime.text.trim() : null,
    endDate: _hasEnd ? _endDate.text.trim() : null,
    endTime: _hasEnd && _hasEndTime ? _endTime.text.trim() : null,
    timezone: _timezone,
    recurring: !_hasEnd && _recurring.text.trim().isNotEmpty
        ? _recurring.text.trim()
        : null,
    countdown: !_hasEnd && _countdown,
    displayedTimezone: _displayedTimezone,
    calendar: switch (_calendar) {
      _CalendarMode.automatic => null,
      _CalendarMode.on => true,
      _CalendarMode.off => false,
    },
    previewTimezones: _previewTimezones,
    format: _format.text.trim().isEmpty ? null : _format.text.trim(),
  );

  void _apply() {
    if (widget.isCurrent?.call() == false) {
      setState(
        () => _error =
            appL10n.theComposerChangedWhileThisDateWasOpenNothingWasChanged,
      );
      return;
    }
    final draft = _draft();
    final validation = draft.validate(locale: Localizations.localeOf(context));
    if (!validation.isValid) {
      setState(() => _error = validation.firstError);
      return;
    }
    Navigator.of(context).pop(LocalDateComposerSheetAction.apply(draft));
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(controller.text);
    final initial = match == null
        ? TimeOfDay.now()
        : TimeOfDay(
            hour: int.parse(match.group(1)!).clamp(0, 23),
            minute: int.parse(match.group(2)!).clamp(0, 59),
          );
    final selected = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (selected == null || !mounted) return;
    controller.text =
        '${selected.hour.toString().padLeft(2, '0')}:'
        '${selected.minute.toString().padLeft(2, '0')}:00';
  }
}

DCalendarDate? _civilDate(String value) {
  final parsed = DateTime.tryParse(value.trim());
  return parsed == null ? null : DCalendarDate.fromDateTime(parsed);
}

class _TimezoneMenu extends StatelessWidget {
  const _TimezoneMenu({
    super.key,
    required this.label,
    required this.zones,
    required this.initial,
    required this.onSelected,
    this.optional = false,
  });

  final String label;
  final List<String> zones;
  final String? initial;
  final ValueChanged<String?> onSelected;
  final bool optional;

  @override
  Widget build(BuildContext context) => DField(
    children: [
      DFieldLabel(child: Text(label)),
      DCombobox<String>.controlled(
        value: initial ?? (optional ? '' : null),
        options: [
          if (optional)
            DComboboxOption(value: '', label: context.l10n.noneDeviceTimezone),
          for (final zone in zones) DComboboxOption(value: zone, label: zone),
        ],
        anchor: DComboboxInput<String>(semanticLabel: label),
        content: DComboboxContent(
          children: [
            DComboboxEmpty<String>(child: Text(context.l10n.noTimezonesFound)),
            const DComboboxList<String>(),
          ],
        ),
        onChanged: (value, reason) =>
            onSelected(value == null || value.isEmpty ? null : value),
      ),
    ],
  );
}
