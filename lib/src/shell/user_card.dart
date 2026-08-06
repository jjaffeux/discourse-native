import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_card.dart';
import '../theme/app_theme.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'external_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

/// Makes [child] open the card for [username] when clicked.
///
/// Wraps rather than replaces its child, so an avatar and a name can each be
/// their own target while pointing at the same account.
class UserCardTarget extends StatelessWidget {
  const UserCardTarget({
    super.key,
    required this.username,
    required this.child,
  });

  final String username;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (username.isEmpty) return child;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showUserCard(context: context, username: username),
        child: child,
      ),
    );
  }
}

/// The username a Discourse profile link points at, or null for anything else.
///
/// Only the profile root counts: `/u/someone/messages` is a page of its own,
/// not a person, and belongs in the browser.
String? usernameFromProfileUrl(Uri url) {
  final segments = url.pathSegments;
  if (segments.length != 2 || segments.first != 'u') return null;
  return segments[1].isEmpty ? null : segments[1];
}

/// Handles a tapped link that turns out to be a mention.
///
/// Returns false — leaving the link to whoever else wants it — when there is
/// no shell above [context] to ask, or when the URL is not a profile on the
/// site being read: a profile elsewhere is that site's page, and the card here
/// could only be fetched from this one.
bool showUserCardForUrl(BuildContext context, String url) {
  final instance = ShellScope.maybeOf(context)?.currentInstance;
  if (instance == null) return false;

  final uri = Uri.tryParse(url);
  if (uri == null || !instance.serves(uri)) return false;

  final username = usernameFromProfileUrl(uri);
  if (username == null) return false;

  showUserCard(context: context, username: username);
  return true;
}

/// Opens the card for [username], anchored to the widget at [context].
///
/// Anchored rather than centered because the card is an aside about the thing
/// you just clicked: it should read as attached to it, not as taking over.
Future<void> showUserCard({
  required BuildContext context,
  required String username,
}) {
  final controller = ShellScope.of(context);
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

  controller.loadUserCard(username);

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, animation, secondaryAnimation) => _UserCardPopup(
      controller: controller,
      username: username,
      anchor: anchor,
    ),
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
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
    required this.controller,
    required this.username,
    required this.anchor,
  });

  static const double width = 320;

  /// Gap between the card and whatever was clicked.
  static const double _gap = 8;

  /// Smallest gap between the card and the window edges.
  static const double _margin = 12;

  final ShellController controller;
  final String username;
  final Rect? anchor;

  @override
  Widget build(BuildContext context) {
    void dismiss() => Navigator.of(context).maybePop();

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): dismiss},
      child: Focus(
        autofocus: true,
        child: CustomSingleChildLayout(
          delegate: _AnchoredLayout(anchor: anchor, gap: _gap, margin: _margin),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _CardSurface(
              child: _CardBody(controller: controller, username: username),
            ),
          ),
        ),
      ),
    );
  }
}

/// Places the card under the anchor, flipping above it when there is no room.
class _AnchoredLayout extends SingleChildLayoutDelegate {
  const _AnchoredLayout({
    required this.anchor,
    required this.gap,
    required this.margin,
  });

  final Rect? anchor;
  final double gap;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = constraints.maxWidth - margin * 2;
    return BoxConstraints.loose(
      Size(
        math.min(_UserCardPopup.width, math.max(0, available)),
        math.max(0, constraints.maxHeight - margin * 2),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final target = anchor;
    if (target == null) {
      return Offset(
        (size.width - childSize.width) / 2,
        (size.height - childSize.height) / 2,
      );
    }

    final below = target.bottom + gap;
    final fitsBelow = below + childSize.height <= size.height - margin;
    final top = fitsBelow
        ? below
        : math.max(margin, target.top - gap - childSize.height);

    final maxLeft = math.max(margin, size.width - childSize.width - margin);
    return Offset(target.left.clamp(margin, maxLeft), top);
  }

  @override
  bool shouldRelayout(_AnchoredLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
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
  const _CardBody({required this.controller, required this.username});

  final ShellController controller;
  final String username;

  @override
  Widget build(BuildContext context) {
    final card = controller.userCard(username);
    if (card != null) return _CardContent(card: card, controller: controller);

    final error = controller.userCardError(username);
    if (error != null) {
      return _CardMessage(
        text: error,
        onRetry: () => controller.loadUserCard(username, force: true),
      );
    }
    return const _CardMessage(text: null);
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({required this.card, required this.controller});

  final UserCard card;
  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final siteUrl = controller.currentInstance?.url;

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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '@${card.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (card.title case final title?) ...[
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
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
              CookedHtml(html: bio, textStyle: theme.textTheme.bodySmall),
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
                onPressed: siteUrl == null
                    ? null
                    : () => openExternalLink('$siteUrl${card.path}'),
                icon: const Icon(Icons.open_in_new, size: 16),
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

/// The loading and failure states, which share the card's footprint so it does
/// not jump around once the account arrives.
class _CardMessage extends StatelessWidget {
  const _CardMessage({required this.text, this.onRetry});

  final String? text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = text;

    return SizedBox(
      height: 132,
      child: Center(
        child: message == null
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (onRetry case final retry?)
                      TextButton(onPressed: retry, child: const Text('Retry')),
                  ],
                ),
              ),
      ),
    );
  }
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
