import 'package:flutter/widgets.dart';

import '../../foundation/timezone_environment.dart';
import '../../plugin_api/timezone_host.dart';
import '../../plugins/discourse_events/event_card.dart';
import '../../plugins/discourse_events/event_data.dart';

enum OneboxEventState {
  upcoming('Upcoming'),
  going('Going'),
  closed('Closed'),
  pending('Saving'),
  error('Error');

  const OneboxEventState(this.label);
  final String label;
}

class OneboxEventSample extends StatefulWidget {
  const OneboxEventSample({super.key, required this.state});

  final OneboxEventState state;

  @override
  State<OneboxEventSample> createState() => _OneboxEventSampleState();
}

class _OneboxEventSampleState extends State<OneboxEventSample> {
  late String? _response = widget.state == OneboxEventState.going
      ? 'going'
      : null;
  bool _retried = false;

  @override
  Widget build(BuildContext context) {
    final environment = TimezoneEnvironment.instance;
    return EventCard(
      siteUrl: 'https://meta.discourse.org',
      zones: PluginTimezoneHost(
        readerTimezone: environment.readerTimezone,
        location: environment.location,
        timezoneNames: () => environment.timezoneNames,
        changes: environment,
      ),
      accountTimezone: 'Europe/Paris',
      event: PostEvent.decode({
        'id': 42,
        'name': 'Community meetup',
        'starts_at': '2026-10-15T18:00:00+02:00',
        'ends_at': '2026-10-15T19:00:00+02:00',
        'timezone': 'Europe/Paris',
        'status': 'public',
        'is_public': true,
        'is_closed': widget.state == OneboxEventState.closed,
        'can_update_attendance': true,
        'should_display_invitees': true,
        'stats': {'going': 12, 'interested': 4},
        'description': 'Meet the community and share what you are working on.',
        'location': 'Paris, France',
        if (_response != null)
          'watching_invitee': {
            'id': 1,
            'status': _response,
            'user': {'id': 1, 'username': 'preview'},
          },
      })!,
      pending: widget.state == OneboxEventState.pending,
      error: widget.state == OneboxEventState.error && !_retried
          ? 'Your attendance could not be saved. Please try again.'
          : null,
      onRespond: (status, _) => setState(() => _response = status),
      onWithdraw: _response == null
          ? null
          : () => setState(() => _response = null),
      onRetry: () => setState(() => _retried = true),
    );
  }
}
