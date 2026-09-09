import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../shell/adaptive_dialog_action.dart';
import '../../shell/open_link.dart';
import '../../shell/site_url.dart';
import 'event_card.dart' show eventResponseLabel;
import 'event_controller.dart';
import 'event_data.dart';

Future<void> showEventParticipants(
  BuildContext context,
  EventHandle source,
) async {
  final event = source.event;
  if (event == null || !source.authoritative) return;
  final handle = source.controller.acquire(source.site, event);
  try {
    await showDiscourseDialog<void>(
      context: context,
      builder: (_) => _Participants(handle: handle),
    );
  } finally {
    handle.dispose();
  }
}

class _Participants extends StatefulWidget {
  const _Participants({required this.handle});
  final EventHandle handle;
  @override
  State<_Participants> createState() => _ParticipantsState();
}

class _ParticipantsState extends State<_Participants> {
  final _search = TextEditingController();
  List<EventInvitee>? _rows;
  String? _error;
  String? _type;
  int _generation = 0;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    widget.handle.controller.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (!widget.handle.authoritative ||
        widget.handle.event?.displayInvitees != true) {
      _generation++;
      setState(() {
        _rows = null;
        _loading = false;
        _error = 'Participant details are no longer available.';
      });
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.handle.controller.participants(
        widget.handle,
        filter: _search.text.trim(),
        type: _type,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _rows = null;
          _error = eventError(error, reading: true);
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.handle.controller.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DiscourseAlertDialog(
    title: const Text('Participants'),
    content: SizedBox(
      width: 440,
      height: MediaQuery.sizeOf(context).height * .55,
      child: Column(
        children: [
          TextField(
            style: Theme.of(context).textTheme.bodyMedium,
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Search participants',
              suffixIcon: DTooltip(
                message: 'Search',
                labelTrigger: true,
                child: IconButton(
                  tooltip: '',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            onSubmitted: (_) => _load(),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final type in <String?>[null, ...eventResponseStatuses])
                ChoiceChip(
                  label: Text(type == null ? 'All' : eventResponseLabel(type)),
                  selected: _type == type,
                  onSelected: (_) {
                    _type = type;
                    unawaited(_load());
                  },
                ),
            ],
          ),
          if (_loading) const DProgress(semanticsLabel: 'Loading participants'),
          if (_error != null) Text(_error!),
          Expanded(
            child: ListView(
              children: [
                for (final invitee in _rows ?? <EventInvitee>[])
                  ListTile(
                    title: Text(invitee.user.name ?? invitee.user.username),
                    subtitle: Text('@${invitee.user.username}'),
                    trailing: Text(
                      '${eventResponseLabel(invitee.status)}${invitee.recurring ? ' ↻' : ''}',
                    ),
                    onTap: () => unawaited(
                      openLink(
                        context,
                        resolveSitePath(
                          widget.handle.site,
                          'u/${Uri.encodeComponent(invitee.user.username)}',
                        ),
                        siteUrl: widget.handle.site,
                      ),
                    ),
                  ),
                if (_rows?.isEmpty == true)
                  const ListTile(
                    title: Text('No participants match this search.'),
                  ),
              ],
            ),
          ),
          if ((_rows?.length ?? 0) >= 200)
            const Text('Showing up to 200 people. Search to narrow the list.'),
        ],
      ),
    ),
    actions: [
      DButton(
        label: const Text('Done'),
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}

Future<void> showEventInvitations(
  BuildContext context,
  EventHandle source,
) async {
  final event = source.event;
  if (event == null || !event.canManage || !source.authoritative) return;
  final handle = source.controller.acquire(source.site, event);
  try {
    await showDiscourseDialog<void>(
      context: context,
      builder: (_) => _Invitations(handle: handle),
    );
  } finally {
    handle.dispose();
  }
}

class _Invitations extends StatefulWidget {
  const _Invitations({required this.handle});
  final EventHandle handle;
  @override
  State<_Invitations> createState() => _InvitationsState();
}

class _InvitationsState extends State<_Invitations> {
  final _names = TextEditingController();
  String? _error;
  bool _sending = false;
  Future<void> _send() async {
    final names = _names.text
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (names.isEmpty || _sending) return;
    if (!widget.handle.authoritative ||
        widget.handle.event?.canManage != true) {
      setState(() => _error = 'You can no longer manage this event.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final sent = await widget.handle.invite(names);
    if (!mounted) return;
    if (sent) {
      Navigator.pop(context);
    } else {
      setState(() {
        _sending = false;
        _error = widget.handle.error ?? 'Unable to send invitations.';
      });
    }
  }

  @override
  void dispose() {
    _names.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DiscourseAlertDialog(
    title: const Text('Invite people'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Send event notifications to these usernames. For private events, access is still determined by the allowed groups.',
          ),
          TextField(
            style: Theme.of(context).textTheme.bodyMedium,
            controller: _names,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Usernames, separated by commas',
            ),
            onSubmitted: (_) => _send(),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      DButton(
        label: const Text('Send invitations'),
        loading: _sending,
        onPressed: _sending ? null : _send,
        variant: DButtonVariant.primary,
      ),
      DButton(
        label: const Text('Cancel'),
        onPressed: _sending ? null : () => Navigator.pop(context),
      ),
    ],
  );
}
