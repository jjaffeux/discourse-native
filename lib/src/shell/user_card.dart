import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_card.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'external_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu_message.dart';
import 'user_status.dart';

final _userCardTransitionCurve = CurveTween(curve: Curves.easeOutCubic);

/// Makes [child] open the card for [username] when clicked.
///
/// Wraps rather than replaces its child, so an avatar and a name can each be
/// their own target while pointing at the same account.
class UserCardTarget extends StatelessWidget {
  const UserCardTarget({
    super.key,
    required this.username,
    required this.child,
    this.siteUrl,
    this.semanticsLabel,
  }) : _backgroundFeedback = true;

  /// An avatar target that only switches to the hand cursor under a pointer.
  ///
  /// Keyboard focus remains visible for people navigating without a pointer.
  const UserCardTarget.avatar({
    super.key,
    required this.username,
    required this.child,
    this.siteUrl,
    this.semanticsLabel,
  }) : _backgroundFeedback = false;

  final String username;
  final Widget child;
  final String? siteUrl;
  final String? semanticsLabel;
  final bool _backgroundFeedback;

  @override
  Widget build(BuildContext context) {
    if (username.isEmpty) return child;
    final theme = Theme.of(context);

    void open() => unawaited(
      showUserCard(context: context, username: username, siteUrl: siteUrl),
    );

    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel ?? 'View profile for @$username',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(4),
          hoverColor: _backgroundFeedback
              ? theme.shell.hover
              : Colors.transparent,
          focusColor: theme.shell.hover,
          highlightColor: _backgroundFeedback ? null : Colors.transparent,
          splashColor: _backgroundFeedback ? null : Colors.transparent,
          onTap: open,
          child: ExcludeSemantics(child: child),
        ),
      ),
    );
  }
}

/// The username a Discourse profile link points at, or null for anything else.
///
/// Only the profile root counts: `/u/someone/messages` is a page of its own,
/// not a person, and belongs in the browser. On a subfolder install the root
/// is `<base>/u/someone`, so the segments before the trailing pair must be
/// exactly [siteUrl]'s base path — anything else, like a topic whose slug
/// happens to be `u`, is not a profile. Without a site, only `/u/someone`
/// itself can be trusted.
String? usernameFromProfileUrl(Uri url, {String? siteUrl}) {
  final segments = url.pathSegments;
  if (segments.length < 2 || segments[segments.length - 2] != 'u') return null;
  final username = segments.last;
  if (username.isEmpty) return null;

  final base = siteUrl == null
      ? const <String>[]
      : (Uri.tryParse(siteUrl)?.pathSegments ?? const [])
            .where((segment) => segment.isNotEmpty)
            .toList();
  final leading = segments.sublist(0, segments.length - 2);
  return listEquals(leading, base) ? username : null;
}

/// Handles a tapped link that turns out to be a mention.
///
/// Returns false — leaving the link to whoever else wants it — when there is
/// no shell above [context] to ask, or when the URL is not a profile on the
/// site being read: a profile elsewhere is that site's page, and the card here
/// could only be fetched from this one.
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

/// Opens the card for [username], anchored to the widget at [context].
///
/// Anchored rather than centered because the card is an aside about the thing
/// you just clicked: it should read as attached to it, not as taking over.
Future<void> showUserCard({
  required BuildContext context,
  required String username,
  String? siteUrl,
}) {
  final controller = ShellScope.read(context);
  final targetSite = siteUrl ?? controller.currentInstance?.url;
  if (targetSite == null) return Future<void>.value();
  // Without a laid-out anchor there is nothing to attach to; fall back to the
  // middle of the screen rather than dropping the tap.
  final anchor = anchorRect(
    anchor: context.findRenderObject() as RenderBox?,
    overlay:
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?,
  );

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _UserCardPopup(username: username, siteUrl: targetSite, anchor: anchor),
    transitionBuilder: (context, animation, secondary, child) {
      final curved = animation.drive(_userCardTransitionCurve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          alignment: Alignment.topLeft,
          child: child,
        ),
      );
    },
  );
}

class _UserCardPopup extends StatelessWidget {
  const _UserCardPopup({
    required this.username,
    required this.siteUrl,
    required this.anchor,
  });

  /// Matches the web card's 39em canvas at Discourse's 16px base size.
  static const double width = 624;

