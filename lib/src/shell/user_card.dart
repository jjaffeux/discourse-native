import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../foundation/calendar_day.dart';
import '../foundation/clock_time.dart';
import '../foundation/count_label.dart';
import '../foundation/icons/d_icons.dart';
import '../foundation/timezone_environment.dart';
import '../models/badge.dart';
import '../models/user_card.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import 'anchored_layout.dart';
import 'cooked_html.dart';
import 'external_link.dart';
import 'image_decode.dart';
import 'platform.dart';
import 'relative_time.dart';
import 'server_image.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_activity.dart';
import 'user_card_header.dart';
import 'user_card_target.dart';
import 'user_menu_message.dart';

/// The height [DSheetContent] draws its `headerImage` at.
const double _sheetBannerHeight = 132;

Future<void> showUserCard({
  required BuildContext context,
  required String username,
  String? siteUrl,
}) {
  final controller = ShellScope.read(context);
  final targetSite = siteUrl ?? controller.currentInstance?.url;
  if (targetSite == null) return Future<void>.value();
  if (context.isTouch) {
    final restAt = GlobalKey(debugLabel: 'user-card-rest');
    return showDSheet<void>(
      context: context,
      side: DSheetSide.bottom,
      inset: true,
      variant: DSheetVariant.adaptiveMenu,
      restAt: restAt,
      builder: (context, sheet) =>
          ShellSelector<({ShellController controller, Object session})>(
            select: (controller) => (
              controller: controller,
              session: controller.lifecycle.capture(targetSite).session,
            ),
            builder: (context, owner, _) => ListenableBuilder(
              listenable: owner.controller.store.ref<UserCard>(
                targetSite,
                username.toLowerCase(),
              ),
              builder: (context, _) {
                final controller = owner.controller;
                final card = controller.userCard(username, siteUrl: targetSite);
                final lease = controller.lifecycle.capture(targetSite);
                return DSheetContent(
                  key: const ValueKey<String>('user-card-surface'),
                  card: true,
                  side: DSheetSide.bottom,
                  inset: true,
                  variant: DSheetVariant.adaptiveMenu,
                  restAt: restAt,
                  scrollWholeSheet: true,
                  showCloseButton: false,
                  semanticLabel: context.l10n.profileFor(username),

                  headerImage: card?.cardBackgroundUrl == null
                      ? null
                      : imageForCover(
                          context,
                          serverImageProvider(card!.cardBackgroundUrl!),
                          // The sheet is never wider than the screen.
                          logicalSize: Size(
                            MediaQuery.sizeOf(context).width,
                            _sheetBannerHeight,
                          ),
                        ),
                  slivers: [
                    if (card != null)
                      UserActivityView(
                        siteUrl: targetSite,
                        username: card.username,
                        embedded: true,
                        onOpen: (item) {
                          if (!lease.isCurrent) return;
                          sheet.close();
                          if (controller.currentInstance?.url != targetSite) {
                            controller.selectInstance(
                              controller.instances.indexWhere(
                                (instance) => instance.url == targetSite,
                              ),
                            );
                          }
                          controller.openUserActivityItem(item);
                        },
                      ),
                  ],
                  children: [
                    _ControllerUserCardPopup(
                      key: ValueKey(owner),
                      restAt: restAt,
                      controller: owner.controller,
                      username: username,
                      siteUrl: targetSite,
                      close: sheet.close,
                    ),
                  ],
                );
              },
            ),
          ),
    );
  }
  final anchor = anchorRect(
    anchor: context.findRenderObject() as RenderBox?,
    overlay:
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?,
  );

  return showDPopover(
    context: context,
    anchorRect: anchor,
    builder: (context) => DPopoverContent(
      key: const ValueKey<String>('user-card-surface'),
      semanticLabel: context.l10n.profileFor(username),
      width: 340,
      constraints: const BoxConstraints(maxHeight: 640),
      align: DPopoverAlign.start,
      sideOffset: 8,
      collisionPadding: 12,
      padding: EdgeInsets.zero,
      child: DPopoverClose(
        builder: (context, close) =>
            ShellSelector<({ShellController controller, Object session})>(
              select: (controller) => (
                controller: controller,
                session: controller.lifecycle.capture(targetSite).session,
              ),
              builder: (context, owner, _) => _ControllerUserCardPopup(
                key: ValueKey(owner),
                controller: owner.controller,
                username: username,
                siteUrl: targetSite,
                close: close,
              ),
            ),
      ),
    ),
  );
}

