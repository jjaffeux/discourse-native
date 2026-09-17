import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../shell/adaptive_dialog_action.dart';
import '../../shell/avatar_image.dart';
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
  if (event == null || !source.authoritative || !event.displayInvitees) return;
  final handle = source.controller.acquire(source.site, event);
  try {
    await showDDialog<void>(
      context: context,
      builder: (_, controller) =>
          _Participants(handle: handle, onClose: controller.close),
    );
  } finally {
    handle.dispose();
  }
}

class _Participants extends StatefulWidget {
  const _Participants({required this.handle, required this.onClose});
  final EventHandle handle;
  final VoidCallback onClose;
  @override
  State<_Participants> createState() => _ParticipantsState();
}

class _ParticipantsState extends State<_Participants> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  List<EventInvitee>? _rows;
  String? _error;
  String? _type;
  int _generation = 0;
  bool _loading = false;

  bool get _available =>
      widget.handle.isCurrent &&
      widget.handle.authoritative &&
      widget.handle.event?.displayInvitees == true;

  @override
  void initState() {
    super.initState();
    widget.handle.controller.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (!_available) {
      _debounce?.cancel();
      _generation++;
      setState(() {
        _rows = null;
        _loading = false;
        _error = 'Participant details are no longer available.';
      });
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    // Invalidate older responses as soon as the query changes, including the
    // debounce window. Never display the previous filter's roster as current.
    _generation++;
    setState(() {
      _rows = null;
      _loading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  void _clearSearch() {
    _search.clear();
    _searchFocus.requestFocus();
    unawaited(_load());
  }

  void _selectType(String? value) {
    final type = value == 'all' ? null : value;
    if (type == _type) return;
    _type = type;
    unawaited(_load());
  }

  Future<void> _load() async {
    _debounce?.cancel();
    if (!_available) {
      _changed();
      return;
    }
    final generation = ++_generation;
    setState(() {
      _rows = null;
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.handle.controller.participants(
        widget.handle,
        filter: _search.text.trim().replaceFirst(RegExp(r'^@'), ''),
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
    _debounce?.cancel();
    widget.handle.controller.removeListener(_changed);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return DDialogContent(
      maxWidth: 520,
      spacing: 12,
      contentPadding: EdgeInsets.zero,
      closeSemanticLabel: 'Close participants',
      children: [
        const Padding(
          padding: EdgeInsetsDirectional.fromSTEB(16, 4, 44, 4),
          child: DDialogHeader(
            children: [DDialogTitle(child: Text('Participants'))],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DInput(
            controller: _search,
            focusNode: _searchFocus,
            hintText: 'Search participants',
            semanticLabel: 'Search participants',
            enabled: _available,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            prefix: Icon(Icons.search, size: 16, color: tokens.mutedForeground),
            suffix: _search.text.isEmpty
                ? null
                : DButton.iconOnly(
                    onPressed: _available ? _clearSearch : null,
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.small,
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                  ),
            onChanged: _searchChanged,
            onSubmitted: (_) => unawaited(_load()),
          ),
        ),
        DTabs<String>.controlled(
          value: _type ?? 'all',
          enabled: _available,
          onChanged: _selectType,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) => DTabList<String>(
                  activateOnFocus: true,
                  children: [
                    for (final type in ['all', ...eventResponseStatuses])
                      ConstrainedBox(
                        // Equal columns fill the available row. Long/scaled
                        // labels can grow and use the kit's horizontal scroll.
                        constraints: BoxConstraints(
                          minWidth: (constraints.maxWidth - 6) / 4,
                        ),
                        child: DTabTrigger<String>(
                          value: type,
                          child: Text(
                            type == 'all' ? 'All' : eventResponseLabel(type),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            DTabPanel<String>(
              value: _type ?? 'all',
              semanticLabel:
                  'Participants: ${_type == null ? 'All' : eventResponseLabel(_type)}',
              child: SizedBox(
                height: math.min(336, MediaQuery.sizeOf(context).height * .5),
                child: _buildResults(context),
              ),
            ),
          ],
        ),
        if ((_rows?.length ?? 0) >= 200)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Showing up to 200 people. Search to narrow the list.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: tokens.mutedForeground),
            ),
          ),
        DDialogFooter(
          children: [
            SizedBox(
              width: double.infinity,
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _rows == null ? '' : '${_rows!.length} shown',
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: tokens.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DButton(label: const Text('Done'), onPressed: widget.onClose),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: DProgress(semanticsLabel: 'Loading participants'),
        ),
      );
    }
    if (_error != null || _rows?.isEmpty != false) {
      final searching = _search.text.trim().isNotEmpty;
      return Center(
        child: SingleChildScrollView(
          child: DEmpty(
            children: [
              DEmptyHeader(
                children: [
                  DEmptyTitle(
                    _error != null
                        ? 'Unable to load participants'
                        : 'No participants found',
                  ),
                  DEmptyDescription(
                    _error ??
                        (searching
                            ? 'Try another name or username.'
                            : _type != null
                            ? 'Try a different response filter.'
                            : 'No participants to show yet.'),
                  ),
                ],
              ),
              if (_available && (_error != null || searching || _type != null))
                DButton(
                  variant: DButtonVariant.outline,
                  label: Text(
                    _error != null
                        ? 'Try again'
                        : searching
                        ? 'Clear search'
                        : 'Show all participants',
                  ),
                  onPressed: _error != null
                      ? () => unawaited(_load())
                      : searching
                      ? _clearSearch
                      : () => _selectType('all'),
                ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      itemCount: _rows!.length,
      separatorBuilder: (_, _) => const DSeparator(space: 1),
      itemBuilder: (context, index) =>
          _ParticipantRow(invitee: _rows![index], siteUrl: widget.handle.site),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.invitee, required this.siteUrl});
  final EventInvitee invitee;
  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final user = invitee.user;
    final name = user.name?.trim();
    final displayName = name == null || name.isEmpty ? user.username : name;
    final words = displayName.split(RegExp(r'\s+'));
    final initials = [
      words.first.characters.first,
      if (words.length > 1) words.last.characters.first,
    ].join().toUpperCase();
    final tokens = DTokens.of(context);
    return DItem(
      size: DItemSize.xs,
      link: true,
      onPressed: () => unawaited(
        openLink(
          context,
          resolveSitePath(siteUrl, 'u/${Uri.encodeComponent(user.username)}'),
          siteUrl: siteUrl,
        ),
      ),
      children: [
        DItemMedia(
          variant: DItemMediaVariant.avatar,
          child: DAvatar(
            decorative: true,
            child: AvatarImage(
              url: user.avatarUrl(siteUrl),
              size: DAvatarSize.standard.dimension,
              fallback: DAvatarFallback(child: Text(initials)),
            ),
          ),
        ),
        DItemContent(
          children: [
            DItemTitle(maxLines: null, child: Text(displayName)),
            DItemDescription(maxLines: null, child: Text('@${user.username}')),
          ],
        ),
        DefaultTextStyle(
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: tokens.mutedForeground),
          child: Wrap(
            spacing: 5,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                switch (invitee.status) {
                  'going' => Icons.check,
                  'interested' => Icons.star_outline,
                  'not_going' => Icons.close,
                  _ => Icons.mail_outline,
                },
                size: 14,
                color: tokens.mutedForeground,
              ),
              Text(eventResponseLabel(invitee.status)),
              if (invitee.recurring)
                DTooltip(
                  message: 'Every occurrence',
                  child: Icon(
                    Icons.repeat,
                    size: 14,
                    color: tokens.mutedForeground,
                    semanticLabel: 'Every occurrence',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
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
