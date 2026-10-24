import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:timezone/timezone.dart' as tz;

import 'event_calendar_data.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_time.dart';
import 'topic_calendar_data.dart';

typedef _DirectoryQuery = ({
  DateTimeRange days,
  String timezone,
  tz.Location location,
  int firstDay,
  int accountRevision,
  int directoryRevision,
  int foregroundRevision,
});

final class EventDirectorySession extends ChangeNotifier {
  EventDirectorySession({
    required this.controller,
    required this.site,
    required this.mine,
    required this._page,
  }) {
    _query = _capture();
    _settings = controller.settings(site);
    controller.addListener(_changed);
    unawaited(refresh());
  }

  final EventController controller;
  final String site;
  final bool mine;
  EventCalendarPage _page;
  late _DirectoryQuery _query;
  late EventSettings _settings;
  List<PostEvent> _occurrences = const [];
  bool _loading = true;
  bool _failed = false;
  bool _disposed = false;
  int _generation = 0;

  EventSettings get settings => _settings;
  List<PostEvent> get occurrences => _occurrences;
  bool get loading => _loading;
  bool get failed => _failed;

  String get timezone => _query.timezone;
  tz.Location get location => _query.location;
  int get firstDay => _query.firstDay;

  _DirectoryQuery _capture() {
    final timezone = controller.zones.readerTimezone(
      controller.accountTimezone(site),
    );
    final firstDay =
        controller.siteState
            .siteConfigFor(site)
            .plugins
            .get(topicCalendarSettingsKey)
            ?.firstDay ??
        1;
    return (
      days: _page.days(firstDay: firstDay),
      timezone: timezone,
      location: controller.zones.location(timezone)!,
      firstDay: firstDay,
      accountRevision: controller.accountRevision(site),
      directoryRevision: controller.directoryRevision(site),
      foregroundRevision: controller.foregroundRevision,
    );
  }

  void _changed() => show(_page);

  void show(EventCalendarPage page) {
    _page = page;
    final next = _capture();
    final settingsChanged = _settings != controller.settings(site);
    _settings = controller.settings(site);
    final contextChanged =
        next.timezone != _query.timezone ||
        next.firstDay != _query.firstDay ||
        next.accountRevision != _query.accountRevision ||
        next.foregroundRevision != _query.foregroundRevision;
    final queryChanged = next != _query;
    _query = next;
    if (queryChanged) {
      if (contextChanged) _occurrences = const [];
      unawaited(refresh());
    } else if (settingsChanged) {
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    final query = _query;
    DateTime inCalendar(DateTime day) =>
        tz.TZDateTime(query.location, day.year, day.month, day.day);
    _loading = true;
    _failed = false;
    notifyListeners();
    try {
      final rows = <PostEvent>[];
      var after = query.days.start;
      // Each series is capped at 200 occurrences by the endpoint.
      while (after.isBefore(query.days.end)) {
        final quarter = DateTime.utc(after.year, after.month + 3, after.day);
        final before = quarter.isBefore(query.days.end)
            ? quarter
            : query.days.end;
        rows.addAll(
          await controller.list(
            site,
            mine: mine,
            after: inCalendar(after),
            before: inCalendar(before),
          ),
        );
        if (_disposed || generation != _generation) return;
        after = before;
      }
      _occurrences = eventDirectoryOccurrences(rows, controller.zones);
      _loading = false;
      notifyListeners();
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _occurrences = const [];
      _failed = true;
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    controller.removeListener(_changed);
    super.dispose();
  }
}

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
