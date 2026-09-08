import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:intl/intl.dart';

import '../../plugin_api/core_plugin_host.dart';
import '../../shell/avatar_image.dart';
import '../../shell/cooked_html.dart';
import '../../shell/open_link.dart';
import '../../shell/site_image.dart';
import '../../shell/site_url.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_export.dart';
import 'event_navigation.dart';
import 'event_participants.dart';
import 'event_time.dart';

/// Rendering is independently testable; no network or account state is read
/// here. Only a hydrated, authorized owner supplies interactive callbacks.
class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.siteUrl,
    required this.zones,
    this.accountTimezone,
    this.settings = const EventSettings(),
    this.pending = false,
    this.error,
    this.onRespond,
    this.onWithdraw,
    this.onParticipants,
    this.onConnect,
    this.onOpen,
    this.onEdit,
    this.onInvite,
    this.onExport,
    this.onWeb,
    this.onRetry,
  });
  final PostEvent event;
  final String siteUrl;
  final PluginTimezoneHost zones;
  final String? accountTimezone;
  final EventSettings settings;
  final bool pending;
  final String? error;
  final void Function(String status, bool recurring)? onRespond;
  final VoidCallback? onWithdraw;
  final VoidCallback? onParticipants;
  final VoidCallback? onConnect;
  final VoidCallback? onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onInvite;
  final VoidCallback? onExport;
  final VoidCallback? onWeb;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = eventDate(
      event.startsAt,
      zones: zones,
      timezone: event.timezone,
      accountTimezone: accountTimezone,
      allDay: event.allDay,
      showLocalTime: event.showLocalTime,
    );
    final selected = event.watching?.status;
    final recurrence = eventRecurrenceLabel(event.recurrence);
    final creator = event.creator;
    final description = event.text('description_html');
    final url = event.text('url');
    final location = event.text('location_html') ?? event.text('location');
    final stats = event.stats;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eventText(eventObject(event.fields['image_upload'])?['url'])
                case final image?)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SiteImage(
                    url: image,
                    siteUrl: siteUrl,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    semanticLabel: '${event.title} cover',
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (date != null) ...[
                  Container(
                    width: 58,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        Text(
                          DateFormat.MMM().format(date).toUpperCase(),
                          style: theme.textTheme.labelSmall,
                        ),
                        Text(
                          '${date.day}',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: onOpen,
                        child: Text(
                          event.title,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            event.private
                                ? 'Private'
                                : event.public
                                ? 'Public'
                                : 'Event',
                          ),
                          if (creator != null) ...[
                            const Text('· Created by'),
                            _Avatar(user: creator, site: siteUrl, size: 24),
                            Text(creator.name ?? creator.username),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if ([
                  onEdit,
                  onInvite,
                  onExport,
                  onWeb,
                  onWithdraw,
                ].any((callback) => callback != null))
                  DTooltip(
                    message: 'Event actions',
                    labelTrigger: true,
                    child: PopupMenuButton<VoidCallback>(
                      tooltip: '',
                      onSelected: (callback) => callback(),
                      itemBuilder: (_) => [
                        if (onEdit != null)
                          PopupMenuItem(
                            value: onEdit,
                            child: const Text('Edit event'),
                          ),
                        if (onInvite != null)
                          PopupMenuItem(
                            value: onInvite,
                            child: const Text('Invite people'),
                          ),
                        if (onWithdraw != null)
                          PopupMenuItem(
                            value: onWithdraw,
                            child: const Text('Remove my response'),
                          ),
                        if (onExport != null)
                          PopupMenuItem(
                            value: onExport,
                            child: const Text('Export calendar'),
                          ),
                        if (onWeb != null)
                          PopupMenuItem(
                            value: onWeb,
                            child: const Text('Open event on web'),
                          ),
                        if (onWeb != null && event.canManage)
                          PopupMenuItem(
                            value: onWeb,
                            child: const Text(
                              'Bulk invitations and reports on web',
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _Detail(
              icon: Icons.schedule,
              child: Text(
                eventDateLabel(event, zones, accountTimezone: accountTimezone),
              ),
            ),
            if (recurrence != null)
              _Detail(icon: Icons.repeat, child: Text(recurrence)),
            if (location != null)
              _Detail(
                icon: Icons.place_outlined,
                child: CookedHtml(
                  html: location,
                  siteUrl: siteUrl,
                  compactParagraphs: true,
                ),
              ),
            if (url != null && !event.flag('url_restates_location'))
              _Detail(
                icon: Icons.link,
                child: InkWell(
                  onTap: () => unawaited(
                    openLink(context, eventLinkUrl(url), siteUrl: siteUrl),
                  ),
                  child: Text(
                    url,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            if (description != null && description.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: CookedHtml(
                  html: description,
                  siteUrl: siteUrl,
                  compactParagraphs: true,
                ),
              )
            else if (event.text('description') case final text?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(text),
              ),
            if (eventObject(event.fields['custom_fields']) case final fields?)
              for (final entry in fields.entries)
                if (entry.value is String && (entry.value as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('${entry.key}: ${entry.value}'),
                  ),
            if (event.displayInvitees && !event.flag('minimal'))
              _Detail(
                icon: Icons.people_outline,
                child: InkWell(
                  onTap: pending ? null : onParticipants,
                  child: Semantics(
                    button: onParticipants != null,
                    label: 'View participants',
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final invitee in event.sampleInvitees)
                          _Avatar(user: invitee.user, site: siteUrl, size: 30),
                        if (stats?['going'] case final int count)
                          Text('$count going'),
                        if (stats?['interested'] case final int count)
                          Text('· $count interested'),
                        if (event.sampleInvitees.isEmpty && stats == null)
                          const Text('Participants'),
                      ],
                    ),
                  ),
                ),
              ),
            if (event.fields['channel']
                case final Map<Object?, Object?> channel)
              if (eventInt(channel['id']) case final id?)
                _Detail(
                  icon: Icons.chat_bubble_outline,
                  child: DButton(
                    onPressed: () => unawaited(
                      openLink(
                        context,
                        resolveSitePath(siteUrl, 'chat/c/-/$id'),
                        siteUrl: siteUrl,
                      ),
                    ),
                    variant: DButtonVariant.link,
                    label: const Text('Open event chat'),
                  ),
                ),
            if (event.text('livestream_url') case final link?)
              _Detail(
                icon: Icons.videocam_outlined,
                child: DButton(
                  onPressed: () =>
                      unawaited(openLink(context, link, siteUrl: siteUrl)),
                  variant: DButtonVariant.link,
                  label: const Text('Open livestream'),
                ),
              ),
            if (event.flag('is_closed') ||
                event.flag('is_expired') ||
                event.flag('at_capacity'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  event.flag('is_closed')
                      ? 'This event is closed.'
                      : event.flag('is_expired')
                      ? 'This event has ended.'
                      : 'This event is at capacity.',
                ),
              ),
            if (onConnect != null &&
                !event.flag('is_expired') &&
                !event.flag('is_closed'))
              DButton(
                label: const Text('Connect to respond'),
                onPressed: onConnect,
              ),
            if (onRespond != null && event.canRespond) ...[
              const DSeparator(space: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in settings.buttons)
                    if (!event.flag('minimal') || status == 'interested')
                      if (status == 'going' && event.recurring)
                        DTooltip(
                          message: 'Choose recurring attendance',
                          labelTrigger: true,
                          child: PopupMenuButton<VoidCallback>(
                            tooltip: '',
                            enabled: !pending && event.canChoose(status),
                            // Menu values retain the callback from opening,
                            // even if the button's widget is replaced meanwhile.
                            onSelected: (callback) => callback(),
                            itemBuilder: (_) => [
                              CheckedPopupMenuItem(
                                value: () => onRespond!(status, false),
                                checked:
                                    selected == 'going' &&
                                    event.watching?.recurring == false,
                                child: const Text('This occurrence only'),
                              ),
                              CheckedPopupMenuItem(
                                value: () => onRespond!(status, true),
                                checked:
                                    selected == 'going' &&
                                    event.watching?.recurring == true,
                                child: const Text('Every occurrence'),
                              ),
                            ],
                            child: IgnorePointer(
                              child: _ResponseButton(
                                status: status,
                                selected: selected == status,
                                enabled: !pending && event.canChoose(status),
                                recurring: true,
                                onTap: () {},
                              ),
                            ),
                          ),
                        )
                      else
                        _ResponseButton(
                          status: status,
                          selected: selected == status,
                          enabled: !pending && event.canChoose(status),
                          onTap: () => onRespond!(status, false),
                        ),
                ],
              ),
            ],
            if (pending)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      if (onRetry != null)
                        DButton(
                          onPressed: onRetry,
                          variant: DButtonVariant.link,
                          label: const Text('Refresh event'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResponseButton extends StatelessWidget {
  const _ResponseButton({
    required this.status,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.recurring = false,
  });
  final String status;
  final bool selected;
  final bool enabled;
  final bool recurring;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: DButton(
      label: Text('${eventResponseLabel(status)}${recurring ? ' ▾' : ''}'),
      icon: Icon(switch (status) {
        'going' => Icons.check,
        'interested' => Icons.star,
        _ => Icons.close,
      }, size: 18),
      variant: selected ? DButtonVariant.primary : DButtonVariant.standard,
      onPressed: enabled ? onTap : null,
    ),
  );
}

String eventResponseLabel(String? status) => switch (status) {
  'going' => 'Going',
  'interested' => 'Interested',
  'not_going' => 'Not going',
  _ => 'Invited',
};

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.child});
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.site, required this.size});
  final EventPerson user;
  final String site;
  final double size;
  @override
  Widget build(BuildContext context) => DTooltip(
    message: user.username,
    child: DAvatar.frame(
      child: SizedBox.square(
        dimension: size,
        child: AvatarImage(
          url: user.avatarUrl(site),
          size: size,
          fallback: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(
              child: Text(user.username.characters.first.toUpperCase()),
            ),
          ),
        ),
      ),
    ),
  );
}

class PostEventCard extends StatefulWidget {
  const PostEventCard({
    super.key,
    required this.site,
    required this.event,
    required this.controller,
    required this.navigation,
  });
  final String site;
  final PostEvent event;
  final EventController controller;
  final EventNavigation navigation;
  @override
  State<PostEventCard> createState() => _PostEventCardState();
}

class _PostEventCardState extends State<PostEventCard> {
  late EventHandle _handle;
  EventExportOperation? _exportOperation;
  bool get _exporting => _exportOperation?.isCurrent ?? false;
  @override
  void initState() {
    super.initState();
    _handle = widget.controller.acquire(widget.site, widget.event);
  }

  @override
  void didUpdateWidget(PostEventCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        oldWidget.event.id != widget.event.id ||
        oldWidget.controller != widget.controller) {
      _exportOperation?.cancel();
      _handle.dispose();
      _handle = widget.controller.acquire(widget.site, widget.event);
    } else if (!_handle.isCurrent &&
        !identical(oldWidget.event, widget.event)) {
      // A fresh snapshot may equal the previous account's seed. Replace only
      // this card's handle; dialogs and pending requests keep their old lifetime.
      _exportOperation?.cancel();
      _handle.dispose();
      _handle = widget.controller.acquire(
        widget.site,
        widget.event,
        useSeed: false,
      );
    } else {
      _handle.updateSource(widget.event);
    }
  }

  @override
  void dispose() {
    _exportOperation?.cancel();
    _handle.dispose();
    super.dispose();
  }

  Future<void> _export(EventHandle handle, int accountRevision) async {
    if (!mounted ||
        !identical(handle, _handle) ||
        !handle.authoritative ||
        handle.pending ||
        widget.controller.accountRevision(widget.site) != accountRevision ||
        _exporting) {
      return;
    }
    final controller = widget.controller;
    final site = widget.site;
    final eventId = widget.event.id;
    final operation = EventExportOperation(controller, site);
    setState(() => _exportOperation = operation);
    try {
      final calendar = await eventCalendar(
        controller,
        site,
        eventId: eventId,
        isCurrent: () => operation.isCurrent,
      );
      if (!mounted || !operation.isCurrent) return;
      final box = context.findRenderObject() as RenderBox?;
      await saveEventCalendar(
        calendar,
        filename: 'event-$eventId.ics',
        isCurrent: () => operation.isCurrent,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (error) {
      if (mounted && operation.isCurrent) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(eventError(error, reading: true))),
        );
      }
    } finally {
      if (mounted && identical(_exportOperation, operation)) {
        setState(() => _exportOperation = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final handle = _handle;
      final event = handle.event;
      if (event == null) {
        return EventUnavailableCard(
          error: handle.error,
          loading: handle.loading,
          onRetry: () => unawaited(handle.refresh()),
          onWeb: () =>
              unawaited(widget.navigation.openWeb(widget.site, widget.event)),
        );
      }
      final available = handle.authoritative && !handle.pending;
      final accountRevision = widget.controller.accountRevision(widget.site);
      bool currentAccount() =>
          handle.controller.isAccountCurrent(handle.site, accountRevision);
      return EventCard(
        event: event,
        siteUrl: widget.site,
        zones: widget.controller.zones,
        accountTimezone: widget.controller.accountTimezone(widget.site),
        settings: widget.controller.settings(widget.site),
        pending: handle.pending,
        error: handle.error,
        onRespond: handle.authoritative
            ? (status, recurring) {
                if (currentAccount()) {
                  unawaited(handle.respond(status, recurring: recurring));
                }
              }
            : null,
        onWithdraw:
            available &&
                event.public &&
                event.canRespond &&
                event.watching?.id != null
            ? () {
                if (currentAccount()) unawaited(handle.withdraw());
              }
            : null,
        onParticipants: available && event.displayInvitees
            ? () => showEventParticipants(context, handle)
            : null,
        onConnect: !widget.controller.accounts.isConnected(widget.site)
            ? () => unawaited(widget.controller.accounts.connect(widget.site))
            : null,
        onEdit: available && event.canManage
            ? () => widget.navigation.edit(widget.site, event)
            : null,
        onInvite: available && event.canManage
            ? () => showEventInvitations(context, handle)
            : null,
        onExport: available && !_exporting
            ? () => unawaited(_export(handle, accountRevision))
            : null,
        onOpen: () => widget.navigation.openEvent(widget.site, event),
        onWeb: () => unawaited(widget.navigation.openWeb(widget.site, event)),
        onRetry: () => unawaited(handle.refresh()),
      );
    },
  );
}

class EventUnavailableCard extends StatelessWidget {
  const EventUnavailableCard({
    super.key,
    this.error,
    this.loading = false,
    this.onRetry,
    this.onWeb,
  });
  final String? error;
  final bool loading;
  final VoidCallback? onRetry;
  final VoidCallback? onWeb;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error ?? 'Event details are unavailable.'),
          if (loading) const LinearProgressIndicator(),
          Wrap(
            spacing: 8,
            children: [
              if (onRetry != null)
                DButton(
                  onPressed: onRetry,
                  variant: DButtonVariant.link,
                  label: const Text('Refresh event'),
                ),
              if (onWeb != null)
                DButton(
                  onPressed: onWeb,
                  variant: DButtonVariant.link,
                  label: const Text('Open event on web'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Cooked HTML alone cannot grant attendance access (quotes, chat, previews).
class EventCookedFallback extends StatelessWidget {
  EventCookedFallback({super.key, required dom.Element element})
    : title = element.attributes['data-name'] ?? 'Event',
      start = element.attributes['data-start'],
      description = element.text.trim();
  final String title;
  final String? start;
  final String description;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DText(title, variant: DTextVariant.large, headingLevel: 2),
          if (start != null) Text(start!),
          if (description.isNotEmpty) Text(description),
        ],
      ),
    ),
  );
}
