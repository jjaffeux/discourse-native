import 'dart:async';

import 'package:flutter/material.dart';

import '../../plugin_api/timezone_host.dart';
import '../../shell/external_link.dart';
import '../../shell/site_url.dart';
import '../../theme/d_button.dart';
import 'event_card.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_export.dart';
import 'event_navigation.dart';
import 'event_time.dart';

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
    // Decode until the view is full, without copying the recurrence array.
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
    if (result.length == 200) break;
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
  });
  final String site;
  final bool mine;
  final EventController controller;
  final EventNavigation navigation;
  @override
  State<EventDirectory> createState() => _EventDirectoryState();
}

class _EventDirectoryState extends State<EventDirectory> {
  final _search = TextEditingController();
  List<PostEvent> _events = const [];
  String? _error;
  int _generation = 0;
  int _accountRevision = 0;
  int _foregroundRevision = 0;
  bool _loading = true;
  EventExportOperation? _exportOperation;
  bool get _exporting => _exportOperation?.isCurrent ?? false;
  @override
  void initState() {
    super.initState();
    _accountRevision = widget.controller.accountRevision(widget.site);
    _foregroundRevision = widget.controller.foregroundRevision;
    widget.controller.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    final revision = widget.controller.accountRevision(widget.site);
    final foreground = widget.controller.foregroundRevision;
    final accountChanged = _accountRevision != revision;
    final resumed = _foregroundRevision != foreground;
    _accountRevision = revision;
    _foregroundRevision = foreground;
    // Rebuild for timezone changes even when the server records are unchanged.
    setState(() {
      if (accountChanged) _events = const [];
    });
    if (accountChanged || resumed) unawaited(_load());
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
      _events = const [];
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.controller.list(
        widget.site,
        mine: widget.mine,
        search: _search.text.trim(),
      );
      if (mounted && generation == _generation) {
        setState(() {
          _events = eventDirectoryOccurrences(rows, widget.controller.zones);
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _events = const [];
          _error = eventError(error, reading: true);
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

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DButton(
                  label: Text(
                    widget.mine ? 'All upcoming events' : 'My events',
                  ),
                  onPressed:
                      widget.controller.accounts.isConnected(widget.site) ||
                          widget.mine
                      ? () =>
                            widget.navigation.openDirectory(mine: !widget.mine)
                      : null,
                ),
                DButton(
                  label: const Text('Refresh'),
                  onPressed: _loading ? null : _load,
                ),
                DButton(
                  label: const Text('Export calendar'),
                  loading: _exporting,
                  onPressed: _exporting ? null : _export,
                ),
                DButton(
                  label: const Text('Calendar view on web'),
                  onPressed: () => unawaited(
                    openExternalLink(
                      resolveSitePath(
                        widget.site,
                        'upcoming-events${widget.mine ? '/mine' : ''}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            TextField(
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
            if (_error != null) Text(_error!),
            if (_loading) const LinearProgressIndicator(),
          ],
        ),
      ),
      Expanded(
        child: _events.isEmpty && !_loading
            ? Center(
                child: Text(
                  _error == null
                      ? 'No upcoming events.'
                      : 'Refresh to try again.',
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: _events.length + 1,
                itemBuilder: (context, index) {
                  if (index == _events.length) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Showing up to 200 upcoming occurrences. Open an event to respond to its current occurrence.',
                      ),
                    );
                  }
                  final event = _events[index];
                  return EventCard(
                    key: ValueKey((widget.site, event.id, event.startsAt)),
                    event: event,
                    siteUrl: widget.site,
                    zones: widget.controller.zones,
                    accountTimezone: widget.controller.accountTimezone(
                      widget.site,
                    ),
                    onOpen: () =>
                        widget.navigation.openEvent(widget.site, event),
                    onWeb: () => unawaited(
                      widget.navigation.openWeb(widget.site, event),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}
