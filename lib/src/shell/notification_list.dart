import 'dart:async';

import 'package:flutter/material.dart';

import '../models/notification.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu_message.dart';

/// How a notification reads: an icon, who did it, and what they did.
///
/// Discourse's own rows are terser than this — an icon, the username, and the
/// topic title, with the icon left to carry the verb. Saying it in words
/// instead follows `SmallActionDescription`, and keeps a row legible when its
/// icon is one of the several that mean "something happened in a topic".
///
/// The wording follows Discourse's `notifications.*` strings so a notification
/// says the same thing here as it does on the web.
@immutable
class NotificationDescription {
  const NotificationDescription({
    required this.icon,
    required this.phrase,
    this.actor,
  });

  factory NotificationDescription.of(DiscourseNotification notification) {
    return NotificationDescription(
      icon: _icon(notification.kind),
      actor: _namesActor(notification.kind)
          // Every kind phrased as something somebody did arrives with a name
          // attached; this is only reached if one does not.
          ? notification.actor ?? 'Someone'
          : null,
      phrase: _phrase(notification),
    );
  }

  final DIconData icon;

  /// Who acted, drawn ahead of the phrase and heavier, or null for the kinds
  /// that are not about a person — a badge, a reminder, a site announcement —
  /// whose [phrase] is a whole sentence on its own.
  final String? actor;

  /// What happened, as it reads after [actor]: `replied to Better image
  /// handling`.
  final String phrase;

  /// Discourse names each notification's icon `notification.<type>` and
  /// resolves it through the REPLACEMENTS table that `tool/icons.txt` mirrors,
  /// so most kinds need nothing here. The rest are the ones whose icon
  /// Discourse sets in a render director instead, the three it draws with a
  /// `discourse-bell-*` glyph that is not in the sprites, and a bell for
  /// whatever we have never heard of.
  static DIconData _icon(NotificationKind kind) =>
      DIcons.byName['notification.${kind.wireName}'] ??
      switch (kind) {
        NotificationKind.posted ||
        NotificationKind.watchingCategoryOrTag ||
        NotificationKind.watchingFirstPost ||
        NotificationKind.followingCreatedTopic ||
        NotificationKind.chatMessage ||
        NotificationKind.chatInvitation => DIcons.comment,
        NotificationKind.followingReplied ||
        NotificationKind.chatWatchedThread => DIcons.reply,
        NotificationKind.chatMention => DIcons.at,
        NotificationKind.assigned => DIcons.userPlus,
        NotificationKind.newFeatures => DIcons.asterisk,
        NotificationKind.adminProblems => DIcons.triangleExclamation,
        _ => DIcons.bell,
      };

  /// False for the kinds that are not somebody doing something to you.
  static bool _namesActor(NotificationKind kind) => switch (kind) {
    NotificationKind.grantedBadge ||
    NotificationKind.groupMessageSummary ||
    NotificationKind.membershipRequestAccepted ||
    NotificationKind.membershipRequestConsolidated ||
    NotificationKind.topicReminder ||
    NotificationKind.bookmarkReminder ||
    NotificationKind.postApproved ||
    NotificationKind.votesReleased ||
    NotificationKind.chatWatchedThread ||
    NotificationKind.newFeatures ||
    NotificationKind.adminProblems ||
    NotificationKind.custom ||
    NotificationKind.unknown => false,
    _ => true,
  };

  static String _phrase(DiscourseNotification n) {
    // Discourse sends a title with every kind that has a topic, so these
    // stand-ins are for the malformed rest rather than for anything routine.
    final title = n.title.isEmpty ? 'a topic' : n.title;
    final group = n.groupName ?? 'a group';
    final channel = n.channelTitle ?? 'chat';

    return switch (n.kind) {
      NotificationKind.mentioned ||
      NotificationKind.groupMentioned => 'mentioned you in $title',
      NotificationKind.replied ||
      NotificationKind.followingReplied => 'replied to $title',
      NotificationKind.quoted => 'quoted you in $title',
      NotificationKind.edited => 'edited your post in $title',
      NotificationKind.liked => 'liked your post in $title',
      NotificationKind.reaction => 'reacted to your post in $title',
      NotificationKind.likedConsolidated => 'liked ${_posts(n.count)}',
      NotificationKind.linkedConsolidated => 'linked ${_posts(n.count)}',
      NotificationKind.linked => 'linked to your post from $title',
      NotificationKind.privateMessage => 'sent you $title',
      NotificationKind.invitedToPrivateMessage ||
      NotificationKind.invitedToTopic => 'invited you to $title',
      NotificationKind.inviteeAccepted => 'accepted your invitation',
      NotificationKind.posted ||
      NotificationKind.watchingCategoryOrTag => 'posted in $title',
      NotificationKind.watchingFirstPost ||
      NotificationKind.followingCreatedTopic => 'created $title',
      NotificationKind.movedPost => 'moved $title',
      NotificationKind.grantedBadge => switch (n.badgeName) {
        final badge? => 'You earned the $badge badge',
        null => 'You earned a badge',
      },
      NotificationKind.groupMessageSummary =>
        '${_plural(n.count, 'message')} in your $group inbox',
      NotificationKind.membershipRequestAccepted =>
        "You're now a member of $group",
      NotificationKind.membershipRequestConsolidated =>
        '${_plural(n.count, 'membership request')} for $group',
      NotificationKind.topicReminder ||
      NotificationKind.bookmarkReminder => 'Reminder: $title',
      NotificationKind.postApproved => 'Your post in $title was approved',
      NotificationKind.votesReleased => 'Your votes in $title were returned',
      NotificationKind.assigned => 'assigned $title to you',
      NotificationKind.chatMention => 'mentioned you in $channel',
      NotificationKind.chatQuoted => 'quoted you in $channel',
      NotificationKind.chatMessage => 'sent a message in $channel',
      NotificationKind.chatInvitation => 'invited you to $channel',
      NotificationKind.chatWatchedThread =>
        'There is a new reply in a thread you follow',
      NotificationKind.newFeatures => 'New features are available',
      NotificationKind.adminProblems =>
        'There is new advice on your site dashboard',
      // A kind from a plugin, or from a Discourse newer than this app. Its
      // title still says what it is about, and tapping it still goes there.
      NotificationKind.custom || NotificationKind.unknown =>
        n.title.isEmpty ? 'New notification' : n.title,
    };
  }

