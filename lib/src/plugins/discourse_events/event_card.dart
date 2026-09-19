import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:intl/intl.dart';

import '../../plugin_api/core_plugin_host.dart';
import '../../shell/avatar_image.dart';
import '../../shell/cooked_html.dart';
import '../../shell/open_link.dart';
import '../../shell/site_image.dart';
import '../../shell/site_url.dart';
import 'event_controller.dart';
import 'event_cooked_visibility.dart';
import 'event_data.dart';
import 'event_export.dart';
import 'event_navigation.dart';
import 'event_participants.dart';
import 'event_time.dart';

/// Rendering is independently testable; no network or account state is read
/// here. Only a hydrated, authorized owner supplies interactive callbacks.
class EventCard extends StatefulWidget {
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
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  void Function(String, bool)? _openingRespond;
  VoidCallback? _openingWithdraw;

  @override
  Widget build(BuildContext context) {
    final EventCard(
      :event,
      :siteUrl,
      :zones,
      :accountTimezone,
      :settings,
      :pending,
      :error,
      :onRespond,
      :onWithdraw,
      :onParticipants,
      :onConnect,
      :onOpen,
      :onEdit,
      :onInvite,
      :onExport,
      :onWeb,
      :onRetry,
    ) = widget;

    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
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
    final descriptionHtml = event.text('description_html');
    final hasHtmlDescription = descriptionHtml?.trim().isNotEmpty ?? false;
    final description = hasHtmlDescription
        ? descriptionHtml!
        : event.text('description');
    final url = event.text('url');
    final location = event.text('location_html') ?? event.text('location');
    final stats = event.stats;
    final channelId = eventInt(eventObject(event.fields['channel'])?['id']);
    final showParticipants = event.displayInvitees && !event.flag('minimal');
    final title = DefaultTextStyle(
      style: theme.textTheme.titleLarge!.copyWith(color: tokens.foreground),
      softWrap: true,
      child: Text(event.title),
    );
    final responseStatuses = settings.buttons.where(
      (status) => !event.flag('minimal') || status == 'interested',
    );
    final responses =
        onRespond != null && event.canRespond && responseStatuses.isNotEmpty
        ? Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in responseStatuses)
                if (status == 'going' && event.recurring)
                  Builder(
                    builder: (menuContext) {
                      void onSelect(VoidCallback callback) => callback();
                      return Semantics(
                        container: true,
                        explicitChildNodes: true,
                        child: DDropdownMenu(
                          onOpenChange: (open, _) {
                            if (open) _openingRespond = onRespond;
                          },
                          content: DDropdownMenuContent(
                            semanticLabel: 'Choose recurring attendance',
                            width: 280,
                            children: [
                              DDropdownMenuCheckboxItem(
                                checked:
                                    selected == 'going' &&
                                    event.watching?.recurring == false,
                                closeOnSelect: true,
                                onChanged: (_) => onSelect(
                                  () => _openingRespond?.call(status, false),
                                ),
                                child: const Text('This occurrence only'),
                              ),
                              DDropdownMenuCheckboxItem(
                                checked:
                                    selected == 'going' &&
                                    event.watching?.recurring == true,
                                closeOnSelect: true,
                                onChanged: (_) => onSelect(
                                  () => _openingRespond?.call(status, true),
                                ),
                                child: const Text('Every occurrence'),
                              ),
                            ],
                          ),
                          child: Semantics(
                            selected: selected == status,
                            child: DDropdownMenuTrigger(
                              builder: (triggerContext, state) => DButton(
                                label: Text(eventResponseLabel(status)),
                                tooltip: 'Choose recurring attendance',
                                variant: selected == status
                                    ? DButtonVariant.primary
                                    : DButtonVariant.outline,
                                focusNode: state.focusNode,
                                hasPopup: true,
                                expanded: state.open,
                                onPressed: !pending && event.canChoose(status)
                                    ? state.toggle
                                    : null,
                                icon: const Icon(Icons.arrow_drop_down),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                else
                  _ResponseButton(
                    status: status,
                    selected: selected == status,
                    enabled: !pending && event.canChoose(status),
                    onTap: () => onRespond(status, false),
                  ),
            ],
          )
        : null;
    final participantLabel = Wrap(
      spacing: 5,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final invitee in event.sampleInvitees)
          _Avatar(user: invitee.user, site: siteUrl, size: 24),
        if (stats?['going'] case final int count) Text('$count going'),
        if (stats?['interested'] case final int count)
          Text(
            '· $count interested',
            style: TextStyle(color: tokens.mutedForeground),
          ),
        if (event.sampleInvitees.isEmpty && stats == null)
          const Text('Participants'),
      ],
    );
    final participants = onParticipants == null
        ? _Detail(icon: Icons.people_outline, child: participantLabel)
        : DButton(
            onPressed: pending ? null : onParticipants,
            variant: DButtonVariant.inline,
            alignment: AlignmentDirectional.centerStart,
            semanticLabel: [
              'View participants',
              if (stats?['going'] case final int count) '$count going',
              if (stats?['interested'] case final int count)
                '$count interested',
            ].join(', '),
            tooltip: 'View participants',
            icon: const Icon(Icons.people_outline),
            label: participantLabel,
          );
    final chat = channelId == null
        ? null
        : DButton(
            onPressed: () => unawaited(
              openLink(
                context,
                resolveSitePath(siteUrl, 'chat/c/-/$channelId'),
                siteUrl: siteUrl,
              ),
            ),
            variant: DButtonVariant.inline,
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Open event chat'),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DCard(
        footer: responses == null ? null : DCardFooter(child: responses),
        children: [
          DCardContent(
            joinNext: responses != null,
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall!.copyWith(
                color: tokens.foreground,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (eventText(
                        eventObject(event.fields['image_upload'])?['url'],
                      )
                      case final image?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ClipRRect(
                        borderRadius: tokens.borderRadius,
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
                        SizedBox(
                          width: MediaQuery.textScalerOf(context).scale(44),
                          child: DCard(
                            spacing: 0,
                            child: ColoredBox(
                              color: tokens.muted.withValues(alpha: .5),
                              child: SizedBox(
                                width: 44,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        DateFormat.MMM()
                                            .format(date)
                                            .toUpperCase(),
                                        style: theme.textTheme.labelSmall!
                                            .copyWith(
                                              color: tokens.mutedForeground,
                                            ),
                                      ),
                                      Text(
                                        '${date.day}',
                                        style: theme.textTheme.headlineSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (onOpen == null)
                              title
                            else
                              DButton(
                                label: title,
                                isLink: true,
                                variant: DButtonVariant.inline,
                                alignment: AlignmentDirectional.centerStart,
                                onPressed: onOpen,
                              ),
                            const SizedBox(height: 5),
                            DefaultTextStyle.merge(
                              style: TextStyle(color: tokens.mutedForeground),
                              child: Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Icon(
                                    event.private
                                        ? Icons.lock_outline
                                        : Icons.public,
                                    size: 12,
                                    color: tokens.mutedForeground,
                                  ),
                                  Text(
                                    event.private
                                        ? 'Private'
                                        : event.public
                                        ? 'Public'
                                        : 'Event',
                                  ),
                                  if (creator != null) ...[
                                    const Text('· Created by'),
                                    _Avatar(
                                      user: creator,
                                      site: siteUrl,
                                      size: 20,
                                    ),
                                    Text(creator.name ?? creator.username),
                                  ],
                                ],
                              ),
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
                        Builder(
                          builder: (menuContext) {
                            // Keep independent popup anchors separate in the
                            // card's native accessibility tree.
                            return Semantics(
                              container: true,
                              explicitChildNodes: true,
                              child: DDropdownMenu(
                                onOpenChange: (open, _) {
                                  if (open) _openingWithdraw = onWithdraw;
                                },
                                content: DDropdownMenuContent(
                                  semanticLabel: 'Event actions',
                                  width: 280,
                                  children: [
                                    if (onEdit != null)
                                      DDropdownMenuItem(
                                        onPressed: onEdit,
                                        child: const Text('Edit event'),
                                      ),
                                    if (onInvite != null)
                                      DDropdownMenuItem(
                                        onPressed: onInvite,
                                        child: const Text('Invite people'),
                                      ),
                                    if (onWithdraw != null)
                                      DDropdownMenuItem(
                                        onPressed: () =>
                                            _openingWithdraw?.call(),
                                        child: const Text('Remove my response'),
                                      ),
                                    if (onExport != null)
                                      DDropdownMenuItem(
                                        onPressed: onExport,
                                        child: const Text('Export calendar'),
                                      ),
                                    if (onWeb != null)
                                      DDropdownMenuItem(
                                        onPressed: onWeb,
                                        child: const Text('Open event on web'),
                                      ),
                                    if (onWeb != null && event.canManage)
                                      DDropdownMenuItem(
                                        onPressed: onWeb,
                                        child: const Text(
                                          'Bulk invitations and reports on web',
                                        ),
                                      ),
                                  ],
                                ),
                                child: DDropdownMenuTrigger(
                                  builder: (triggerContext, state) =>
                                      DButton.iconOnly(
                                        tooltip: 'Event actions',
                                        variant: DButtonVariant.ghost,
                                        icon: const Icon(Icons.more_vert),
                                        focusNode: state.focusNode,
                                        hasPopup: true,
                                        expanded: state.open,
                                        onPressed: state.toggle,
                                      ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Detail(
                    icon: Icons.schedule,
                    child: Text(
                      eventDateLabel(
                        event,
                        zones,
                        accountTimezone: accountTimezone,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (recurrence != null)
                    _Detail(icon: Icons.repeat, child: Text(recurrence)),
                  if (location != null && location.trim().isNotEmpty)
                    _Detail(
                      icon: Icons.place_outlined,
                      child: CookedHtml(
                        html: location,
                        siteUrl: siteUrl,
                        compactParagraphs: true,
                        textStyle: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (url != null && !event.flag('url_restates_location'))
                    _Detail(
                      icon: Icons.link,
                      child: DButton(
                        variant: DButtonVariant.inline,
                        alignment: AlignmentDirectional.centerStart,
                        isLink: true,
                        label: Text(url, softWrap: true, maxLines: 4),
                        onPressed: () => unawaited(
                          openLink(
                            context,
                            eventLinkUrl(url),
                            siteUrl: siteUrl,
                          ),
                        ),
                      ),
                    ),
                  if (description != null && description.trim().isNotEmpty)
                    _EventDescription(
                      key: ValueKey((siteUrl, event.id)),
                      source: description,
                      isHtml: hasHtmlDescription,
                      siteUrl: siteUrl,
                    ),
                  if (eventObject(event.fields['custom_fields'])
                      case final fields?)
                    for (final entry in fields.entries)
                      if (entry.value is String &&
                          (entry.value as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text('${entry.key}: ${entry.value}'),
                        ),
                  if (showParticipants || chat != null) ...[
                    const DSeparator(space: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked =
                            constraints.maxWidth < 400 ||
                            MediaQuery.textScalerOf(context).scale(12) > 18;
                        return Flex(
                          direction: stacked ? Axis.vertical : Axis.horizontal,
                          crossAxisAlignment: stacked
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showParticipants)
                              Flexible(
                                fit: stacked ? FlexFit.loose : FlexFit.tight,
                                child: participants,
                              ),
                            if (showParticipants && chat != null)
                              SizedBox(
                                width: stacked ? 0 : 12,
                                height: stacked ? 4 : 0,
                              ),
                            ?chat,
                          ],
                        );
                      },
                    ),
                    if (responses != null) const SizedBox(height: 12),
                  ],
                  if (event.text('livestream_url') case final link?)
                    DButton(
                      onPressed: () =>
                          unawaited(openLink(context, link, siteUrl: siteUrl)),
                      variant: DButtonVariant.inline,
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Open livestream'),
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
                  if (pending)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: DProgress(semanticsLabel: 'Loading event'),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              error,
                              style: TextStyle(color: tokens.destructive),
                            ),
                            if (onRetry != null)
                              DButton(
                                onPressed: onRetry,
                                variant: DButtonVariant.inline,
                                label: const Text('Refresh event'),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDescription extends StatefulWidget {
  const _EventDescription({
    super.key,
    required this.source,
    required this.isHtml,
    required this.siteUrl,
  });
  final String source;
  final bool isHtml;
  final String siteUrl;

  @override
  State<_EventDescription> createState() => _EventDescriptionState();
}

class _EventDescriptionState extends State<_EventDescription> {
  bool _expanded = false;

  String get _preview {
    if (!widget.isHtml) return widget.source;
    final fragment = html.parseFragment(widget.source);
    for (final element in fragment.querySelectorAll(
      'p,div,li,br,blockquote,pre,h1,h2,h3,h4,h5,h6,tr',
    )) {
      element.append(dom.Text('\n'));
    }
    for (final image in fragment.querySelectorAll('img')) {
      image.replaceWith(dom.Text(image.attributes['alt'] ?? ''));
    }
    return (fragment.text ?? '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: DTokens.of(context).mutedForeground);
    final preview = _preview;
    final content = widget.isHtml
        ? CookedHtml(
            html: widget.source,
            siteUrl: widget.siteUrl,
            compactParagraphs: true,
            textStyle: style,
          )
        : Text(widget.source, style: style);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DSeparator(space: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final painter = TextPainter(
                text: TextSpan(text: preview, style: style),
                maxLines: 2,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: constraints.maxWidth);
              final needsDisclosure = painter.didExceedMaxLines;
              painter.dispose();
              if (!needsDisclosure) return content;
              return DCollapsible(
                open: _expanded,
                onOpenChange: (value) => setState(() => _expanded = value),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_expanded)
                      Text(
                        preview,
                        style: style,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    DCollapsibleContent(child: content),
                    const SizedBox(height: 4),
                    Semantics(
                      expanded: _expanded,
                      child: DButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        variant: DButtonVariant.inline,
                        iconPosition: DButtonIconPosition.end,
                        icon: Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                        ),
                        label: Text(
                          _expanded ? 'Show less' : 'Show full description',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
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
  });
  final String status;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DToggle(
    pressed: selected,
    enabled: enabled,
    variant: DToggleVariant.outline,
    onPressedChanged: (_) => onTap(),
    icon: Icon(switch (status) {
      'going' => Icons.check,
      'interested' => Icons.star_outline,
      _ => Icons.close,
    }),
    child: Text(eventResponseLabel(status)),
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
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: DTokens.of(context).mutedForeground),
        const SizedBox(width: 9),
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
        DToast.show(
          context,
          eventError(error, reading: true),
          type: DToastType.error,
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
  Widget build(BuildContext context) => DCard(
    spacing: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error ?? 'Event details are unavailable.'),
          if (loading) const DProgress(semanticsLabel: 'Loading event'),
          Wrap(
            spacing: DSpacing.controlGap,
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
  factory EventCookedFallback({
    Key? key,
    required dom.Element element,
    String? siteUrl,
  }) {
    final visible = eventVisibleCookedElement(element);
    return EventCookedFallback._(
      key: key,
      title: visible.attributes['data-name'] ?? 'Event',
      start: visible.attributes['data-start'],
      description: visible.text.trim(),
      descriptionHtml: visible.innerHtml.trim(),
      siteUrl: siteUrl,
    );
  }
  const EventCookedFallback._({
    super.key,
    required this.title,
    required this.start,
    required this.description,
    required this.descriptionHtml,
    this.siteUrl,
  });
  final String title;
  final String? start;
  final String description;
  final String descriptionHtml;
  final String? siteUrl;
  @override
  Widget build(BuildContext context) => DCard(
    spacing: 0,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DText(title, variant: DTextVariant.large, headingLevel: 2),
          if (start != null) Text(start!),
          if (descriptionHtml.isNotEmpty)
            Builder(
              builder: (context) => CookedHtml(
                html: descriptionHtml,
                siteUrl: siteUrl,
                textStyle: DefaultTextStyle.of(context).style,
              ),
            ),
        ],
      ),
    ),
  );
}
