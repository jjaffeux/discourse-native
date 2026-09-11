import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/discourse_api_contracts.dart'
    show WriteException, WriteFailure;
import '../../plugin_api/composer_syntax.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/shell_extensions.dart';
import '../../shell/adaptive_dialog_action.dart';
import 'event_composer_parser.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_time.dart';

const eventSyntaxKind = ComposerSyntaxKind(
  owner: eventsPluginId,
  name: 'event',
);

final class EventSyntaxPolicy implements ComposerSyntaxPolicy {
  const EventSyntaxPolicy(this.context);
  final ComposerSyntaxPolicyContext context;
  ComposerPluginState get state => context.readState();
  bool get firstPost =>
      !context.isPluginTarget &&
      (state.createsTopic || state.editingPostNumber == 1);
  bool get canAuthor =>
      firstPost &&
      state.siteSettings.get(eventSettingsKey)?.enabled == true &&
      state.freshCurrentUser.get(eventUserKey)?.canCreate == true;
  @override
  ComposerSyntaxKind get kind => eventSyntaxKind;
  @override
  Object get projectionState => (canAuthor, firstPost);
  @override
  TextInputFormatter? get inputFormatter => null;
  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final block in parseEventBlocks(source)) EventProjection(block, this),
  ];
}

final class EventProjection implements ComposerSyntaxProjection {
  const EventProjection(this.block, this.policy);
  final EventBlock block;
  final EventSyntaxPolicy policy;
  @override
  int get start => block.start;
  @override
  int get end => block.end;
  @override
  String get source => block.source;
  @override
  bool get supportsHover => true;
  @override
  bool get protectsAdjacentDelete => true;
  @override
  int caretAfter(String document) =>
      end < document.length && document[end] == '\n' ? end + 1 : end;
  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: caretAfter(document.text)),
        composing: TextRange.empty,
      );
  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) {
    if (!policy.canAuthor) return true;
    final selection = document.selection;
    if (!selection.isValid) return false;
    if (selection.isCollapsed && suppressCollapsedCaret) return false;
    return selection.isCollapsed
        ? selection.baseOffset > start && selection.baseOffset < end
        : selection.start < end && selection.end > start;
  }

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) => [
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        key: context.pillKey,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: context.baseStyle.color ?? Colors.grey),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '▦ ${block.attribute('name') ?? 'Event'} · ${block.attribute('start') ?? ''}',
          style: context.baseStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  ];
  @override
  Future<void> edit(BuildContext context, ComposerEditorHost editor) =>
      openEventComposer(context, editor, policy, block: block);
  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    if (!policy.canAuthor || !editor.isCurrent || !editor.isEditing) return;
    final expected = editor.value.text;
    if (end > expected.length || expected.substring(start, end) != source) {
      return;
    }
    editor.commitText(
      expectedText: expected,
      value: TextEditingValue(
        text: expected.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      ),
    );
  }
}

Future<void> openEventComposer(
  BuildContext context,
  ComposerEditorHost editor,
  EventSyntaxPolicy policy, {
  EventBlock? block,
}) async {
  if (!editor.isCurrent || !editor.isEditing || !policy.canAuthor) return;
  final expected = editor.value;
  final blocks = parseEventBlocks(expected.text);
  if (block == null && (blocks.isNotEmpty || hasEventMarkup(expected.text))) {
    return;
  }
  if (block != null &&
      (block.end > expected.text.length ||
          expected.text.substring(block.start, block.end) != block.source)) {
    return;
  }
  final controller = PluginUiScope.maybe(context, eventControllerKey);
  final result = await showDiscourseDialog<String>(
    context: context,
    builder: (_) => EventComposerSheet(
      block: block,
      settings:
          policy.state.siteSettings.get(eventSettingsKey) ??
          const EventSettings(),
      timezone:
          policy.state.accountTimezone ??
          controller?.zones.readerTimezone() ??
          'Etc/UTC',
      controller: controller,
      isCurrent: () =>
          editor.isCurrent &&
          editor.isEditing &&
          policy.canAuthor &&
          editor.value.text == expected.text,
    ),
  );
  if (result == null ||
      !context.mounted ||
      !editor.isCurrent ||
      !editor.isEditing ||
      !policy.canAuthor) {
    return;
  }
  if (block == null) {
    editor.insertBlock(expectedValue: expected, markdown: result);
  } else {
    editor.commitText(
      expectedText: expected.text,
      value: TextEditingValue(
        text: expected.text.replaceRange(block.start, block.end, result),
        selection: TextSelection.collapsed(offset: block.start + result.length),
      ),
    );
  }
  editor.requestFocus();
}

