import 'dart:async';

import 'package:flutter/material.dart';

import '../models/notification.dart';
import '../plugin_api/notification_feed_host.dart';
import '../plugin_api/notification_types.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icon.dart';
import 'account_activity_loader.dart';
import 'external_link.dart';
import 'shell_controller.dart';
import 'user_menu_message.dart';

@immutable
class NotificationDescription {
  const NotificationDescription({
    required this.icon,
    required this.phrase,
    this.actor,
  });

  factory NotificationDescription.of(DiscourseNotification notification) {
    return NotificationDescription.fromPresentation(
      resolveCoreNotification(notification).presentation,
    );
  }

  factory NotificationDescription.fromPresentation(
    NotificationPresentation presentation,
  ) => NotificationDescription(
    icon: presentation.icon,
    actor: presentation.actor,
    phrase: presentation.phrase,
  );

  final DIconData icon;

  final String? actor;

  final String phrase;
}

enum _NotificationFeedKind { all, replies }

class NotificationSection extends StatelessWidget {
  const NotificationSection({
    super.key,
    required this.siteUrl,
    required this.onOpened,
  });

  final String siteUrl;

  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) => AccountActivityLoader.notifications(
    siteUrl: siteUrl,
    builder: (context, controller) => _NotificationSectionView(
      controller: controller,
      siteUrl: siteUrl,
      onOpened: onOpened,
      kind: _NotificationFeedKind.all,
    ),
  );
}

class RepliesSection extends StatelessWidget {
  const RepliesSection({
    super.key,
    required this.siteUrl,
    required this.onOpened,
  });

  final String siteUrl;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) =>
      AccountActivityLoader.replyNotifications(
        siteUrl: siteUrl,
        builder: (context, controller) => _NotificationSectionView(
          controller: controller,
          siteUrl: siteUrl,
          onOpened: onOpened,
          kind: _NotificationFeedKind.replies,
        ),
      );
}

class PluginNotificationsSection extends StatefulWidget {
  const PluginNotificationsSection({
    super.key,
    required this.siteUrl,
    required this.onOpened,
    required this.host,
    required this.source,
  });

  final String siteUrl;
  final VoidCallback onOpened;
  final PluginNotificationFeedHost host;
  final PluginNotificationFeedSource source;

  @override
  State<PluginNotificationsSection> createState() =>
      _PluginNotificationsSectionState();
}

class _PluginNotificationsSectionState
    extends State<PluginNotificationsSection> {
  @override
  void initState() {
    super.initState();
    unawaited(
      widget.host.loadPluginNotificationFeed(widget.siteUrl, widget.source),
    );
  }

  @override
  void didUpdateWidget(PluginNotificationsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.source.id != widget.source.id ||
        !identical(oldWidget.host, widget.host)) {
      unawaited(
        widget.host.loadPluginNotificationFeed(widget.siteUrl, widget.source),
      );
    }
  }

  Future<void> _open(DiscourseNotification notification, String? path) async {
    widget.host.readPluginNotification(widget.siteUrl, notification);
    if (path == null) return;
    final url = widget.host.pluginAbsoluteUrl(path, siteUrl: widget.siteUrl);
    if (await widget.host.openPluginNotificationUrl(url)) {
      if (mounted) widget.onOpened();
      return;
    }
    if (mounted && await openExternalLink(url) && mounted) widget.onOpened();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.host.notificationFeedListenable(widget.source.id),
    builder: (context, _) {
      final feed = widget.host.notificationFeedFor(
        widget.source.id,
        widget.siteUrl,
      );
      if (feed.error case final error?) {
        return UserMenuMessage(
          text: error,
          onRetry: () => widget.host.loadPluginNotificationFeed(
            widget.siteUrl,
            widget.source,
          ),
        );
      }
      if (!feed.loaded) return const UserMenuMessage(text: null);
      if (feed.isEmpty) {
        return UserMenuMessage(text: widget.source.emptyMessage);
      }
      final registry =
          PluginScope.maybeOf(context)?.registry ??
          PluginRegistryScope.maybeOf(context);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...feed.notifications.map((notification) {
            final resolved =
                registry?.resolveNotification(notification) ??
                resolveCoreNotification(notification);
            return NotificationRow(
              notification: notification,
              resolved: resolved,
              onTap: () => _open(notification, resolved.path),
            );
          }),
        ],
      );
    },
  );
}

class _NotificationSectionView extends StatefulWidget {
  const _NotificationSectionView({
    required this.controller,
    required this.siteUrl,
    required this.onOpened,
    required this.kind,
  });

  final ShellController controller;
  final String siteUrl;
  final VoidCallback onOpened;
  final _NotificationFeedKind kind;

  @override
  State<_NotificationSectionView> createState() =>
      _NotificationSectionViewState();
}

class _NotificationSectionViewState extends State<_NotificationSectionView> {
  Future<void> _open(DiscourseNotification notification, String? path) async {
    final controller = widget.controller;
    controller.readNotification(widget.siteUrl, notification);

    if (path == null) return;

    final url = controller.absoluteUrl(path, siteUrl: widget.siteUrl);
    if (await controller.openNotificationUrl(url)) {
      if (mounted) widget.onOpened();
      return;
    }
    if (!mounted) return;
    if (await openExternalLink(url) && mounted) widget.onOpened();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final (listenable, retry) = switch (widget.kind) {
      _NotificationFeedKind.all => (
        controller.accountActivity.notificationsListenable,
        () => controller.loadNotifications(widget.siteUrl),
      ),
      _NotificationFeedKind.replies => (
        controller.accountActivity.replyNotificationsListenable,
        () => controller.loadReplyNotifications(widget.siteUrl),
      ),
    };
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final currentFeed = switch (widget.kind) {
          _NotificationFeedKind.all => controller.notificationsFor(
            widget.siteUrl,
          ),
          _NotificationFeedKind.replies => controller.replyNotificationsFor(
            widget.siteUrl,
          ),
        };

        if (currentFeed.error case final error?) {
          return UserMenuMessage(text: error, onRetry: retry);
        }
        if (!currentFeed.loaded) return const UserMenuMessage(text: null);
        if (currentFeed.isEmpty) {
          return const UserMenuMessage(text: 'Nothing new.');
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...currentFeed.notifications.map((notification) {
              final resolved = controller.plugins.registry.resolveNotification(
                notification,
              );
              return NotificationRow(
                notification: notification,
                resolved: resolved,
                onTap: () => _open(notification, resolved.path),
              );
            }),
          ],
        );
      },
    );
  }
}

class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.notification,
    required this.onTap,
    this.resolved,
  });

  final DiscourseNotification notification;
  final VoidCallback onTap;
  final ResolvedNotification? resolved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = resolved == null
        ? NotificationDescription.of(notification)
        : NotificationDescription.fromPresentation(resolved!.presentation);
    final line = switch (description.actor) {
      final actor? => '$actor ${description.phrase}',
      null => description.phrase,
    };
    final accessibilityLabel = notification.isUnread ? '$line, unread' : line;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Semantics(
        key: ValueKey('notification-row-${notification.id}'),
        label: accessibilityLabel,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
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
        ),
      ),
    );
  }
}
