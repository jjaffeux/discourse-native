import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'event_composer_parser.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_time.dart';

ComposerSyntaxKind get eventSyntaxKind => ComposerSyntaxKind(
  owner: eventsPluginId,
  name: 'event',
  label: appL10n.event,
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

final class EventProjection implements ComposerBlockSyntaxProjection {
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
  int caretAfter(String document) {
    if (document.startsWith('\r\n', end)) return end + 2;
    return document.startsWith('\n', end) ? end + 1 : end;
  }

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
          '▦ ${block.attribute('name') ?? appL10n.event} · ${block.attribute('start') ?? ''}',
          style: context.baseStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
    TextSpan(
      text: '\n',
      style: context.baseStyle.copyWith(color: Colors.transparent),
    ),
    TextSpan(
      text: source.substring(2),
      style: const TextStyle(
        fontSize: 0,
        height: 0,
        letterSpacing: 0,
        color: Colors.transparent,
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
  final touch = context.isTouch;
  Widget content(BuildContext context) => EventComposerSheet(
    embedded: touch,
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
  );
  final result = touch
      ? await showDSheet<String>(
          context: context,
          side: DSheetSide.bottom,
          inset: true,
          fillAvailableHeight: true,
          builder: (context, sheet) => DSheetContent(
            side: DSheetSide.bottom,
            semanticLabel: block == null ? appL10n.addEvent : appL10n.editEvent,
            topBottomMaxHeightFactor: 1,
            scrollWholeSheet: false,
            children: [
              DSheetHeader(
                children: [
                  DSheetTitle(
                    child: Text(
                      block == null ? appL10n.addEvent : appL10n.editEvent,
                    ),
                  ),
                ],
              ),
              Expanded(child: SingleChildScrollView(child: content(context))),
            ],
          ),
        )
      : await showDiscourseDialog<String>(context: context, builder: content);
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
    this.embedded = false,
  });
  final EventBlock? block;
  final EventSettings settings;
  final String timezone;
  final EventController? controller;
  final bool embedded;
  final bool Function() isCurrent;
  @override
  State<EventComposerSheet> createState() => _EventComposerSheetState();
}

class _EventComposerSheetState extends State<EventComposerSheet> {
  static Map<String, String> get _textFields => {
    'name': appL10n.name,
    'start': appL10n.starts,
    'end': appL10n.endsOptional,
    'timezone': appL10n.timezone,
    'recurrence-until': appL10n.repeatUntilOptional,
    'allowed-groups': appL10n.allowedGroupsCommaSeparated,
    'url': appL10n.meetingOrEventURL,
    'location': appL10n.location,
    'max-attendees': appL10n.maximumAttendeesOptional,
    'reminders': appL10n.remindersForExampleNotification15Minutes,
    'image': appL10n.eventImageURL,
  };
  static Map<String, String> get _booleanFields => {
    'all-day': appL10n.allDay,
    'show-local-time': appL10n.displayInTheEventTimezone,
    'minimal': appL10n.minimalCard,
    'closed': appL10n.closed,
    'chat-enabled': appL10n.enableEventChat,
    'livestream': appL10n.enableLivestreamFromTheEventURL,
  };
  final _fields = <String, TextEditingController>{};
  final _initial = <String, String>{};
  final _booleans = <String, bool>{};

  /// Setting names by the attribute each custom field is read from and
  /// written to. A setting naming a built-in field is that field.
  final _customFields = <String, String>{};
  late final TextEditingController _description;
  late String _recurrence;
  late String _status;
  String? _error;
  @override
  void initState() {
    super.initState();
    final block = widget.block;
    for (final name in widget.settings.customFields) {
      final attribute = eventCustomFieldAttributeName(name);
      if (!_textFields.containsKey(attribute)) _customFields[attribute] = name;
    }
    for (final name in {..._textFields.keys, ..._customFields.keys}) {
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
        () => _error = appL10n.thePostChangedWhileThisEditorWasOpenCloseItAnd,
      );
      return;
    }
    try {
      final start = _fields['start']!.text.trim();
      final end = _fields['end']!.text.trim();
      final allDay = _booleans['all-day']!;
      if (eventCalendarDay(start) == null ||
          (!allDay && !RegExp(r'[T ]\d{2}:\d{2}').hasMatch(start))) {
        throw FormatException(appL10n.enterAStartDateAndTimeOrSelectAllDay);
      }
      if (end.isNotEmpty && eventCalendarDay(end) == null) {
        throw FormatException(appL10n.enterAValidEndDate);
      }
      final zones = widget.controller?.zones;
      final zone = _fields['timezone']!.text.trim();
      if (!allDay && zones != null && zones.location(zone) == null) {
        throw FormatException(appL10n.chooseAValidTimezoneSuchAsEuropeParis);
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
        throw FormatException(appL10n.enterValidDatesAndTimes);
      }
      if (endDate != null &&
          (endDate.isBefore(startDate) || (!allDay && endDate == startDate))) {
        throw FormatException(appL10n.theEventMustEndAfterItStarts);
      }
      final capacity = _fields['max-attendees']!.text.trim();
      if (capacity.isNotEmpty && (int.tryParse(capacity) ?? 0) < 1) {
        throw FormatException(
          appL10n.maximumAttendeesMustBeAPositiveWholeNumber,
        );
      }
      if (_status == 'private' &&
          _fields['allowed-groups']!.text.trim().isEmpty) {
        throw FormatException(
          appL10n.chooseAtLeastOneAllowedGroupForAPrivateEvent,
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
      labelText: _textFields[name] ?? _customFields[name] ?? name,
      hintText: {'start', 'end', 'recurrence-until'}.contains(name)
          ? (_booleans['all-day']!
                ? appL10n.inputIsoDate
                : appL10n.yYYYMMDDHHMm)
          : null,
      suffix: {'start', 'end', 'recurrence-until'}.contains(name)
          ? DButton.iconOnly(
              onPressed: () => _chooseDate(name),
              variant: DButtonVariant.ghost,
              tooltip: appL10n.chooseDateAndTime,
              icon: const Icon(Icons.calendar_today),
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
  Widget build(BuildContext context) {
    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _field('name'),
        _field('start'),
        _field('end'),
        DCheckbox(
          contentPadding: EdgeInsets.zero,
          title: DLabel(child: Text(context.l10n.allDay)),
          value: _booleans['all-day'],
          onChanged: (value) => setState(() => _booleans['all-day'] = value!),
        ),
        if (!_booleans['all-day']!) _field('timezone'),
        DSelect<String>.controlled(
          isExpanded: true,
          value: _recurrence,
          label: Text(context.l10n.repeats),
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
                label:
                    eventRecurrenceLabel(value) ?? context.l10n.doesNotRepeat,
                child: Text(
                  eventRecurrenceLabel(value) ?? context.l10n.doesNotRepeat,
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
          label: Text(context.l10n.participation),
          entries: [
            for (final value in {'public', 'private', 'standalone', _status})
              DSelectOption(
                value: value,
                label: switch (value) {
                  'public' => context.l10n.public,
                  'private' => context.l10n.privateGroups,
                  'standalone' => context.l10n.noAttendanceTracking,
                  _ => value,
                },
                child: Text(switch (value) {
                  'public' => context.l10n.public,
                  'private' => context.l10n.privateGroups,
                  'standalone' => context.l10n.noAttendanceTracking,
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
          labelText: context.l10n.descriptionMarkdown,
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
                      Expanded(child: Text(context.l10n.moreOptions)),
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
                    for (final attribute in _customFields.keys)
                      _field(attribute),
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
    );
    final actions = <Widget>[
      DButton(
        label: Text(context.l10n.apply),
        onPressed: _apply,
        variant: DButtonVariant.primary,
      ),
      DButton(
        label: Text(context.l10n.cancel),
        onPressed: () => Navigator.pop(context),
      ),
      if (widget.block != null)
        DButton(
          label: Text(context.l10n.removeEvent),
          variant: DButtonVariant.destructive,
          onPressed: () {
            if (widget.isCurrent()) Navigator.pop(context, '');
          },
        ),
    ];
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fields,
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      );
    }
    return DiscourseAlertDialog(
      title: Text(
        widget.block == null ? context.l10n.addEvent : context.l10n.editEvent,
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(child: fields),
      ),
      actions: actions,
    );
  }
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
      return PluginComposerSubmitPreparation.failed(
        WriteException(
          WriteFailure.validation,
          errors: [appL10n.anEventMustBeTheOnlyEventInTheFirstPost],
        ),
      );
    }
    return const PluginComposerSubmitPreparation.proceed();
  }
}