class _ControllerUserCardPopup extends StatefulWidget {
  const _ControllerUserCardPopup({
    super.key,
    required this.controller,
    required this.username,
    required this.siteUrl,
    required this.close,
    this.restAt,
  });

  final GlobalKey? restAt;
  final ShellController controller;
  final String username;
  final String siteUrl;
  final VoidCallback close;

  @override
  State<_ControllerUserCardPopup> createState() =>
      _ControllerUserCardPopupState();
}

class _ControllerUserCardPopupState extends State<_ControllerUserCardPopup> {
  // The requests announce every card on every forum; this one cares only
  // about what they change for it. The parent remounts it for each account
  // session, which starts from new store refs.
  late final _changes = Listenable.merge([
    widget.controller.userCardRequests,
    widget.controller.store.ref<UserCard>(
      widget.siteUrl,
      widget.username.toLowerCase(),
    ),
  ]);
  late ({UserCard? card, String? error}) _view = _read();

  ({UserCard? card, String? error}) _read() => (
    card: widget.controller.userCard(widget.username, siteUrl: widget.siteUrl),
    error: widget.controller.userCardError(
      widget.username,
      siteUrl: widget.siteUrl,
    ),
  );

  void _changed() {
    final next = _read();
    if (next != _view) setState(() => _view = next);
  }