class EventComposerSheet extends StatefulWidget {
  const EventComposerSheet({
    super.key,
    required this.settings,
    required this.timezone,
    required this.isCurrent,
    this.block,
    this.controller,
  });
  final EventBlock? block;
  final EventSettings settings;
  final String timezone;
  final EventController? controller;
  final bool Function() isCurrent;
  @override
  State<EventComposerSheet> createState() => _EventComposerSheetState();
}

class _EventComposerSheetState extends State<EventComposerSheet> {
  static const _textFields = {
    'name': 'Name',
    'start': 'Starts',
    'end': 'Ends (optional)',
    'timezone': 'Timezone',
    'recurrence-until': 'Repeat until (optional)',
    'allowed-groups': 'Allowed groups (comma separated)',
    'url': 'Meeting or event URL',
    'location': 'Location',
    'max-attendees': 'Maximum attendees (optional)',
    'reminders': 'Reminders (for example: notification.15.minutes)',
    'image': 'Event image URL',
  };
  static const _booleanFields = {
    'all-day': 'All day',
    'show-local-time': 'Display in the event timezone',
    'minimal': 'Minimal card',
    'closed': 'Closed',
    'chat-enabled': 'Enable event chat',
    'livestream': 'Enable livestream from the event URL',
  };
  final _fields = <String, TextEditingController>{};
  final _initial = <String, String>{};
  final _booleans = <String, bool>{};
  late final TextEditingController _description;
  late String _recurrence;
  late String _status;
  String? _error;
  @override
  void initState() {
    super.initState();
    final block = widget.block;
    for (final name in {..._textFields.keys, ...widget.settings.customFields}) {
      final value =
          block?.attribute(name) ??
          (name == 'timezone' ? (block == null ? widget.timezone : 'UTC') : '');
      _fields[name] = TextEditingController(text: value);
      _initial[name] = value;
    }
    for (final name in _booleanFields.keys) {
      _booleans[name] = block?.attribute(name) == 'true';
    }
    _status = block?.attribute('status') ?? 'public';
    _recurrence = block?.attribute('recurrence') ?? '';
    _description = TextEditingController(text: block?.description ?? '\n\n');
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    _description.dispose();
    super.dispose();
  }

