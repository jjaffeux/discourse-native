import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../foundation/calendar_day.dart';
import '../foundation/clock_time.dart';
import '../foundation/count_label.dart';
import '../foundation/timezone_environment.dart';
import '../foundation/uri_path.dart';
import '../models/badge.dart';
import '../models/discourse_instance.dart';
import '../models/user_card.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'external_link.dart';
import 'platform.dart';
import 'relative_time.dart';
import 'server_image.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'skeleton_fill.dart';
import 'user_card_header.dart';
import 'user_menu_message.dart';

class UserCardTarget extends StatelessWidget {
  const UserCardTarget({
    super.key,
    required this.username,
    required this.child,
    this.siteUrl,
    this.semanticLabel,
  });

  const UserCardTarget.avatar({
    super.key,
    required this.username,
    required this.child,
    this.siteUrl,
    this.semanticLabel,
  });

  final String username;
  final Widget child;
  final String? siteUrl;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (username.isEmpty) return child;

    void open() => unawaited(
      showUserCard(context: context, username: username, siteUrl: siteUrl),
    );

    void loadPreview() {
      final controller = ShellScope.maybeRead(context);
      final targetSite = siteUrl ?? controller?.currentInstance?.url;
      if (controller == null || targetSite == null) return;
      unawaited(
        controller.loadUserCard(
          username,
          siteUrl: targetSite,
          force:
              controller.userCardError(username, siteUrl: targetSite) != null,
        ),
      );
    }

    return DHoverCard(
      onOpenChange: (isOpen, reason) {
        if (isOpen) loadPreview();
      },
      trigger: DHoverCardTrigger(
        builder: (context, state) => DButton(
          focusNode: state.focusNode,
          onPressed: open,
          variant: DButtonVariant.inline,
          density: DButtonDensity.inlineMetadata,
          semanticLabel:
              semanticLabel ??
              context.l10n.viewProfileForUsercard((username).toString()),
          label: DefaultTextStyle(
            style: DefaultTextStyle.of(context).style,
            child: ExcludeSemantics(child: child),
          ),
        ),
      ),
      content: DHoverCardContent(
        align: DPopoverAlign.start,
        child: _UserCardHoverPreview(username: username, siteUrl: siteUrl),
      ),
    );
  }
}

class _UserCardHoverPreview extends StatelessWidget {
  const _UserCardHoverPreview({required this.username, required this.siteUrl});

  final String username;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    if (ShellScope.maybeIdentityOf(context) == null) {
      return Text(context.l10n.profilePreviewUnavailable);
    }
    return ShellSelector<_PreviewTarget>(
      select: (controller) {
        final targetSite = siteUrl ?? controller.currentInstance?.url;
        return (
          controller: controller,
          siteUrl: targetSite,
          // Only a connected forum can load a card. A new account session
          // forgets the store's refs, so the preview resubscribes with it.
          session: targetSite != null && controller.contains(targetSite)
              ? controller.lifecycle.capture(targetSite).session
              : null,
        );
      },
      builder: (context, target, _) {
        final (:controller, siteUrl: targetSite, :session) = target;
        if (targetSite == null || session == null) {
          return Text(context.l10n.profilePreviewUnavailable);
        }
        // A card's fetch and result are announced here, not on the shell.
        return ListenableBuilder(
          listenable: Listenable.merge([
            controller.userCardRequests,
            controller.store.ref<UserCard>(targetSite, username.toLowerCase()),
          ]),
          builder: (context, _) {
            final card = controller.userCard(username, siteUrl: targetSite);
            if (card != null) return _UserCardHoverContent(card: card);
            final error = controller.userCardError(
              username,
              siteUrl: targetSite,
            );
            if (error != null) return Text(error);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted ||
                  controller.userCard(username, siteUrl: targetSite) != null ||
                  controller.userCardError(username, siteUrl: targetSite) !=
                      null) {
                return;
              }
              unawaited(controller.loadUserCard(username, siteUrl: targetSite));
            });
            return const _CardSkeleton(preview: true);
          },
        );
      },
    );
  }
}

typedef _PreviewTarget = ({
  ShellController controller,
  String? siteUrl,
  Object? session,
});

class _UserCardHoverContent extends StatelessWidget {
  const _UserCardHoverContent({required this.card});

