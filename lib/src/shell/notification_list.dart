import 'dart:async';

import 'package:flutter/material.dart';

import '../plugin_api/notification_feed_host.dart';
import '../plugin_api/notification_types.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import 'account_activity_loader.dart';
import 'adaptive_dialog_action.dart';
import 'external_link.dart';
import 'shell_controller.dart';
import 'site_emoji_text.dart';
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

enum _NotificationFeedKind { all, replies, other }

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

class OtherNotificationsSection extends StatelessWidget {
  const OtherNotificationsSection({
    super.key,
    required this.siteUrl,
    required this.onOpened,
  });

  final String siteUrl;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) =>
      AccountActivityLoader.otherNotifications(
        siteUrl: siteUrl,
        builder: (context, controller) => _NotificationSectionView(
          controller: controller,
          siteUrl: siteUrl,
          onOpened: onOpened,
          kind: _NotificationFeedKind.other,
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
    this.unreadCount = 0,
    this.viewAll,
    this.emptyStateAction,
  }) : assert(unreadCount >= 0);

  final String siteUrl;
  final VoidCallback onOpened;
  final PluginNotificationFeedHost host;
  final PluginNotificationFeedSource source;
  final int unreadCount;
  final PluginNotificationFeedLink? viewAll;
  final PluginNotificationFeedLink? emptyStateAction;

  @override
  State<PluginNotificationsSection> createState() =>
      _PluginNotificationsSectionState();
}

class _PluginNotificationsSectionState
    extends State<PluginNotificationsSection> {
  bool _dismissing = false;
  String? _dismissError;
  int _dismissRevision = 0;

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
    final identityChanged =
        oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.source.id != widget.source.id ||
        !identical(oldWidget.host, widget.host);
    if (identityChanged) {
      _dismissRevision++;
      _dismissing = false;
      _dismissError = null;
      unawaited(
        widget.host.loadPluginNotificationFeed(widget.siteUrl, widget.source),
      );
    } else if (widget.unreadCount == 0) {
      _dismissError = null;
    }
  }

  Future<void> _confirmDismiss() async {
    final dismissal = widget.source.dismissal;
    if (dismissal == null || _dismissing || widget.unreadCount <= 0) return;
    final revision = _dismissRevision;
    final host = widget.host;
    final source = widget.source;
    final siteUrl = widget.siteUrl;
    final confirmed = await showDiscourseDialog<bool>(
      context: context,
      builder: (dialogContext) => DiscourseAlertDialog(
        title: const Text('Mark notifications as read?'),
        content: Text(dismissal.confirmationMessage(widget.unreadCount)),
        actions: [
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          AdaptiveDialogAction(
            key: ValueKey(
              'plugin-notification-dismiss-confirm-${source.id.id}',
            ),
            kind: AdaptiveDialogActionKind.primary,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dismissal.buttonLabel),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        revision != _dismissRevision ||
        !identical(widget.host, host) ||
        widget.source != source ||
        widget.siteUrl != siteUrl) {
      return;
    }

    setState(() {
      _dismissing = true;
      _dismissError = null;
    });
    try {
      await host.dismissPluginNotifications(siteUrl, source);
    } catch (_) {
      if (mounted && revision == _dismissRevision) {
        setState(() {
          _dismissError = "Couldn't mark notifications as read. Try again.";
        });
      }
    } finally {
      if (mounted && revision == _dismissRevision) {
        setState(() => _dismissing = false);
      }
    }
  }

  Widget _withActions(Widget content, {required bool empty}) {
    final dismissal = widget.source.dismissal;
    final showAction =
        dismissal != null &&
        (widget.unreadCount > 0 || _dismissing || _dismissError != null);
    final dismissAction = showAction ? dismissal : null;
    final link = empty ? widget.emptyStateAction : widget.viewAll;
    if (dismissAction == null && link == null) return content;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dismissAction != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: DButton(
                key: ValueKey(
                  'plugin-notification-dismiss-${widget.source.id.id}',
                ),
                label: Text(dismissAction.buttonLabel),
                loadingLabel: Text(dismissAction.buttonLabel),
                tooltip: dismissAction.buttonTooltip,
                size: DButtonSize.small,
                variant: DButtonVariant.flat,
                loading: _dismissing,
                onPressed: widget.unreadCount > 0 ? _confirmDismiss : null,
              ),
            ),
          ),
        if (_dismissError case final error?)
          Semantics(
            liveRegion: true,
            child: Padding(
              key: ValueKey(
                'plugin-notification-dismiss-error-${widget.source.id.id}',
              ),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                error,
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
        content,
        if (link != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.center,
              child: DButton(
                key: ValueKey(
                  empty
                      ? 'plugin-notification-empty-action-${widget.source.id.id}'
                      : 'plugin-notification-view-all-${widget.source.id.id}',
                ),
                label: Text(link.label),
                variant: DButtonVariant.link,
                onPressed: () => unawaited(_openLink(link.path)),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openLink(String path) async {
    final url = widget.host.pluginAbsoluteUrl(path, siteUrl: widget.siteUrl);
    if (await widget.host.openPluginNotificationUrl(url)) {
      if (mounted) widget.onOpened();
      return;
    }
    if (mounted && await openExternalLink(url) && mounted) widget.onOpened();
  }

  Future<void> _open(DiscourseNotification notification, String? path) async {
    widget.host.readPluginNotification(widget.siteUrl, notification);
    if (path == null) return;
    await _openLink(path);
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
        return _withActions(
          UserMenuMessage(text: widget.source.emptyMessage),
          empty: true,
        );
      }
      final registry =
          PluginScope.maybeOf(context)?.registry ??
          PluginRegistryScope.maybeOf(context);
      return _withActions(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...feed.notifications.map((notification) {
              final resolved =
                  registry?.resolveNotification(notification) ??
                  resolveCoreNotification(notification);
              return NotificationRow(
                siteUrl: widget.siteUrl,
                notification: notification,
                resolved: resolved,
                onTap: () => _open(notification, resolved.path),
              );
            }),
          ],
        ),
        empty: false,
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
      _NotificationFeedKind.other => (
        controller.accountActivity.otherNotificationsListenable,
        () => controller.loadOtherNotifications(widget.siteUrl),
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
          _NotificationFeedKind.other => controller.otherNotificationsFor(
            widget.siteUrl,
          ),
        };

        if (currentFeed.error case final error?) {
          return UserMenuMessage(text: error, onRetry: retry);
        }
        if (!currentFeed.loaded) return const UserMenuMessage(text: null);
        if (currentFeed.isEmpty) {
          return UserMenuMessage(
            text: widget.kind == _NotificationFeedKind.other
                ? 'You don’t have any other notifications yet.'
                : 'Nothing new.',
          );
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
                siteUrl: widget.siteUrl,
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
    required this.siteUrl,
    required this.notification,
    required this.onTap,
    this.resolved,
  });

  final String siteUrl;
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
                    child: SiteEmojiText(
                      [
                        if (description.actor case final actor?)
                          SiteEmojiTextRun(
                            '$actor ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        SiteEmojiTextRun(description.phrase),
                      ],
                      siteUrl: siteUrl,
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
