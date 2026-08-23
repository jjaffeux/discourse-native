import 'dart:async';

import 'package:flutter/material.dart';

import '../../shell/platform.dart';
import '../../shell/shell_sheet.dart';
import '../../theme/app_theme.dart';
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
  final title = draft.isNew ? 'Insert date and time' : 'Edit date and time';
  Widget editor(BuildContext context) => LocalDateComposerSheet(
    draft: draft,
    siteFormats: siteFormats,
    isCurrent: isCurrent,
  );
  if (context.isTouch) {
    return showShellSheet<LocalDateComposerSheetAction>(
      context: context,
      title: title,
      padding: EdgeInsets.zero,
      builder: editor,
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
                    child: Text(
                      title,
                      style: Theme.of(dialogContext).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(color: Theme.of(dialogContext).shell.divider, height: 1),
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
  });

  final LocalDateComposerDraft draft;
  final List<String> siteFormats;
  final bool Function()? isCurrent;

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
      ...LocalDateEnvironment.instance.timezoneNames,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dateTimeRow(
            date: _startDate,
            time: _startTime,
            label: 'Start',
            hasTime: _hasStartTime,
            onTimeEnabled: (value) => setState(() => _hasStartTime = value),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('End date and time'),
            value: _hasEnd,
            onChanged: (value) => setState(() {
              _hasEnd = value;
              if (!value) _hasEndTime = false;
            }),
          ),
          if (_hasEnd)
            _dateTimeRow(
              date: _endDate,
              time: _endTime,
              label: 'End',
              hasTime: _hasEndTime,
              onTimeEnabled: (value) => setState(() => _hasEndTime = value),
            ),
          const SizedBox(height: 16),
          _TimezoneMenu(
            key: const ValueKey('local-date-source-timezone'),
            label: 'Source timezone',
            zones: _zones,
            initial: _timezone,
            onSelected: (zone) {
              if (zone != null) setState(() => _timezone = zone);
            },
          ),
          const SizedBox(height: 16),
          _preview(),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('Display options'),
            children: [
              if (!_hasEnd) ...[
                TextField(
                  controller: _recurring,
                  decoration: const InputDecoration(
                    labelText: 'Recurrence (optional)',
                    hintText: '1.weeks',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Countdown'),
                  value: _countdown,
                  onChanged: (value) => setState(() => _countdown = value),
                ),
              ],
              _TimezoneMenu(
                key: const ValueKey('local-date-displayed-timezone'),
                label: 'Displayed timezone (optional)',
                zones: _zones,
                initial: _displayedTimezone,
                optional: true,
                onSelected: (zone) => setState(() => _displayedTimezone = zone),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_CalendarMode>(
                initialValue: _calendar,
                decoration: const InputDecoration(labelText: 'Relative day'),
                items: const [
                  DropdownMenuItem(
                    value: _CalendarMode.automatic,
                    child: Text('Automatic'),
                  ),
                  DropdownMenuItem(
                    value: _CalendarMode.on,
                    child: Text('Always on'),
                  ),
                  DropdownMenuItem(
                    value: _CalendarMode.off,
                    child: Text('Off'),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _calendar = value ?? _CalendarMode.automatic,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _format,
                decoration: InputDecoration(
                  labelText: 'Moment format (optional)',
                  hintText: widget.siteFormats.firstOrNull ?? 'LLL',
                  helperText: widget.siteFormats.isEmpty
                      ? 'For example: LLL or YYYY-MM-DD [at] HH:mm'
                      : 'Site formats: ${widget.siteFormats.join(', ')}',
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
              Text('Preview timezones', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final zone in _previewTimezones)
                    InputChip(
                      label: Text(LocalDateFormatter.zoneLabel(zone)),
                      onDeleted: () =>
                          setState(() => _previewTimezones.remove(zone)),
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
                        label: 'Add preview timezone',
                        zones: _zones
                            .where((zone) => !_previewTimezones.contains(zone))
                            .toList(),
                        initial: null,
                        optional: true,
                        onSelected: (zone) =>
                            setState(() => _previewCandidate = zone),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _previewCandidate == null
                          ? null
                          : () => setState(() {
                              _previewTimezones.add(_previewCandidate!);
                              _previewCandidate = null;
                            }),
                      icon: const Icon(Icons.add),
                      tooltip: 'Add timezone',
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                error,
                key: const ValueKey('local-date-sheet-error'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _actions(),
        ],
      ),
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
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: date,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(labelText: '$label date'),
            ),
          ),
          IconButton(
            onPressed: () => unawaited(_pickDate(date)),
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Choose $label date',
          ),
        ],
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text('$label time'),
        value: hasTime,
        onChanged: (value) => onTimeEnabled(value ?? false),
      ),
      if (hasTime)
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: time,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: '$label time',
                  hintText: '09:00:00',
                ),
              ),
            ),
            IconButton(
              onPressed: () => unawaited(_pickTime(time)),
              icon: const Icon(Icons.schedule),
              tooltip: 'Choose $label time',
            ),
          ],
        ),
    ],
  );

  Widget _preview() {
    final draft = _draft();
    final validation = draft.validate(locale: Localizations.localeOf(context));
    final text = validation.isValid
        ? _previewText(draft)
        : validation.firstError ?? 'Complete the date to see a preview.';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.public, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  String _previewText(LocalDateComposerDraft draft) {
    final locale = Localizations.localeOf(context);
    const formatter = LocalDateFormatter();
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
    if (start == null) return 'That wall time does not exist.';
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
    spacing: 8,
    runSpacing: 8,
    children: [
      if (!widget.draft.isNew) ...[
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(const LocalDateComposerSheetAction.remove()),
          child: const Text('Remove'),
        ),
      ],
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _apply, child: const Text('Apply')),
    ],
  );

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
            'The composer changed while this date was open. Nothing was changed.',
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

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selected == null || !mounted) return;
    controller.text =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => DropdownMenu<String>(
      width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
      label: Text(label),
      initialSelection: initial,
      enableFilter: true,
      enableSearch: true,
      requestFocusOnTap: true,
      dropdownMenuEntries: [
        if (optional)
          const DropdownMenuEntry(value: '', label: 'None / device timezone'),
        for (final zone in zones) DropdownMenuEntry(value: zone, label: zone),
      ],
      onSelected: (value) =>
          onSelected(value == null || value.isEmpty ? null : value),
    ),
  );
}
