import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'event_controller.dart';
import 'event_cooked_visibility.dart';
import 'event_data.dart';
import 'event_date_stamp.dart';
import 'event_export.dart';
import 'event_navigation.dart';
import 'event_participants.dart';
import 'event_time.dart';

/// Only a hydrated, authorized owner supplies interactive callbacks.
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
      child: SiteEmojiText.plain(event.title, siteUrl: siteUrl),
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
                            semanticLabel:
                                context.l10n.chooseRecurringAttendance,
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
                                child: Text(context.l10n.thisOccurrenceOnly),
                              ),
                              DDropdownMenuCheckboxItem(
                                checked:
                                    selected == 'going' &&
                                    event.watching?.recurring == true,
                                closeOnSelect: true,
                                onChanged: (_) => onSelect(
                                  () => _openingRespond?.call(status, true),
                                ),
                                child: Text(context.l10n.everyOccurrence),
                              ),
                            ],
                          ),
                          child: Semantics(
                            selected: selected == status,
                            child: DDropdownMenuTrigger(
                              builder: (triggerContext, state) => DButton(
                                size: DButtonSize.post,
                                label: Text(eventResponseLabel(status)),
                                tooltip: context.l10n.chooseRecurringAttendance,
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
        if (stats?['going'] case final int count)
          Text(context.l10n.goingEventcard((count).toString())),
        if (stats?['interested'] case final int count)
          Text(
            context.l10n.interestedEventcard((count).toString()),
            style: TextStyle(color: tokens.mutedForeground),
          ),
        if (event.sampleInvitees.isEmpty && stats == null)
          Text(context.l10n.participants),
      ],
    );
    final participants = onParticipants == null
        ? _Detail(icon: Icons.people_outline, child: participantLabel)
        : DButton(
            size: DButtonSize.post,
            onPressed: pending ? null : onParticipants,
            variant: DButtonVariant.inline,
            alignment: AlignmentDirectional.centerStart,
            semanticLabel: [
              context.l10n.viewParticipants,
              if (stats?['going'] case final int count)
                context.l10n.goingEventcard((count).toString()),
              if (stats?['interested'] case final int count)
                context.l10n.interestedEventcardValue((count).toString()),
            ].join(', '),
            tooltip: context.l10n.viewParticipants,
            icon: const Icon(Icons.people_outline),
            label: participantLabel,
          );
    final chat = channelId == null
        ? null
        : LinkTarget(
            url: resolveSitePath(siteUrl, 'chat/c/-/$channelId'),
            siteUrl: siteUrl,
            child: DButton(
              size: DButtonSize.post,
              onPressed: () => unawaited(
                openLink(
                  context,
                  resolveSitePath(siteUrl, 'chat/c/-/$channelId'),
                  siteUrl: siteUrl,
                ),
              ),
              variant: DButtonVariant.inline,
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(context.l10n.openEventChat),
            ),
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
                          semanticLabel: context.l10n.cover(
                            (event.title).toString(),
                          ),
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (date != null) ...[
                        EventDateStamp(date: date),
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
                                size: DButtonSize.post,
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
                                        ? context.l10n.private
                                        : event.public
                                        ? context.l10n.public
                                        : context.l10n.event,
                                  ),
                                  if (creator != null) ...[
                                    Text(context.l10n.createdBy),
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
                                  semanticLabel: context.l10n.eventActions,
                                  width: 280,
                                  children: [
                                    if (onEdit != null)
                                      DDropdownMenuItem(
                                        onPressed: onEdit,
                                        child: Text(context.l10n.editEvent),
                                      ),
                                    if (onInvite != null)
                                      DDropdownMenuItem(
                                        onPressed: onInvite,
                                        child: Text(context.l10n.invitePeople),
                                      ),
                                    if (onWithdraw != null)
                                      DDropdownMenuItem(
                                        onPressed: () =>
                                            _openingWithdraw?.call(),
                                        child: Text(
                                          context.l10n.removeMyResponse,
                                        ),
                                      ),
                                    if (onExport != null)
                                      DDropdownMenuItem(
                                        onPressed: onExport,
                                        child: Text(
                                          context.l10n.exportCalendar,
                                        ),
                                      ),
                                    if (onWeb != null)
                                      DDropdownMenuItem(
                                        onPressed: onWeb,
                                        child: Text(
                                          context.l10n.openEventOnWeb,
                                        ),
                                      ),
                                    if (onWeb != null && event.canManage)
                                      DDropdownMenuItem(
                                        onPressed: onWeb,
                                        child: Text(
                                          context
                                              .l10n
                                              .bulkInvitationsAndReportsOnWeb,
                                        ),
                                      ),
                                  ],
                                ),
                                child: DDropdownMenuTrigger(
                                  builder: (triggerContext, state) =>
                                      DButton.iconOnly(
                                        size: DButtonSize.post,
                                        tooltip: context.l10n.eventActions,
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
                        use24HourClock: use24HourClockOf(context),
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
                      child: LinkTarget(
                        url: eventLinkUrl(url),
                        siteUrl: siteUrl,
                        child: DButton(
                          size: DButtonSize.post,
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
                    LinkTarget(
                      url: link,
                      siteUrl: siteUrl,
                      child: DButton(
                        size: DButtonSize.post,
                        onPressed: () => unawaited(
                          openLink(context, link, siteUrl: siteUrl),
                        ),
                        variant: DButtonVariant.inline,
                        icon: const Icon(Icons.videocam_outlined),
                        label: Text(context.l10n.openLivestream),
                      ),
                    ),
                  if (event.flag('is_closed') ||
                      event.flag('is_expired') ||
                      event.flag('at_capacity'))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        event.flag('is_closed')
                            ? context.l10n.thisEventIsClosed
                            : event.flag('is_expired')
                            ? context.l10n.thisEventHasEnded
                            : context.l10n.thisEventIsAtCapacity,
                      ),
                    ),
                  if (onConnect != null &&
                      !event.flag('is_expired') &&
                      !event.flag('is_closed'))
                    DButton(
                      size: DButtonSize.post,
                      label: Text(context.l10n.connectToRespond),
                      onPressed: onConnect,
                    ),
                  if (pending)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: DProgress(
                        semanticsLabel: context.l10n.loadingEvent,
                      ),
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
                                size: DButtonSize.post,
                                onPressed: onRetry,
                                variant: DButtonVariant.inline,
                                label: Text(context.l10n.refreshEvent),
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
                        size: DButtonSize.post,
                        onPressed: () => setState(() => _expanded = !_expanded),
                        variant: DButtonVariant.inline,
                        iconPosition: DButtonIconPosition.end,
                        icon: Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                        ),
                        label: Text(
                          _expanded
                              ? context.l10n.showLess
                              : context.l10n.showFullDescription,
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
    size: DToggleSize.post,
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
  'going' => appL10n.going,
  'interested' => appL10n.interested,
  'not_going' => appL10n.notGoing,
  _ => appL10n.invited,
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
          error is EmptyEventCalendarException
              ? appL10n.thisEventHasNoDatesLeftToExport
              : eventError(error, reading: true),
          type: DToastType.error,
        );
      }
    } finally {
      if (mounted && identical(_exportOperation, operation)) {
        setState(() => _exportOperation = null);
      }
    }
  }

  // Not the controller: every event's load and write notifies it, and a post
  // stream or onebox list holds one card per event.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _handle.changes,
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
      // As on the web: the calendar feed leaves a closed or expired event
      // out, and an invitation to one that has started notifies nobody.
      final expiredOrClosed =
          event.flag('is_expired') || event.flag('is_closed');
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
        onInvite: available && !expiredOrClosed && event.canManage
            ? () => showEventInvitations(context, handle)
            : null,
        onExport: available && !expiredOrClosed && !_exporting
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
          Text(error ?? context.l10n.eventDetailsAreUnavailable),
          if (loading) DProgress(semanticsLabel: context.l10n.loadingEvent),
          Wrap(
            spacing: DSpacing.controlGap,
            children: [
              if (onRetry != null)
                DButton(
                  size: DButtonSize.post,
                  onPressed: onRetry,
                  variant: DButtonVariant.link,
                  label: Text(context.l10n.refreshEvent),
                ),
              if (onWeb != null)
                DButton(
                  size: DButtonSize.post,
                  onPressed: onWeb,
                  variant: DButtonVariant.link,
                  label: Text(context.l10n.openEventOnWeb),
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
      title: visible.attributes['data-name'] ?? appL10n.event,
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