  /// Gap between the card and whatever was clicked.
  static const double _gap = 8;

  /// Smallest gap between the card and the window edges.
  static const double _margin = 12;

  final String username;
  final String siteUrl;
  final Rect? anchor;

  @override
  Widget build(BuildContext context) => ShellSelector<ShellController>(
    select: (controller) => controller,
    builder: (context, controller, _) => _ControllerUserCardPopup(
      key: ObjectKey(controller),
      controller: controller,
      username: username,
      siteUrl: siteUrl,
      anchor: anchor,
    ),
  );
}

class _ControllerUserCardPopup extends StatefulWidget {
  const _ControllerUserCardPopup({
    super.key,
    required this.controller,
    required this.username,
    required this.siteUrl,
    required this.anchor,
  });

  final ShellController controller;
  final String username;
  final String siteUrl;
  final Rect? anchor;

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
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    await controller.loadUserCard(widget.username, siteUrl: widget.siteUrl);
  }

  @override
  Widget build(BuildContext context) {
    void dismiss() => Navigator.of(context).maybePop();

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): dismiss},
      child: Focus(
        autofocus: true,
        child: CustomSingleChildLayout(
          delegate: AnchoredLayout(
            anchor: widget.anchor,
            maxWidth: _UserCardPopup.width,
            gap: _UserCardPopup._gap,
            margin: _UserCardPopup._margin,
          ),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => _CardSurface(
              child: _CardBody(
                controller: widget.controller,
                username: widget.username,
                siteUrl: widget.siteUrl,
                close: dismiss,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      key: const ValueKey<String>('user-card-surface'),
      color: theme.shell.floating,
      elevation: 8,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      // A `Container`, not a `DecoratedBox`: a bordered decoration's
      // dimensions are padding a `Container` applies and a `DecoratedBox`
      // does not, so the panel's contents would sit under its own border and
      // be clipped by the rounded `Material` around it.
      child: SizedBox(
        width: double.infinity,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.shell.divider),
          ),
          child: child,
        ),
      ),
    );
  }
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
    return const UserMenuMessage(text: null, height: 132);
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
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 500;
            final profileAction = SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  close();
                  unawaited(openExternalLink('$siteUrl${card.path}'));
                },
                icon: const DIcon(DIcons.upRightFromSquare, size: 16),
                label: const Text('View profile'),
              ),
            );
            final actions = [...pluginActions, profileAction];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (narrow) ...[
                  _CardIdentity(
                    card: card,
                    siteUrl: siteUrl,
                    avatarSize: 88,
                    compact: true,
                  ),
                  const SizedBox(height: 12),
                  _CardActions(actions: actions, horizontal: true),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _CardIdentity(
                          card: card,
                          siteUrl: siteUrl,
                          avatarSize: 112,
                          compact: false,
                        ),
                      ),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: 156,
                        child: _CardActions(actions: actions),
                      ),
                    ],
                  ),
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
                          icon: const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                          ),
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
                        _Metadata(
                          label: 'Time read',
                          value: _duration(card.timeRead),
                        ),
                    ],
                  ),
                ],
                if (card.badgeCount > 0) ...[
                  const SizedBox(height: 10),
                  _BadgeCount(count: card.badgeCount),
                ],
              ],
            );
          },
        ),
      ),
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
  const _CardIdentity({
    required this.card,
    required this.siteUrl,
    required this.avatarSize,
    required this.compact,
  });

  final UserCard card;
  final String siteUrl;
  final double avatarSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(
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
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: compact
                      ? DiscourseTypography.fontUp3
                      : DiscourseTypography.fontUp5,
                  height: DiscourseTypography.lineHeightMedium,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '@${card.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
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
              if (card.isStaff || card.isSuspended) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (card.isStaff)
                      _Badge(label: 'staff', color: theme.colorScheme.primary),
                    if (card.isSuspended)
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
  const _CardActions({required this.actions, this.horizontal = false});

  final List<Widget> actions;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    if (!horizontal) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(height: 6),
            actions[index],
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = actions.length == 1
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
    return InkWell(onTap: onTap, child: child);
  }
}

class _BadgeCount extends StatelessWidget {
  const _BadgeCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.shell.panel,
        border: Border.all(color: theme.shell.divider),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DIcon(DIcons.certificate, size: 16),
          const SizedBox(width: 5),
          Text('$count badges', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