  final UserCard card;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        DAvatar.frame(
          decorative: true,
          child: SizedBox.square(
            dimension: 40,
            child: AvatarImage(
              url: card.avatarUrl,
              size: 40,
              fallback: ColoredBox(
                color: tokens.muted,
                child: Center(
                  child: Text(
                    card.username.characters.firstOrNull?.toUpperCase() ?? '?',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                card.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '@${card.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tokens.mutedForeground),
              ),
              if (card.title case final title?)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (card.location case final location?)
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.mutedForeground,
                    fontSize: DiscourseTypography.xs,
                    height: DiscourseTypography.lineHeightCaption,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String? usernameFromProfileUrl(Uri url, {String? siteUrl}) {
  final segments = siteUrl == null
      ? tryUriPathSegments(url)
      : DiscourseInstance.pathSegmentsWithin(siteUrl, url);
  if (segments == null ||
      segments.length != 2 ||
      segments.first != 'u' ||
      segments.last.isEmpty) {
    return null;
  }
  return segments.last;
}

bool showUserCardForUrl(BuildContext context, String url, {String? siteUrl}) {
  final controller = ShellScope.maybeRead(context);
  final instance = siteUrl == null
      ? controller?.currentInstance
      : controller?.instances.where((site) => site.url == siteUrl).firstOrNull;
  if (instance == null) return false;

  final uri = Uri.tryParse(url);
  if (uri == null || !instance.serves(uri)) return false;

  final username = usernameFromProfileUrl(uri, siteUrl: instance.url);
  if (username == null) return false;

  unawaited(
    showUserCard(context: context, username: username, siteUrl: instance.url),
  );
  return true;
}

Future<void> showUserCard({
  required BuildContext context,
  required String username,
  String? siteUrl,
}) {
  final controller = ShellScope.read(context);
  final targetSite = siteUrl ?? controller.currentInstance?.url;
  if (targetSite == null) return Future<void>.value();
  if (context.isTouch) {
    return showDSheet<void>(
      context: context,
      side: DSheetSide.bottom,
      inset: true,
      variant: DSheetVariant.menu,
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
                final card = owner.controller.userCard(
                  username,
                  siteUrl: targetSite,
                );
                return DSheetContent(
                  key: const ValueKey<String>('user-card-surface'),
                  side: DSheetSide.bottom,
                  inset: true,
                  variant: DSheetVariant.menu,
                  showCloseButton: false,
                  semanticLabel: context.l10n.profileFor(username),
                  topBottomMaxHeightFactor: .9,
                  headerImage: card?.cardBackgroundUrl == null
                      ? null
                      : serverImageProvider(card!.cardBackgroundUrl!),
                  children: [
                    _ControllerUserCardPopup(
                      key: ValueKey(owner),
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
      width: 400,
      constraints: const BoxConstraints(maxHeight: 480),
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
  });

  final ShellController controller;
  final String username;
  final String siteUrl;
  final VoidCallback close;

  @override
  State<_ControllerUserCardPopup> createState() =>
      _ControllerUserCardPopupState();
}

class _ControllerUserCardPopupState extends State<_ControllerUserCardPopup> {
  @override
  void initState() {
    super.initState();
    unawaited(_load());
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

  // The parent remounts this for each account session, which starts from new
  // store refs; within one session only the card and its fetch change.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.controller.userCardRequests,
      widget.controller.store.ref<UserCard>(
        widget.siteUrl,
        widget.username.toLowerCase(),
      ),
    ]),
    builder: (context, _) => _CardBody(
      controller: widget.controller,
      username: widget.username,
      siteUrl: widget.siteUrl,
      close: widget.close,
    ),
  );
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.controller,
    required this.username,
    required this.siteUrl,
    required this.close,
  });

  final ShellController controller;
  final String username;
  final String siteUrl;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final card = controller.userCard(username, siteUrl: siteUrl);
    if (card != null) {
      if (context.isTouch) {
        return _MobileCardContent(card: card, siteUrl: siteUrl, close: close);
      }
      return _CardContent(card: card, siteUrl: siteUrl, close: close);
    }

    final error = controller.userCardError(username, siteUrl: siteUrl);
    if (error != null) {
      return UserMenuMessage(
        text: error,
        height: 132,
        onRetry: () =>
            controller.loadUserCard(username, force: true, siteUrl: siteUrl),
      );
    }
    return const Padding(padding: EdgeInsets.all(12), child: _CardSkeleton());
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({this.preview = false});

  final bool preview;

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    semanticsLabel: context.l10n.loadingProfile,
    color: skeletonFill(context, on: SkeletonSurface.floating),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DSkeleton.circle(diameter: preview ? 40 : 64),
            SizedBox(width: preview ? 10 : 16),
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  DSkeleton(width: 160, height: 16),
                  DSkeleton(width: 104, height: 14),
                ],
              ),
            ),
          ],
        ),
        if (!preview) ...[
          const SizedBox(height: 12),
          const DSkeleton(height: 28),
          const SizedBox(height: 12),
          const DSkeleton(height: 14),
          const SizedBox(height: 8),
          const FractionallySizedBox(
            widthFactor: 0.75,
            child: DSkeleton(height: 14),
          ),
          const SizedBox(height: 12),
          const DSkeleton(width: 160, height: 12),
        ],
      ],
    ),
  );
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
                        icon: const Icon(Icons.location_on_outlined, size: 16),
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
              if (card.badgeCount > 0) ...[
                const SizedBox(height: 10),
                _BadgeCount(count: card.badgeCount),
              ],
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