  static String _posts(int count) =>
      count <= 1 ? 'one of your posts' : '$count of your posts';

  static String _plural(int count, String noun) =>
      count == 1 ? '1 $noun' : '$count ${noun}s';
}

/// The notifications tab's contents: the site's own list.
///
/// Draws itself as a column rather than a list of its own, so that it scrolls
/// inside whichever of the menu's two forms is showing it — a popover with a
/// fixed height, or a sheet that is one long scroll.
class NotificationSection extends StatelessWidget {
  const NotificationSection({
    super.key,
    required this.siteUrl,
    required this.onOpened,
  });

  final String siteUrl;

  /// Closes the menu, once a tap has led somewhere. Not called for the few
  /// notifications that point at nothing reachable, which would otherwise
  /// close the menu onto an unchanged screen.
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<({ShellController controller, bool loaded})>(
        select: (controller) =>
            (controller: controller, loaded: controller.loaded),
        builder: (context, shell, _) => _NotificationSectionView(
          controller: shell.controller,
          controllerLoaded: shell.loaded,
          siteUrl: siteUrl,
          onOpened: onOpened,
        ),
      );
}

class _NotificationSectionView extends StatefulWidget {
  const _NotificationSectionView({
    required this.controller,
    required this.controllerLoaded,
    required this.siteUrl,
    required this.onOpened,
  });

  final ShellController controller;
  final bool controllerLoaded;
  final String siteUrl;
  final VoidCallback onOpened;

  @override
  State<_NotificationSectionView> createState() =>
      _NotificationSectionViewState();
}

class _NotificationSectionViewState extends State<_NotificationSectionView> {
  (ShellController, String)? _requestIdentity;
  (ShellController, String)? _loadedRequestIdentity;
  bool _requestInFlight = false;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(_NotificationSectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.siteUrl != widget.siteUrl ||
        (!oldWidget.controllerLoaded && widget.controllerLoaded)) {
      _request();
    }
  }

  void _request() {
    final controller = widget.controller;
    final siteUrl = widget.siteUrl;
    final identity = (controller, siteUrl);
    if (_loadedRequestIdentity == identity && controller.loaded) return;
    if (_requestIdentity == identity && _requestInFlight) return;
    _requestIdentity = identity;
    _requestInFlight = true;
    unawaited(_load(controller, siteUrl, identity));
  }

  Future<void> _load(
    ShellController controller,
    String siteUrl,
    (ShellController, String) identity,
  ) async {
    try {
      await controller.load();
      if (!mounted || _requestIdentity != identity || !controller.loaded) {
        return;
      }
      _loadedRequestIdentity = identity;
      await controller.loadNotifications(siteUrl);
    } catch (_) {
      return;
    } finally {
      if (_requestIdentity == identity) _requestInFlight = false;
    }
  }

  /// Marks the notification read, then follows it.
  ///
  /// A topic on a site in the rail is something this app has a view for, so it
  /// opens here. Everything else a notification points at — a badge, a group,
  /// a chat channel, the admin dashboard — is a page this app does not have,
  /// and belongs in the browser rather than nowhere.
  Future<void> _open(DiscourseNotification notification) async {
    final controller = widget.controller;
    controller.readNotification(widget.siteUrl, notification);

    final path = notification.path;
    if (path == null) return;

    final url = controller.absoluteUrl(path, siteUrl: widget.siteUrl);
    if (controller.openTopicUrl(url)) {
      widget.onOpened();
      return;
    }
    if (await openExternalLink(url) && mounted) widget.onOpened();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller.accountActivity.notificationsListenable,
      builder: (context, _) {
        final feed = controller.notificationsFor(widget.siteUrl);

        if (feed.error case final error?) {
          return UserMenuMessage(
            text: error,
            onRetry: () => controller.loadNotifications(widget.siteUrl),
          );
        }
        // Not loaded and not loading is the moment before the fetch this widget
        // asked for has started, which is a wait like any other.
        if (!feed.loaded) return const UserMenuMessage(text: null);
        if (feed.isEmpty) return const UserMenuMessage(text: 'Nothing new.');

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final notification in feed.notifications)
              NotificationRow(
                notification: notification,
                onTap: () => _open(notification),
              ),
          ],
        );
      },
    );
  }
}

/// One notification, drawn to the same measurements as the stand-in rows
/// around it in the other tabs.
class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.notification,
    required this.onTap,
  });

  final DiscourseNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = NotificationDescription.of(notification);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            // What is still unread is what the badge on the tab is counting,
            // so it is the one thing in the row worth a color.
            color: notification.isUnread
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: DIcon(
                  description.icon,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (description.actor case final actor?)
                        TextSpan(
                          text: '$actor ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      TextSpan(text: description.phrase),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
