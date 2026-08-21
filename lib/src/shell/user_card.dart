import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_card.dart';
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
  });

  final String username;
  final Widget child;
  final String? siteUrl;

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
      label: 'View profile for @$username',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(4),
          hoverColor: theme.shell.hover,
          focusColor: theme.shell.hover,
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
  final box = context.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;

  // Without a laid-out anchor there is nothing to attach to; fall back to the
  // middle of the screen rather than dropping the tap.
  final anchor = (box == null || overlay == null || !box.hasSize)
      ? null
      : Rect.fromPoints(
          box.localToGlobal(Offset.zero, ancestor: overlay),
          box.localToGlobal(
            box.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
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

  static const double width = 320;

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
      color: theme.shell.floating,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.shell.divider),
        ),
        child: child,
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.controller,
    required this.username,
    required this.siteUrl,
  });

  final ShellController controller;
  final String username;
  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final card = controller.userCard(username, siteUrl: siteUrl);
    if (card != null) {
      return _CardContent(card: card, siteUrl: siteUrl);
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
  const _CardContent({required this.card, required this.siteUrl});

  final UserCard card;
  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: AvatarImage(
                      url: card.avatarUrl,
                      size: 56,
                      fallback: ColoredBox(
                        color: theme.shell.panel,
                        child: Center(
                          child: Text(
                            card.username.isEmpty
                                ? '?'
                                : card.username.characters.first.toUpperCase(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '@${card.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (card.title case final title?) ...[
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                      if (card.isStaff || card.isSuspended) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            if (card.isStaff)
                              _Badge(
                                label: 'staff',
                                color: theme.colorScheme.primary,
                              ),
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
            ),
            if (card.bioExcerpt case final bio?) ...[
              const SizedBox(height: 14),
              CookedHtml(
                html: bio,
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                  height: DiscourseTypography.lineHeightCooked,
                ),
                siteUrl: siteUrl,
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                if (card.createdAt case final joined?)
                  _Stat(label: 'Joined', value: _month(joined)),
                if (card.lastPostedAt case final last?)
                  _Stat(label: 'Last post', value: _month(last)),
                if (card.badgeCount > 0)
                  _Stat(label: 'Badges', value: '${card.badgeCount}'),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => openExternalLink('$siteUrl${card.path}'),
                icon: const DIcon(DIcons.upRightFromSquare, size: 16),
                label: const Text('View profile'),
              ),
            ),
          ],
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
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
