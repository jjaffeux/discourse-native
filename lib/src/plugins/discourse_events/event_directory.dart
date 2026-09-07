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
  final result = <PostEvent>[];
  for (final event in events) {
    final occurrences = event.fields['occurrences'];
    if (occurrences is List) {
      for (final raw in occurrences) {
        final fields = eventObject(raw);
        if (eventText(fields?['starts_at']) == null) continue;
        result.add(
          PostEvent.decode({
            ...event.fields,
            ...fields!,
            'should_display_invitees': false,
            'sample_invitees': null,
            'stats': null,
            'watching_invitee': null,
            'can_update_attendance': false,
          }, topicId: event.topicId)!,
        );
      }
    } else if (event.startsAt != null) {
      result.add(event);
    }
  }
  DateTime? instant(PostEvent event) => eventDate(
    event.startsAt,
    zones: zones,
    timezone: event.timezone,
    allDay: event.allDay,
    showLocalTime: event.showLocalTime,
  );
  result.sort((a, b) {
    final first = instant(a);
    final second = instant(b);
    return first != null && second != null
        ? first.compareTo(second)
        : a.startsAt!.compareTo(b.startsAt!);
  });
  final seen = <(int, String?)>{};
  return List.unmodifiable(
    result.where((event) => seen.add((event.id, event.startsAt))).take(200),
  );
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
  bool _exporting = false;
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
    setState(() => _exporting = true);
    try {
      final calendar = await eventCalendar(
        widget.controller,
        widget.site,
        mine: widget.mine,
      );
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await saveEventCalendar(
        calendar,
        filename: widget.mine ? 'my-events.ics' : 'upcoming-events.ics',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (error) {
      if (mounted) setState(() => _error = eventError(error, reading: true));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void dispose() {
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
