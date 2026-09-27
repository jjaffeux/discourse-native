import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'event_calendar.dart';
import 'event_calendar_data.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_navigation.dart';
import 'event_time.dart';
import 'topic_calendar_data.dart';

/// Finder occurrences are authoritative. A future occurrence never offers
/// RSVP controls: the server's attendance routes act on the current series.
List<PostEvent> eventDirectoryOccurrences(
  List<PostEvent> events,
  PluginTimezoneHost zones,
) {
  final candidates =
      <
        ({
          PostEvent event,
          Map<String, Object?>? occurrence,
          String startsAt,
          DateTime? instant,
          int index,
        })
      >[];
  void add(PostEvent event, {Map<String, Object?>? occurrence}) {
    Object? field(String key) => occurrence?.containsKey(key) == true
        ? occurrence![key]
        : event.fields[key];
    final startsAt = eventText(field('starts_at'));
    if (startsAt == null) return;
    candidates.add((
      event: event,
      occurrence: occurrence,
      startsAt: startsAt,
      instant: eventDate(
        startsAt,
        zones: zones,
        timezone: eventText(field('timezone')),
        allDay: field('all_day') == true,
        showLocalTime: field('show_local_time') == true,
      ),
      index: candidates.length,
    ));
  }

  for (final event in events) {
    final occurrences = event.fields['occurrences'];
    if (occurrences is List) {
      for (final raw in occurrences) {
        // PostEvent already froze these maps; keep references until selected.
        if (raw is Map<String, Object?> &&
            eventText(raw['starts_at']) != null) {
          add(event, occurrence: raw);
        }
      }
    } else {
      add(event);
    }
  }
  candidates.sort((a, b) {
    final first = a.instant;
    final second = b.instant;
    final int order;
    if (first != null && second != null) {
      order = first.compareTo(second);
    } else if (first == null && second == null) {
      order = a.startsAt.compareTo(b.startsAt);
    } else {
      // Unknown dates follow known instants, keeping the comparison transitive.
      order = first == null ? 1 : -1;
    }
    return order != 0 ? order : a.index.compareTo(b.index);
  });

  final result = <PostEvent>[];
  final seen = <(int, String)>{};
  for (final candidate in candidates) {
    final occurrence = candidate.occurrence;
    final id = occurrence?.containsKey('id') == true
        ? eventInt(occurrence!['id'])
        : candidate.event.id;
    if (id == null || seen.contains((id, candidate.startsAt))) continue;
    // Keep each occurrence independent without copying the recurrence array.
    final event = occurrence == null
        ? candidate.event
        : PostEvent.decode({
            for (final entry in candidate.event.fields.entries)
              if (entry.key != 'occurrences') entry.key: entry.value,
            for (final entry in occurrence.entries)
              if (entry.key != 'occurrences') entry.key: entry.value,
            'should_display_invitees': false,
            'sample_invitees': null,
            'stats': null,
            'watching_invitee': null,
            'can_update_attendance': false,
          }, topicId: candidate.event.topicId);
    if (event == null) continue;
    seen.add((event.id, candidate.startsAt));
    result.add(event);
  }
  return List.unmodifiable(result);
}

class EventDirectory extends StatelessWidget {
  const EventDirectory({
    super.key,
    required this.site,
    required this.mine,
    required this.controller,
    required this.navigation,
    this.page,
  });
  final String site;
  final bool mine;
  final EventController controller;
  final EventNavigation navigation;
  final EventCalendarPage? page;
  @override
  Widget build(BuildContext context) => ContentReadingLaneBox(
    child: _EventDirectoryBody(
      site: site,
      mine: mine,
      controller: controller,
      navigation: navigation,
      page: page,
      // The mockup follows the shell width (53 + 240 + 420), so a narrow
      // desktop pane still starts in Month. Picking a view pins that choice.
      compact: MediaQuery.sizeOf(context).width < 713,
    ),
  );
}

