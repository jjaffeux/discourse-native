import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'event_card.dart' show eventResponseLabel;
import 'event_controller.dart';
import 'event_data.dart';

final RegExp _whitespace = RegExp(r'\s+');

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

  /// Availability as of the last change this sheet handled. Access can return
  /// after a failed re-read or an account refresh; the roster was withdrawn
  /// when it left, so it must be read again rather than left disabled behind
  /// the withdrawal notice with no way to retry.
  bool _wasAvailable = true;

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
    final available = _available;
    final returned = available && !_wasAvailable;
    _wasAvailable = available;
    if (returned) {
      unawaited(_load());
    } else if (!available) {
      _debounce?.cancel();
      _generation++;
      setState(() {
        _rows = null;
        _loading = false;
        _error = appL10n.participantDetailsAreNoLongerAvailable;
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
      closeSemanticLabel: context.l10n.closeParticipants,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 44, 4),
          child: DDialogHeader(
            children: [DDialogTitle(child: Text(context.l10n.participants))],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DInput(
            controller: _search,
            focusNode: _searchFocus,
            hintText: context.l10n.searchParticipants,
            semanticLabel: context.l10n.searchParticipants,
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
                    tooltip: context.l10n.clearSearch,
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
                            type == 'all'
                                ? context.l10n.all
                                : eventResponseLabel(type),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            DTabPanel<String>(
              value: _type ?? 'all',
              semanticLabel: context.l10n.participantsEventparticipants(
                (_type == null).toString(),
                ((!(_type == null)) ? (eventResponseLabel(_type)) : '')
                    .toString(),
              ),
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
              context.l10n.showingUpTo200PeopleSearchToNarrowTheList,
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
                        _rows == null
                            ? ''
                            : context.l10n.shown((_rows!.length).toString()),
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: tokens.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DButton(
                    label: Text(context.l10n.done),
                    onPressed: widget.onClose,
                  ),
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
      return const _ParticipantSkeleton();
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
                        ? context.l10n.unableToLoadParticipants
                        : context.l10n.noParticipantsFound,
                  ),
                  DEmptyDescription(
                    _error ??
                        (searching
                            ? context.l10n.tryAnotherNameOrUsername
                            : _type != null
                            ? context.l10n.tryADifferentResponseFilter
                            : context.l10n.noParticipantsToShowYet),
                  ),
                ],
              ),
              if (_available && (_error != null || searching || _type != null))
                DButton(
                  variant: DButtonVariant.outline,
                  label: Text(
                    _error != null
                        ? context.l10n.tryAgain
                        : searching
                        ? context.l10n.clearSearch
                        : context.l10n.showAllParticipants,
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

class _ParticipantSkeleton extends StatelessWidget {
  const _ParticipantSkeleton();

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: DSkeletonRegion(
        semanticsLabel: context.l10n.loadingParticipants,
        color: skeletonFill(context, on: SkeletonSurface.floating),
        child: Column(
          children: [
            for (var i = 0; i < 6; i++) ...[
              if (i > 0) const DSeparator(space: 1),
              DItem(
                size: DItemSize.xs,
                children: [
                  const DItemMedia(
                    variant: DItemMediaVariant.avatar,
                    child: DAvatar(decorative: true, child: DSkeleton()),
                  ),
                  DItemContent(
                    spacing: 6,
                    children: [
                      DItemTitle(
                        child: DSkeleton(
                          width: 120 + (i % 3) * 24,
                          height: scaler.scale(16),
                        ),
                      ),
                      DItemDescription(
                        child: DSkeleton(width: 90, height: scaler.scale(12)),
                      ),
                    ],
                  ),
                  DSkeleton(width: 44, height: scaler.scale(12)),
                ],
              ),
            ],
          ],
        ),
      ),
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
    final words = displayName.split(_whitespace);
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
                  message: context.l10n.everyOccurrence,
                  child: Icon(
                    Icons.repeat,
                    size: 14,
                    color: tokens.mutedForeground,
                    semanticLabel: context.l10n.everyOccurrence,
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
    // The server matches usernames exactly and reports success when none
    // match, so a mention prefix would invite nobody without an error.
    final names = _names.text
        .split(RegExp(r'[\s,]+'))
        .map((s) => s.replaceFirst(RegExp(r'^@'), ''))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (names.isEmpty || _sending) return;
    if (!widget.handle.authoritative ||
        widget.handle.event?.canManage != true) {
      setState(() => _error = appL10n.youCanNoLongerManageThisEvent);
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
        _error = widget.handle.error ?? appL10n.unableToSendInvitations;
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
    title: Text(context.l10n.invitePeople),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context
                .l10n
                .sendEventNotificationsToTheseUsernamesForPrivateEventsAccessIs,
          ),
          TextField(
            style: Theme.of(context).textTheme.bodyMedium,
            controller: _names,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.l10n.usernamesSeparatedByCommas,
            ),
            onSubmitted: (_) => _send(),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      DButton(
        label: Text(context.l10n.sendInvitations),
        loading: _sending,
        onPressed: _sending ? null : _send,
        variant: DButtonVariant.primary,
      ),
      DButton(
        label: Text(context.l10n.cancel),
        onPressed: _sending ? null : () => Navigator.pop(context),
      ),
    ],
  );
}
