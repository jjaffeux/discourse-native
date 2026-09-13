import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../foundation/uri_path.dart';
import '../models/discourse_instance.dart';
import '../models/user_card.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'external_link.dart';
import 'inline_action.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu_message.dart';
import 'user_status.dart';

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
        builder: (context, state) => InlineAction(
          focusNode: state.focusNode,
          onTap: open,
          semanticLabel: semanticLabel ?? 'View profile for @$username',
          excludeChildSemantics: true,
          borderRadius: BorderRadius.circular(4),
          child: child,
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
    final controller = ShellScope.maybeOf(context);
    final targetSite = siteUrl ?? controller?.currentInstance?.url;
    if (controller == null || targetSite == null) {
      return const Text('Profile preview unavailable.');
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final card = controller.userCard(username, siteUrl: targetSite);
        if (card == null) {
          final error = controller.userCardError(username, siteUrl: targetSite);
          if (error != null) return Text(error);
          if (!controller.contains(targetSite)) {
            return const Text('Profile preview unavailable.');
          }
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
        }
        return _UserCardHoverContent(card: card);
      },
    );
  }
}

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
  final anchor = anchorRect(
    anchor: context.findRenderObject() as RenderBox?,
    overlay:
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?,
  );

  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) =>
        _UserCardPopup(username: username, siteUrl: targetSite, anchor: anchor),
  );
}

class _UserCardPopup extends StatelessWidget {
  const _UserCardPopup({
    required this.username,
    required this.siteUrl,
    required this.anchor,
  });

  final String username;
  final String siteUrl;
  final Rect? anchor;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)!;
    return DPopover(
      defaultOpen: true,
      onOpenChangeComplete: (open) {
        // Remove this card's route even if a plugin action opened another one.
        if (!open && route.isActive) route.navigator?.removeRoute(route);
      },
      content: DPopoverContent(
        key: const ValueKey<String>('user-card-surface'),
        semanticLabel: 'Profile for @$username',
        width: 400,
        constraints: const BoxConstraints(maxHeight: 480),
        align: DPopoverAlign.start,
        sideOffset: 8,
        collisionPadding: 12,
        padding: const EdgeInsets.all(12),
        child: DPopoverClose(
          builder: (context, close) =>
              ShellSelector<({ShellController controller, Object session})>(
                select: (controller) => (
                  controller: controller,
                  session: controller.lifecycle.capture(siteUrl).session,
                ),
                builder: (context, owner, _) => _ControllerUserCardPopup(
                  // Account changes clear the cache, so load the new session.
                  key: ValueKey(owner),
                  controller: owner.controller,
                  username: username,
                  siteUrl: siteUrl,
                  close: close,
                ),
              ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A profile link can supply an entire cooked post as its context.
          // Only its opening corner belongs to the popover's anchor area.
          final point =
              switch (Directionality.of(context)) {
                TextDirection.ltr => anchor?.bottomLeft,
                TextDirection.rtl => anchor?.bottomRight,
              } ??
              constraints.biggest.center(Offset.zero);
          final padding = MediaQuery.paddingOf(context);
          return Stack(
            children: [
              Positioned(
                left: point.dx.clamp(
                  padding.left,
                  constraints.maxWidth - padding.right - 1,
                ),
                top: (point.dy - 1).clamp(
                  padding.top,
                  constraints.maxHeight - padding.bottom - 1,
                ),
                width: 1,
                height: 1,
                child: const DPopoverAnchor(child: SizedBox.expand()),
              ),
            ],
          );
        },
      ),
    );
  }
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
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
    return const _CardSkeleton();
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({this.preview = false});

  final bool preview;

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    semanticsLabel: 'Loading profile',
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
        label: const Text('View profile'),
        onPressed: () {
          close();
          unawaited(openExternalLink('$siteUrl${card.path}'));
        },
        icon: const DIcon(DIcons.upRightFromSquare),
      ),
    );
    final actions = [...pluginActions, profileAction];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _CardIdentity(card: card, siteUrl: siteUrl),
        const SizedBox(height: 12),
        _CardActions(actions: actions),
        if (card.bioExcerpt case final bio?) ...[
          const SizedBox(height: 12),
          CookedHtml(
            html: bio,
            textStyle: theme.textTheme.bodyMedium?.copyWith(
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
                _Metadata(label: 'Last post', value: _month(last)),
              if (card.createdAt case final joined?)
                _Metadata(label: 'Joined', value: _month(joined)),
              if (card.timeRead > 0)
                _Metadata(label: 'Time read', value: _duration(card.timeRead)),
            ],
          ),
        ],
        if (card.badgeCount > 0) ...[
          const SizedBox(height: 10),
          _BadgeCount(count: card.badgeCount),
        ],
      ],
    );
  }

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _month(DateTime when) =>
      '${_months[when.month - 1]} ${when.year}';

  static String _duration(int seconds) {
    final hours = seconds ~/ Duration.secondsPerHour;
    if (hours > 0) return '${hours}h';
    final minutes = seconds ~/ Duration.secondsPerMinute;
    return minutes > 0 ? '${minutes}m' : '${seconds}s';
  }

  static String _websiteLabel(String website) {
    final uri = Uri.tryParse(website);
    if (uri?.host case final String host when host.isNotEmpty) {
      return '${host.startsWith('www.') ? host.substring(4) : host}${uri!.path == '/' ? '' : uri.path}';
    }
    return website;
  }
}

class _CardIdentity extends StatelessWidget {
  const _CardIdentity({required this.card, required this.siteUrl});

  final UserCard card;
  final String siteUrl;
  static const double avatarSize = 64;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DAvatar.frame(
          child: SizedBox.square(
            dimension: avatarSize,
            child: AvatarImage(
              url: card.avatarUrl,
              size: avatarSize,
              fallback: ColoredBox(
                color: theme.shell.panel,
                child: Center(
                  child: Text(
                    card.username.isEmpty
                        ? '?'
                        : card.username.characters.first.toUpperCase(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '@${card.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              UserStatusMessage(
                siteUrl: siteUrl,
                userId: card.id,
                status: card.status,
                showDescription: true,
                size: 17,
                style: theme.textTheme.bodyMedium,
              ),
              if (card.title case final title?)
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
              if (card.isStaff || card.isSuspendedAt(DateTime.now())) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (card.isStaff)
                      _Badge(label: 'staff', color: theme.colorScheme.primary),
                    if (card.isSuspendedAt(DateTime.now()))
                      _Badge(
                        label: 'suspended',
                        color: theme.colorScheme.error,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
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
            : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
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
    return InlineAction.link(
      onTap: onTap!,
      semanticLabel: label,
      excludeChildSemantics: true,
      child: child,
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
    child: Text('$count badges'),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DBadge(
    backgroundColor: color.withValues(alpha: 0.18),
    foregroundColor: color,
    child: Text(label),
  );
}