  void _apply() {
    if (!widget.isCurrent()) {
      setState(
        () => _error =
            'The post changed while this editor was open. Close it and reopen the event.',
      );
      return;
    }
    try {
      final start = _fields['start']!.text.trim();
      final end = _fields['end']!.text.trim();
      final allDay = _booleans['all-day']!;
      if (eventCalendarDay(start) == null ||
          (!allDay && !RegExp(r'[T ]\d{2}:\d{2}').hasMatch(start))) {
        throw const FormatException(
          'Enter a start date and time, or select All day.',
        );
      }
      if (end.isNotEmpty && eventCalendarDay(end) == null) {
        throw const FormatException('Enter a valid end date.');
      }
      final zones = widget.controller?.zones;
      final zone = _fields['timezone']!.text.trim();
      if (!allDay && zones != null && zones.location(zone) == null) {
        throw const FormatException(
          'Choose a valid timezone, such as Europe/Paris.',
        );
      }
      final startDate = zones == null
          ? DateTime.tryParse(start)
          : eventDate(
              start,
              zones: zones,
              timezone: zone,
              allDay: allDay,
              showLocalTime: true,
            );
      final endDate = end.isEmpty
          ? null
          : zones == null
          ? DateTime.tryParse(end)
          : eventDate(
              end,
              zones: zones,
              timezone: zone,
              allDay: allDay,
              showLocalTime: true,
            );
      if (startDate == null || (end.isNotEmpty && endDate == null)) {
        throw const FormatException('Enter valid dates and times.');
      }
      if (endDate != null &&
          (endDate.isBefore(startDate) || (!allDay && endDate == startDate))) {
        throw const FormatException('The event must end after it starts.');
      }
      final capacity = _fields['max-attendees']!.text.trim();
      if (capacity.isNotEmpty && (int.tryParse(capacity) ?? 0) < 1) {
        throw const FormatException(
          'Maximum attendees must be a positive whole number.',
        );
      }
      if (_status == 'private' &&
          _fields['allowed-groups']!.text.trim().isEmpty) {
        throw const FormatException(
          'Choose at least one allowed group for a private event.',
        );
      }
      final values = <String, String?>{};
      for (final entry in _fields.entries) {
        if (widget.block == null || entry.value.text != _initial[entry.key]) {
          values[entry.key] = entry.value.text;
        }
      }
      for (final entry in _booleans.entries) {
        if (widget.block == null
            ? entry.value
            : entry.value != (widget.block!.attribute(entry.key) == 'true')) {
          values[entry.key] = entry.value ? 'true' : 'false';
        }
      }
      if (widget.block == null ||
          _status != (widget.block!.attribute('status') ?? 'public')) {
        values['status'] = _status;
      }
      if (widget.block == null ||
          _recurrence != (widget.block!.attribute('recurrence') ?? '')) {
        values['recurrence'] = _recurrence;
      }
      if (allDay &&
          (widget.block == null ||
              widget.block?.attribute('all-day') != 'true')) {
        values['start'] = start.substring(0, 10);
        if (end.isNotEmpty) values['end'] = end.substring(0, 10);
      }
      final raw =
          widget.block?.replace(values, description: _description.text) ??
          '[event${[for (final entry in values.entries)
            if (entry.value?.isNotEmpty == true) ' ${eventAttributeName(entry.key)}=${eventAttributeSource(entry.value!)}'].join()}]${_description.text}[/event]';
      Navigator.pop(context, raw);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Widget _field(String name) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: DInput(
      controller: _fields[name],
      labelText: _textFields[name] ?? name,
      hintText: {'start', 'end', 'recurrence-until'}.contains(name)
          ? (_booleans['all-day']! ? 'YYYY-MM-DD' : 'YYYY-MM-DD HH:mm')
          : null,
      suffix: {'start', 'end', 'recurrence-until'}.contains(name)
          ? DTooltip(
              message: 'Choose date and time',
              labelTrigger: true,
              child: IconButton(
                tooltip: '',
                icon: const Icon(Icons.calendar_today),
                onPressed: () => _chooseDate(name),
              ),
            )
          : null,
      keyboardType: name == 'max-attendees'
          ? TextInputType.number
          : TextInputType.text,
    ),
  );

  Future<void> _chooseDate(String name) async {
    final held = DateTime.tryParse(_fields[name]!.text) ?? DateTime.now();
    final first = DateTime(1900);
    final last = DateTime(2200);
    final day = await showDatePicker(
      context: context,
      initialDate: held.isBefore(first)
          ? first
          : held.isAfter(last)
          ? last
          : held,
      firstDate: first,
      lastDate: last,
    );
    if (day == null || !mounted) return;
    final allDay = _booleans['all-day']!;
    final time = allDay
        ? null
        : await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(held),
          );
    if (!mounted || (!allDay && time == null)) return;
    String two(int value) => value.toString().padLeft(2, '0');
    _fields[name]!.text =
        '${day.year}-${two(day.month)}-${two(day.day)}'
        '${time == null ? '' : ' ${two(time.hour)}:${two(time.minute)}'}';
  }

  @override
  Widget build(BuildContext context) => DiscourseAlertDialog(
    title: Text(widget.block == null ? 'Add event' : 'Edit event'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field('name'),
            _field('start'),
            _field('end'),
            DCheckbox(
              contentPadding: EdgeInsets.zero,
              title: const DLabel(child: Text('All day')),
              value: _booleans['all-day'],
              onChanged: (value) =>
                  setState(() => _booleans['all-day'] = value!),
            ),
            if (!_booleans['all-day']!) _field('timezone'),
            DSelect<String>.controlled(
              isExpanded: true,
              value: _recurrence,
              label: const Text('Repeats'),
              entries: [
                for (final value in {
                  '',
                  'every_day',
                  'every_weekday',
                  'every_week',
                  'every_two_weeks',
                  'every_four_weeks',
                  'every_month',
                  _recurrence,
                })
                  DSelectOption(
                    value: value,
                    label: eventRecurrenceLabel(value) ?? 'Does not repeat',
                    child: Text(
                      eventRecurrenceLabel(value) ?? 'Does not repeat',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _recurrence = value!),
              initialValue: _recurrence,
            ),
            if (_recurrence.isNotEmpty) _field('recurrence-until'),
            DSelect<String>.controlled(
              isExpanded: true,
              value: _status,
              label: const Text('Participation'),
              entries: [
                for (final value in {
                  'public',
                  'private',
                  'standalone',
                  _status,
                })
                  DSelectOption(
                    value: value,
                    label: switch (value) {
                      'public' => 'Public',
                      'private' => 'Private groups',
                      'standalone' => 'No attendance tracking',
                      _ => value,
                    },
                    child: Text(switch (value) {
                      'public' => 'Public',
                      'private' => 'Private groups',
                      'standalone' => 'No attendance tracking',
                      _ => value,
                    }),
                  ),
              ],
              onChanged: (value) => setState(() => _status = value!),
              initialValue: _status,
            ),
            if (_status == 'private') _field('allowed-groups'),
            _field('url'),
            _field('location'),
            DTextarea(
              controller: _description,
              minLines: 3,
              maxLines: 8,
              labelText: 'Description (Markdown)',
            ),
            DCollapsible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DCollapsibleTrigger(
                    builder: (context, state) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          const Expanded(child: Text('More options')),
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
                        _field('max-attendees'),
                        _field('reminders'),
                        _field('image'),
                        for (final name in widget.settings.customFields)
                          if (!_textFields.containsKey(name)) _field(name),
                        for (final entry in _booleanFields.entries)
                          if (entry.key != 'all-day')
                            DCheckbox(
                              contentPadding: EdgeInsets.zero,
                              title: DLabel(child: Text(entry.value)),
                              value: _booleans[entry.key],
                              onChanged: (value) =>
                                  setState(() => _booleans[entry.key] = value!),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      DButton(
        label: const Text('Apply'),
        onPressed: _apply,
        variant: DButtonVariant.primary,
      ),
      DButton(
        label: const Text('Cancel'),
        onPressed: () => Navigator.pop(context),
      ),
      if (widget.block != null)
        DButton(
          label: const Text('Remove event'),
          variant: DButtonVariant.destructive,
          onPressed: () {
            if (widget.isCurrent()) Navigator.pop(context, '');
          },
        ),
    ],
  );
}

final class EventSubmitPreparer implements PluginComposerSubmitPreparer {
  const EventSubmitPreparer();
  @override
  PluginComposerSubmitPreparation prepareComposerSubmit(
    ComposerEditorHost composer,
  ) {
    final policy = composer.syntaxPolicy<EventSyntaxPolicy>(eventSyntaxKind);
    final blocks = parseEventBlocks(composer.value.text);
    if (blocks.isNotEmpty && (blocks.length > 1 || policy?.firstPost != true)) {
      return const PluginComposerSubmitPreparation.failed(
        WriteException(
          WriteFailure.validation,
          errors: [
            'An event must be the only event in the first post of a topic.',
          ],
        ),
      );
    }
    return const PluginComposerSubmitPreparation.proceed();
  }
}
