import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../plugin_api/timezone_host.dart';
import '../../shell/external_link.dart';
import '../../shell/site_url.dart';
import '../../theme/d_button.dart';
import 'event_calendar.dart';
import 'event_calendar_data.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_export.dart';
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

class EventDirectory extends StatefulWidget {
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
  State<EventDirectory> createState() => _EventDirectoryState();
}

enum _CalendarAction { refresh, search, export, web }

class _EventDirectoryState extends State<EventDirectory> {
  final _search = TextEditingController();
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
  bool _searchVisible = false;
  EventExportOperation? _exportOperation;
  bool get _exporting => _exportOperation?.isCurrent ?? false;
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
    _page = widget.page ?? _defaultPage();
    _accountRevision = widget.controller.accountRevision(widget.site);
    _foregroundRevision = widget.controller.foregroundRevision;
    widget.controller.addListener(_changed);
    unawaited(_load());
  }

  EventCalendarPage _defaultPage() {
    final today = tz.TZDateTime.from(widget.controller.api.clock(), _location);
    return EventCalendarPage(
      _settings.calendarView,
      DateTime.utc(today.year, today.month, today.day),
    );
  }

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
    if (accountChanged) _exportOperation?.cancel();
    if (accountChanged || resumed || calendarChanged) {
      _occurrences = const [];
      _events = const [];
      unawaited(_load());
    } else if (settingsChanged) {
      setState(_projectEvents);
    }
  }

  @override
  void didUpdateWidget(EventDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.controller != widget.controller;
    if (controllerChanged) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (controllerChanged ||
        oldWidget.site != widget.site ||
        oldWidget.mine != widget.mine) {
      _exportOperation?.cancel();
      _accountRevision = widget.controller.accountRevision(widget.site);
      _foregroundRevision = widget.controller.foregroundRevision;
      _timezone = _readerTimezone;
      _firstDay = _siteFirstDay;
      _settings = widget.controller.settings(widget.site);
      _page =
          widget.page ??
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
      if (widget.page != null) _page = widget.page!;
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
    setState(() => _page = page);
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
            search: _search.text.trim().isEmpty ? null : _search.text.trim(),
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

  Future<void> _export() async {
    if (!mounted || _exporting) return;
    final controller = widget.controller;
    final site = widget.site;
    final mine = widget.mine;
    final operation = EventExportOperation(controller, site);
    setState(() => _exportOperation = operation);
    try {
      final calendar = await eventCalendar(
        controller,
        site,
        mine: mine,
        isCurrent: () => operation.isCurrent,
      );
      if (!mounted || !operation.isCurrent) return;
      final box = context.findRenderObject() as RenderBox?;
      await saveEventCalendar(
        calendar,
        filename: mine ? 'my-events.ics' : 'upcoming-events.ics',
        isCurrent: () => operation.isCurrent,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (error) {
      if (mounted && operation.isCurrent) {
        setState(() => _error = eventError(error, reading: true));
      }
    } finally {
      if (mounted && identical(_exportOperation, operation)) {
        setState(() => _exportOperation = null);
      }
    }
  }

  @override
  void dispose() {
    _exportOperation?.cancel();
    _generation++;
    widget.controller.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _action(_CalendarAction action) {
    switch (action) {
      case _CalendarAction.refresh:
        unawaited(_load());
      case _CalendarAction.search:
        setState(() => _searchVisible = !_searchVisible);
        if (!_searchVisible && _search.text.isNotEmpty) {
          _search.clear();
          unawaited(_load());
        }
      case _CalendarAction.export:
        unawaited(_export());
      case _CalendarAction.web:
        unawaited(
          openExternalLink(
            resolveSitePath(widget.site, _page.webPath(widget.mine)),
          ),
        );
    }
  }

  Widget _actions() {
    final owner = (
      widget.controller,
      widget.site,
      widget.mine,
      _accountRevision,
    );
    VoidCallback guarded(_CalendarAction action) => () {
      if (mounted &&
          owner ==
              (widget.controller, widget.site, widget.mine, _accountRevision)) {
        _action(action);
      }
    };
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Calendar actions',
      onSelected: (callback) => callback(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: guarded(_CalendarAction.refresh),
          child: const Text('Refresh'),
        ),
        CheckedPopupMenuItem(
          value: guarded(_CalendarAction.search),
          checked: _searchVisible,
          child: const Text('Search events'),
        ),
        PopupMenuItem(
          value: guarded(_CalendarAction.export),
          enabled: !_exporting,
          child: Text(_exporting ? 'Exporting calendar…' : 'Export calendar'),
        ),
        PopupMenuItem(
          value: guarded(_CalendarAction.web),
          child: const Text('Open web calendar'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => EventCalendar(
    page: _page,
    events: _events,
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
    onPageChanged: _navigate,
    onOpen: (entry) => widget.navigation.openEvent(widget.site, entry.event),
    actions: _actions(),
    status: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_searchVisible)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              style: Theme.of(context).textTheme.bodyMedium,
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                labelText: 'Search events',
                suffixIcon: IconButton(
                  tooltip: 'Search events',
                  onPressed: _load,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: Text(_error!)),
                  DButton(
                    variant: DButtonVariant.transparentPrimary,
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
        SizedBox(
          height: 2,
          child: _loading ? const LinearProgressIndicator() : null,
        ),
      ],
    ),
  );
}