class _EventDirectoryBody extends StatefulWidget {
  const _EventDirectoryBody({
    required this.site,
    required this.mine,
    required this.controller,
    required this.navigation,
    required this.page,
    required this.compact,
  });

  final String site;
  final bool mine;
  final EventController controller;
  final EventNavigation navigation;
  final EventCalendarPage? page;
  final bool compact;

  @override
  State<_EventDirectoryBody> createState() => _EventDirectoryState();
}

class _EventDirectoryState extends State<_EventDirectoryBody> {
  List<PostEvent> _occurrences = const [];
  List<EventCalendarEntry> _events = const [];
  late EventCalendarPage _page;
  late String _timezone;
  late int _firstDay;
  late EventSettings _settings;
  String? _error;
  int _generation = 0;
  int _accountRevision = 0;
  int _foregroundRevision = 0;
  bool _loading = true;
  bool _viewSelected = false;
  tz.Location get _location => widget.controller.zones.location(_timezone)!;
  String get _readerTimezone => widget.controller.zones.readerTimezone(
    widget.controller.accountTimezone(widget.site),
  );
  int get _siteFirstDay =>
      widget.controller.siteState
          .siteConfigFor(widget.site)
          .plugins
          .get(topicCalendarSettingsKey)
          ?.firstDay ??
      1;

  @override
  void initState() {
    super.initState();
    _timezone = _readerTimezone;
    _firstDay = _siteFirstDay;
    _settings = widget.controller.settings(widget.site);
    _accountRevision = widget.controller.accountRevision(widget.site);
    _foregroundRevision = widget.controller.foregroundRevision;
    widget.controller.addListener(_changed);
    _viewSelected = widget.page != null;
    _page = _directoryPage(widget.page) ?? _defaultPage();
    unawaited(_load());
  }

  EventCalendarPage _defaultPage() {
    final today = tz.TZDateTime.from(widget.controller.api.clock(), _location);
    final view = widget.compact
        ? EventCalendarView.schedule
        : EventCalendarView.month;
    return EventCalendarPage(
      view,
      DateTime.utc(today.year, today.month, today.day),
    );
  }

  // Old calendar links still open the requested month, but the directory only
  // offers the Month and Schedule presentations shown in the native mockups.
  EventCalendarPage? _directoryPage(EventCalendarPage? page) => page == null
      ? null
      : EventCalendarPage(
          page.view == EventCalendarView.schedule
              ? EventCalendarView.schedule
              : EventCalendarView.month,
          page.date,
        );

  void _changed() {
    final revision = widget.controller.accountRevision(widget.site);
    final foreground = widget.controller.foregroundRevision;
    final accountChanged = _accountRevision != revision;
    final resumed = _foregroundRevision != foreground;
    final calendarChanged =
        _timezone != _readerTimezone || _firstDay != _siteFirstDay;
    final settingsChanged =
        _settings != widget.controller.settings(widget.site);
    _accountRevision = revision;
    _foregroundRevision = foreground;
    _timezone = _readerTimezone;
    _firstDay = _siteFirstDay;
    _settings = widget.controller.settings(widget.site);
    if (accountChanged || resumed || calendarChanged) {
      _occurrences = const [];
      _events = const [];
      unawaited(_load());
    } else if (settingsChanged) {
      setState(_projectEvents);
    }
  }