  @override
  void initState() {
    super.initState();
    _changes.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    _changes.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load() async {
    final controller = widget.controller;
    try {
      await controller.load();
    } catch (_) {
      return;
    }
    if (!mounted || !identical(widget.controller, controller)) return;
    if (!controller.loaded) return;
    if (!controller.contains(widget.siteUrl)) {
      widget.close();
      return;
    }
    await controller.loadUserCard(widget.username, siteUrl: widget.siteUrl);
  }

  @override
  Widget build(BuildContext context) {
    final (:card, :error) = _view;
    final controller = widget.controller;
    final siteUrl = widget.siteUrl;
    if (card != null) {
      if (context.isTouch) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: widget.restAt,
              child: _MobileCardContent(
                card: card,
                siteUrl: siteUrl,
                close: widget.close,
              ),
            ),
            DSheetSwipeHint(label: context.l10n.swipeUpToViewActivity),
          ],
        );
      }
      return _CardContent(card: card, siteUrl: siteUrl, close: widget.close);
    }

    if (error != null) {
      return UserMenuMessage(
        text: error,
        height: 132,
        onRetry: () => controller.loadUserCard(
          widget.username,
          force: true,
          siteUrl: siteUrl,
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(12),
      child: UserCardSkeleton(),
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.card,
    required this.siteUrl,
    required this.close,
  });

  final UserCard card;
  final String siteUrl;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pluginActions = PluginScope.of(
      context,
    ).registry.userCardActions(context, siteUrl, card, close);
    final pluginMetadata = PluginScope.of(
      context,
    ).registry.userCardMetadata(context, siteUrl, card, close);
    final profileAction = SizedBox(
      width: double.infinity,
      child: DButton(
        label: Text(context.l10n.viewProfile),
        onPressed: () {
          close();
          unawaited(openExternalLink('$siteUrl${card.path}'));
        },
        icon: const DIcon(DIcons.upRightFromSquare),
      ),
    );
    final shell = ShellScope.read(context);
    final currentUser = shell.currentUserFor(siteUrl);
    final ownCard =
        currentUser != null &&
        (card.id != null && currentUser.id != null
            ? card.id == currentUser.id
            : card.username.toLowerCase() ==
                  currentUser.username.toLowerCase());
    final lease = shell.lifecycle.capture(siteUrl);
    final actions = [
      if (ownCard)
        DButton(
          label: Text(context.l10n.preferences),
          icon: const DIcon(DIcons.gear),
          onPressed: () {
            if (!lease.isCurrent) return;
            close();
            shell.openPreferences(siteUrl);
          },
        ),
      ...pluginActions,
      profileAction,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        UserCardHeader(card: card, siteUrl: siteUrl),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              _CardActions(actions: actions),
              if (card.bioExcerpt case final bio?) ...[
                const SizedBox(height: 12),
                CookedHtml(
                  html: bio,
                  textStyle: theme.textTheme.bodyLarge?.copyWith(
                    height: DiscourseTypography.lineHeightCooked,
                  ),
                  siteUrl: siteUrl,
                ),
              ],
              if (card.website != null || card.location != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    if (card.website case final website?)
                      _CardDetail(
                        icon: const DIcon(DIcons.globe, size: 16),
                        label: card.websiteName ?? _websiteLabel(website),
                        onTap: () => unawaited(openExternalLink(website)),
                      ),
                    if (card.location case final location?)
                      _CardDetail(
                        icon: const DIcon(DIcons.locationDot, size: 16),
                        label: location,
                      ),
                  ],
                ),
              ],
              if (card.createdAt != null ||
                  card.lastPostedAt != null ||
                  card.timeRead > 0) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (card.lastPostedAt case final last?)
                      _Metadata(
                        label: context.l10n.lastPost,
                        value: _month(last),
                      ),
                    if (card.createdAt case final joined?)
                      _Metadata(
                        label: context.l10n.joined,
                        value: _month(joined),
                      ),
                    if (card.timeRead > 0)
                      _Metadata(
                        label: context.l10n.timeRead,
                        value: durationLabel(card.timeRead).short,
                      ),
                  ],
                ),
              ],
              if (pluginMetadata.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 12, runSpacing: 4, children: pluginMetadata),
              ],
              if (card.badgeCount > 0) ...[
                const SizedBox(height: 10),
                _BadgeCount(count: card.badgeCount),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: DButton(
                  variant: DButtonVariant.secondary,
                  size: DButtonSize.toolbar,
                  shape: DButtonShape.pill,
                  borderColor: Colors.transparent,
                  label: Text(context.l10n.viewActivity),
                  icon: const DIcon(DIcons.barsStaggered),
                  onPressed: () {
                    if (!lease.isCurrent) return;
                    close();
                    shell.openUserActivity(
                      siteUrl,
                      username: card.username,
                      displayName: card.displayName,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _month(DateTime when) {
    final day = calendarDay(when)!;
    return '${shortMonthName(day.month)} ${day.year}';
  }

  static String _websiteLabel(String website) {
    final uri = Uri.tryParse(website);
    if (uri?.host case final String host when host.isNotEmpty) {
      return '${host.startsWith('www.') ? host.substring(4) : host}${uri!.path == '/' ? '' : uri.path}';
    }
    return website;
  }
}

class _MobileCardContent extends StatelessWidget {
  const _MobileCardContent({
    required this.card,
    required this.siteUrl,
    required this.close,
  });
  final UserCard card;
  final String siteUrl;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final shell = ShellScope.read(context);
    final pluginMetadata = PluginScope.of(
      context,
    ).registry.userCardMetadata(context, siteUrl, card, close);
    final current = shell.currentUserFor(siteUrl);
    final own =
        current != null &&
        (card.id != null && current.id != null
            ? card.id == current.id
            : card.username.toLowerCase() == current.username.toLowerCase());
    final lease = shell.lifecycle.capture(siteUrl);
    final actions = <Widget>[
      if (own)
        DButton(
          size: DButtonSize.toolbar,
          shape: DButtonShape.pill,
          borderColor: Colors.transparent,
          label: Text(context.l10n.userCardEditProfileAction),
          icon: const DIcon(DIcons.pencil),
          onPressed: () {
            if (lease.isCurrent) {
              close();
              shell.openPreferences(siteUrl);
            }
          },
        ),
      if (!own &&
          card.canSendPrivateMessage &&
          current?.canSendPrivateMessages == true)
        DButton(
          size: DButtonSize.toolbar,
          shape: DButtonShape.pill,
          borderColor: Colors.transparent,
          label: Text(context.l10n.userCardMessageAction),
          icon: const DIcon(DIcons.envelope),
          onPressed: () {
            if (lease.isCurrent && shell.currentInstance?.url == siteUrl) {
              close();
              shell.openPrivateMessage(
                siteUrl: siteUrl,
                targetRecipients: card.username,
              );
            }
          },
        ),
      if (!own)
        ...PluginScope.of(
          context,
        ).registry.userCardActions(context, siteUrl, card, close),
    ];
    final zone = TimezoneEnvironment.instance.location(card.timezone);
    final secondary = Color.lerp(tokens.background, tokens.foreground, .62)!;
    final muted = Color.lerp(tokens.background, tokens.foreground, .50)!;
    final textStyle = TextStyle(
      fontSize: DiscourseTypography.preview,
      height: 1.5,
      color: secondary,
    );
    Widget fact(Widget icon, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme.merge(
          data: IconThemeData(size: 11, color: muted),
          child: icon,
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: textStyle)),
      ],
    );
    Widget stat(String label, String value) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(color: muted),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: tokens.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      style: textStyle,
    );
    final remainder = (card.badgeCount - card.featuredBadges.length).clamp(
      0,
      1 << 31,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UserCardHeader(card: card, siteUrl: siteUrl, mobileSheet: true),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (actions.isNotEmpty) ...[
                LayoutBuilder(
                  builder: (context, bounds) {
                    if (MediaQuery.textScalerOf(context).scale(13) > 19) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final action in actions)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: action,
                            ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(child: actions[i]),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
              ],
              if (card.bioExcerpt case final bio?) ...[
                CookedHtml(
                  html: bio,
                  siteUrl: siteUrl,
                  textStyle: TextStyle(
                    fontSize: DiscourseTypography.compact,
                    height: 1.5,
                    color: Color.lerp(
                      tokens.background,
                      tokens.foreground,
                      .90,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (card.website != null ||
                  card.location != null ||
                  zone != null) ...[
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    if (card.website case final website?)
                      _CardDetail(
                        icon: const DIcon(DIcons.globe, size: 11),
                        label:
                            card.websiteName ??
                            _CardContent._websiteLabel(website),
                        onTap: () => unawaited(openExternalLink(website)),
                      ),
                    if (card.location case final location?)
                      fact(const DIcon(DIcons.locationDot), location),
                    if (zone != null)
                      fact(
                        const DIcon(DIcons.farClock),
                        clockTimeLabel(context, tz.TZDateTime.now(zone)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              if (card.createdAt != null ||
                  card.lastPostedAt != null ||
                  card.timeRead > 0) ...[
                DSeparator(
                  color: Color.lerp(tokens.background, tokens.foreground, .12),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    if (card.lastPostedAt case final last?)
                      RelativeTimeBuilder(
                        when: last,
                        builder: (context, label) =>
                            stat(context.l10n.lastPost, label),
                      ),
                    if (card.createdAt case final created?)
                      stat(context.l10n.joined, _CardContent._month(created)),
                    if (card.timeRead > 0)
                      stat(
                        context.l10n.userCardReadTime,
                        _readTime(card.timeRead),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              if (pluginMetadata.isNotEmpty) ...[
                Wrap(spacing: 16, runSpacing: 6, children: pluginMetadata),
                const SizedBox(height: 14),
              ],
              if (card.featuredBadges.isNotEmpty || remainder > 0)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final badge in card.featuredBadges)
                      DBadge(
                        size: DBadgeSize.featured,
                        variant: DBadgeVariant.secondary,
                        backgroundColor: Color.lerp(
                          tokens.background,
                          tokens.foreground,
                          .10,
                        ),
                        foregroundColor: tokens.foreground,
                        leading: DIcon(
                          pluginIconNamed(context, badge.icon) ??
                              DIcons.certificate,
                          color: switch (badge.tier) {
                            BadgeTier.gold => const Color(0xffe2b55e),
                            BadgeTier.silver => const Color(0xffa6b6ba),
                            BadgeTier.bronze => const Color(0xffd5a25e),
                          },
                        ),
                        child: Text(badge.name),
                      ),
                    if (remainder > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          context.l10n.userCardMoreBadges(remainder),
                          style: TextStyle(
                            fontSize: DiscourseTypography.xs,
                            height: 1.5,
                            color: muted,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _readTime(int seconds) {
    const month = 30 * Duration.secondsPerDay;
    return seconds >= month && seconds < 365 * Duration.secondsPerDay
        ? appL10n.relativeDurationMonths((seconds / month).round())
        : durationLabel(seconds).short;
  }
}

class _CardActions extends StatelessWidget {
  const _CardActions({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = actions.length == 1 || constraints.maxWidth < 320
            ? constraints.maxWidth
            : (constraints.maxWidth - DSpacing.controlGap) / 2;
        return Wrap(
          spacing: DSpacing.controlGap,
          runSpacing: 8,
          children: [
            for (final action in actions) SizedBox(width: width, child: action),
          ],
        );
      },
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label ',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              TextSpan(text: value),
            ],
          ),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _CardDetail extends StatelessWidget {
  const _CardDetail({required this.icon, required this.label, this.onTap});

  final Widget icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme(
          data: IconThemeData(color: color),
          child: icon,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              decoration: onTap == null ? null : TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return child;
    return DItem(
      fitContent: true,
      size: DItemSize.artwork,
      highlightOnInteraction: false,
      link: true,
      onPressed: onTap!,
      semanticLabel: label,
      children: [ExcludeSemantics(child: child)],
    );
  }
}

class _BadgeCount extends StatelessWidget {
  const _BadgeCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => DBadge(
    variant: DBadgeVariant.outline,
    leading: const DIcon(DIcons.certificate, size: 12),
    child: Text(countLabel(count, CountNoun.badge)),
  );
}