  @override
  void didUpdateWidget(_EventDirectoryBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.controller != widget.controller;
    if (controllerChanged) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (controllerChanged ||
        oldWidget.site != widget.site ||
        oldWidget.mine != widget.mine) {
      _accountRevision = widget.controller.accountRevision(widget.site);
      _foregroundRevision = widget.controller.foregroundRevision;
      _timezone = _readerTimezone;
      _firstDay = _siteFirstDay;
      _settings = widget.controller.settings(widget.site);
      if (oldWidget.site != widget.site) _viewSelected = widget.page != null;
      _page =
          _directoryPage(widget.page) ??
          (oldWidget.site != widget.site ? _defaultPage() : _page);
      _occurrences = const [];
      _events = const [];
      unawaited(_load());
    } else {
      final calendarChanged =
          _timezone != _readerTimezone || _firstDay != _siteFirstDay;
      final oldRange = _page.days(firstDay: _firstDay);
      _timezone = _readerTimezone;
      _firstDay = _siteFirstDay;
      if (widget.page != null && widget.page != oldWidget.page) {
        final incoming = _directoryPage(widget.page)!;
        if (incoming != _page) _viewSelected = true;
        _page = incoming;
      } else if (!_viewSelected && oldWidget.compact != widget.compact) {
        _page = EventCalendarPage(_defaultPage().view, _page.date);
      }
      if (_settings != widget.controller.settings(widget.site)) {
        _settings = widget.controller.settings(widget.site);
        _projectEvents();
      }
      if (calendarChanged || oldRange != _page.days(firstDay: _firstDay)) {
        unawaited(_load());
      }
    }
  }

  void _projectEvents() {
    final controller = widget.controller;
    _events = [
      for (final event in _occurrences)
        ?EventCalendarEntry.decode(
          event,
          zones: controller.zones,
          timezone: _timezone,
          settings: _settings,
          categoryName: switch (eventInt(event.fields['category_id'])) {
            final id? =>
              controller.siteState.categoryFor?.call(widget.site, id)?.name,
            _ => null,
          },
          categoryColor: switch (eventInt(event.fields['category_id'])) {
            final id? => switch (controller.siteState.categoryFor?.call(
              widget.site,
              id,
            )) {
              final category? => Color(category.colorValue),
              _ => null,
            },
            _ => null,
          },
        ),
    ];
  }

  void _navigate(EventCalendarPage page) {
    if (page == _page) return;
    final oldRange = _page.days(firstDay: _firstDay);
    setState(() {
      _viewSelected = _viewSelected || page.view != _page.view;
      _page = page;
    });
    if (oldRange != page.days(firstDay: _firstDay)) unawaited(_load());
    widget.navigation.rememberDirectory(mine: widget.mine, page: page);
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final controller = widget.controller;
    final site = widget.site;
    final mine = widget.mine;
    final days = _page.days(firstDay: _firstDay);
    final location = _location;
    DateTime inCalendar(DateTime day) =>
        tz.TZDateTime(location, day.year, day.month, day.day);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = <PostEvent>[];
      var after = days.start;
      // The endpoint caps each series at 200 occurrences. Fetch a year in
      // quarters so a daily series reaches December, then deduplicate overlaps.
      while (after.isBefore(days.end)) {
        final quarter = DateTime.utc(after.year, after.month + 3, after.day);
        final before = quarter.isBefore(days.end) ? quarter : days.end;
        rows.addAll(
          await controller.list(
            site,
            mine: mine,
            after: inCalendar(after),
            before: inCalendar(before),
          ),
        );
        if (!mounted || generation != _generation) return;
        after = before;
      }
      setState(() {
        _occurrences = eventDirectoryOccurrences(rows, controller.zones);
        _projectEvents();
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _occurrences = const [];
          _events = const [];
          _error = 'Unable to load events. Try refreshing the calendar.';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EventCalendar(
    page: _page,
    events: _events,
    loading: _loading,
    location: _location,
    firstDay: _firstDay,
    display: _settings.calendarDisplay,
    clock: widget.controller.api.clock,
    mine: widget.mine,
    onMineChanged:
        widget.controller.accounts.isConnected(widget.site) || widget.mine
        ? (mine) => widget.navigation.openDirectory(
            mine: mine,
            page: _page,
            replace: true,
          )
        : null,
    onViewSelected: () => _viewSelected = true,
    onPageChanged: _navigate,
    onOpen: (entry) => widget.navigation.openEvent(widget.site, entry.event),
    status: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: Text(_error!)),
                  DButton(
                    variant: DButtonVariant.outline,
                    onPressed: _load,
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        if (!_loading && _error == null && _events.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'No events in this period.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    ),
  );
}
