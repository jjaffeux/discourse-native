import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../data/site_lifecycle.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/post_flag.dart';
import '../models/topic.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_dialog_action.dart';
import 'bookmark_ui.dart';
import 'choice_menu.dart';
import 'command_menu.dart';
import 'post_flag_editor.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_share.dart';

class TopicBookmarkButton extends StatelessWidget {
  const TopicBookmarkButton({
    super.key,
    required this.siteUrl,
    required this.topic,
    required this.busy,
    this.showLabel = false,
  });

  final String siteUrl;
  final TopicDetail topic;
  final bool busy;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final icon = busy
        ? const SizedBox.square(dimension: 18, child: DSpinner())
        : DIcon(
            topic.topicBookmark?.reminderAt != null
                ? DIcons.discourseBookmarkClock
                : topic.hasBookmarks
                ? DIcons.bookmark
                : DIcons.farBookmark,
            size: 18,
          );
    final tooltip = topic.hasBookmarks
        ? 'Manage ${topic.bookmarks.length} topic bookmark${topic.bookmarks.length == 1 ? '' : 's'}'
        : 'Bookmark this topic';
    final variant = topic.topicBookmark != null
        ? DButtonVariant.transparentPrimary
        : DButtonVariant.flat;
    void open() => unawaited(
      showTopicBookmarkMenu(
        context: context,
        controller: controller,
        siteUrl: siteUrl,
        topic: topic,
      ),
    );

    if (showLabel) {
      return DButton(
        key: const ValueKey('topic-bookmark-button'),
        onPressed: busy ? null : open,
        icon: icon,
        label: Text(topic.hasBookmarks ? 'Bookmarked' : 'Bookmark'),
        tooltip: tooltip,
        loading: busy,
        variant: variant,
        size: DButtonSize.small,
      );
    }
    return DButton.iconOnly(
      key: const ValueKey('topic-bookmark-button'),
      onPressed: busy ? null : open,
      icon: icon,
      tooltip: tooltip,
      loading: busy,
      variant: variant,
      size: DButtonSize.small,
    );
  }
}

enum _TopicCommand {
  flag,
  pinned,
  selectPosts,
  closed,
  archived,
  visible,
  delete,
  recover,
}

class TopicShareButton extends StatelessWidget {
  const TopicShareButton({
    super.key,
    required this.siteUrl,
    required this.topic,
    this.route,
  });

  final String siteUrl;
  final TopicDetail topic;
  final ContentRoute? route;

  void _share(BuildContext context) {
    final controller = ShellScope.read(context);
    final instance = controller.currentInstance;
    if (instance == null || instance.url != siteUrl) return;
    final slug = route?.slug;
    unawaited(
      showTopicShareSheet(
        context: context,
        title: topic.title,
        url: topicShareUrl(
          siteUrl: siteUrl,
          topicId: topic.id,
          slug: slug,
          config: instance.config,
          username: instance.user?.username,
        ),
        onReplyAsNewTopic: topic.canReplyAsNewTopic
            ? captureShareReplyAsNewTopic(
                context: context,
                siteUrl: siteUrl,
                topicId: topic.id,
                continuation: topicContinuationMarkdown(
                  title: topic.title,
                  url: topicShareUrl(
                    siteUrl: siteUrl,
                    topicId: topic.id,
                    slug: slug,
                    config: instance.config,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DButton.iconOnly(
      key: const ValueKey('topic-share-button'),
      onPressed: () => _share(context),
      icon: const DIcon(DIcons.link, size: 18),
      tooltip: 'Share topic',
      variant: DButtonVariant.flat,
      size: DButtonSize.small,
    );
  }
}

class TopicStatusButton extends StatelessWidget {
  const TopicStatusButton({
    super.key,
    required this.siteUrl,
    required this.topic,
    this.topicFlags = const [],
  });

  final String siteUrl;
  final TopicDetail topic;
  final List<PostFlagType> topicFlags;

  void _flag(BuildContext context) {
    final controller = ShellScope.read(context);
    final current = controller.store.read<TopicDetail>(siteUrl, topic.id);
    if (current == null ||
        controller.topicFlagWriteInFlight(siteUrl, topic.id)) {
      return;
    }
    final flags = controller.availableTopicFlagTypes(siteUrl, current);
    if (flags.isEmpty) return;
    unawaited(
      showTopicFlagEditor(
        context: context,
        siteUrl: siteUrl,
        topic: current,
        flagTypes: flags,
      ),
    );
  }

  Future<void> _changePin(BuildContext context) async {
    final error = await ShellScope.read(
      context,
    ).updateTopicPinPreference(siteUrl, topic.id, !topic.pinned);
    if (error == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _change(
    BuildContext context,
    TopicStatusProperty status,
    bool enabled,
  ) async {
    final controller = ShellScope.read(context);
    final error = await controller.updateTopicStatus(
      siteUrl,
      topic.id,
      status,
      enabled,
    );
    if (error == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _changeDeletion(BuildContext context, bool deleted) async {
    final controller = ShellScope.read(context);
    if (controller.accountSessionDisposed) return;
    final lease = controller.lifecycle.capture(siteUrl);
    final route = controller.currentContent;
    final tabId = controller.activeTabId;
    final staff = controller.instanceFor(siteUrl)?.user?.staff == true;
    final canNavigateBack =
        controller.forumActive &&
        controller.currentInstance?.url == siteUrl &&
        route?.topicId == topic.id;
    if (deleted) {
      final confirmed = await showDiscourseAlertDialog<bool>(
        context: context,
        title: const Text('Delete topic?'),
        description: const Text(
          'This removes the topic and all of its replies. Staff may be able '
          'to recover it later.',
        ),
        cancelLabel: const Text('Cancel'),
        actionLabel: const Text('Delete'),
        cancelResult: false,
        actionResult: true,
        actionKey: const ValueKey('topic-delete-confirm'),
        actionVariant: DButtonVariant.destructive,
      );
      if (confirmed != true || !context.mounted) return;
    }
    if (!lease.isCurrent || controller.accountSessionDisposed) return;
    final error = await controller.setTopicDeleted(siteUrl, topic.id, deleted);
    // The controller also returns null for retired work, so check the opening
    // session before interpreting its result.
    if (!context.mounted ||
        !lease.isCurrent ||
        controller.accountSessionDisposed) {
      return;
    }
    if (error != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (deleted &&
        !staff &&
        canNavigateBack &&
        controller.forumActive &&
        controller.currentInstance?.url == siteUrl &&
        controller.activeTabId == tabId &&
        identical(controller.currentContent, route)) {
      controller.handleBack(canReturnToSidebar: false);
    }
  }

  void _selectCommand(BuildContext context, _TopicCommand command) {
    final controller = ShellScope.read(context);
    if (_busy(controller)) return;
    final current = controller.store.read<TopicDetail>(siteUrl, topic.id);
    if (current == null) return;
    final allowed = switch (command) {
      _TopicCommand.flag =>
        controller.availableTopicFlagTypes(siteUrl, current).isNotEmpty,
      _TopicCommand.pinned => current.hasPinPreference,
      _TopicCommand.selectPosts => current.canSelectPosts,
      _TopicCommand.closed => current.canCloseTopic,
      _TopicCommand.archived => current.canArchiveTopic,
      _TopicCommand.visible => current.canToggleTopicVisibility,
      _TopicCommand.delete => current.canDeleteTopic,
      _TopicCommand.recover => current.canRecoverTopic,
    };
    if (!allowed) return;
    switch (command) {
      case _TopicCommand.flag:
        _flag(context);
      case _TopicCommand.pinned:
        unawaited(_changePin(context));
      case _TopicCommand.selectPosts:
        controller.setTopicPostSelectionEnabled(siteUrl, topic.id, true);
      case _TopicCommand.closed:
        unawaited(_change(context, TopicStatusProperty.closed, !topic.closed));
      case _TopicCommand.archived:
        unawaited(
          _change(context, TopicStatusProperty.archived, !topic.archived),
        );
      case _TopicCommand.visible:
        unawaited(
          _change(context, TopicStatusProperty.visible, !topic.visible),
        );
      case _TopicCommand.delete:
        unawaited(_changeDeletion(context, true));
      case _TopicCommand.recover:
        unawaited(_changeDeletion(context, false));
    }
  }

  bool _busy(ShellController controller) =>
      controller.topicStatusWriteInFlight(siteUrl, topic.id) ||
      controller.topicDeletionWriteInFlight(siteUrl, topic.id) ||
      controller.topicPostSelectionWriteInFlight(siteUrl, topic.id) ||
      controller.topicPinWriteInFlight(siteUrl, topic.id) ||
      controller.topicFlagWriteInFlight(siteUrl, topic.id);

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.identityOf(context);
    SiteLease? lease;
    bool ownsController() =>
        context.mounted &&
        !controller.accountSessionDisposed &&
        identical(ShellScope.read(context), controller);

    // The popup retains its options across anchor rebuilds. Each option must
    // retain the same topic and intent, and the account that opened it.
    void select(_TopicCommand command) {
      if (!ownsController() || lease?.isCurrent != true) return;
      _selectCommand(context, command);
    }

    final hasStatusCommands =
        topic.canCloseTopic ||
        topic.canArchiveTopic ||
        topic.canToggleTopicVisibility;
    final hasPriorToDestructive = topic.canSelectPosts || hasStatusCommands;
    final hasMoreActions = topicFlags.isNotEmpty;
    final options = [
      if (topicFlags.isNotEmpty)
        CommandMenuOption(
          value: () => select(_TopicCommand.flag),
          label: 'Flag topic',
          icon: DIcons.flag,
          key: const ValueKey('topic-flag-button'),
        ),
      if (topic.hasPinPreference)
        CommandMenuOption(
          value: () => select(_TopicCommand.pinned),
          label: topic.pinned ? 'Unpin topic' : 'Pin topic',
          icon: DIcons.thumbtack,
          key: const ValueKey('topic-pin-button'),
          dividerBefore: topicFlags.isNotEmpty,
        ),
      if (topic.canSelectPosts)
        CommandMenuOption(
          value: () => select(_TopicCommand.selectPosts),
          label: 'Select posts',
          icon: DIcons.list,
          key: const ValueKey('topic-select-posts'),
          dividerBefore: hasMoreActions || topic.hasPinPreference,
        ),
      if (topic.canCloseTopic)
        CommandMenuOption(
          value: () => select(_TopicCommand.closed),
          label: topic.closed ? 'Open topic' : 'Close topic',
          icon: DIcons.lock,
          key: const ValueKey('topic-status-closed'),
          dividerBefore:
              !topic.canSelectPosts &&
              (hasMoreActions || topic.hasPinPreference),
        ),
      if (topic.canArchiveTopic)
        CommandMenuOption(
          value: () => select(_TopicCommand.archived),
          label: topic.archived ? 'Unarchive topic' : 'Archive topic',
          icon: topic.archived ? DIcons.folderOpen : DIcons.folder,
          key: const ValueKey('topic-status-archived'),
          dividerBefore:
              !topic.canSelectPosts &&
              !topic.canCloseTopic &&
              (hasMoreActions || topic.hasPinPreference),
        ),
      if (topic.canToggleTopicVisibility)
        CommandMenuOption(
          value: () => select(_TopicCommand.visible),
          label: topic.visible ? 'Make topic unlisted' : 'Make topic visible',
          icon: topic.visible ? DIcons.farEyeSlash : DIcons.farEye,
          key: const ValueKey('topic-status-visible'),
          dividerBefore:
              !topic.canSelectPosts &&
              !topic.canCloseTopic &&
              !topic.canArchiveTopic &&
              (hasMoreActions || topic.hasPinPreference),
        ),
      if (topic.canDeleteTopic)
        CommandMenuOption(
          value: () => select(_TopicCommand.delete),
          label: 'Delete topic',
          icon: DIcons.trashCan,
          key: const ValueKey('topic-status-delete'),
          dividerBefore: hasPriorToDestructive,
          destructive: true,
        ),
      if (topic.canRecoverTopic)
        CommandMenuOption(
          value: () => select(_TopicCommand.recover),
          label: 'Recover topic',
          icon: DIcons.arrowRotateLeft,
          key: const ValueKey('topic-status-recover'),
          dividerBefore: !topic.canDeleteTopic && hasPriorToDestructive,
        ),
    ];
    return ShellSelector<bool>(
      select: _busy,
      builder: (context, busy, _) => CommandMenuAnchor<VoidCallback>(
        title: 'More topic actions',
        options: options,
        enabled: !busy,
        onSelected: (select) => select(),
        builder: (context, openMenu) => DButton.iconOnly(
          key: const ValueKey('topic-status-button'),
          tooltip: 'More topic actions',
          onPressed: openMenu == null
              ? null
              : () {
                  if (!ownsController() || _busy(controller)) return;
                  lease = controller.lifecycle.capture(siteUrl);
                  openMenu();
                },
          loading: busy,
          variant: DButtonVariant.flat,
          size: DButtonSize.small,
          icon: busy
              ? const SizedBox.square(dimension: 16, child: DSpinner())
              : const DIcon(DIcons.wrench, size: 16),
        ),
      ),
    );
  }
}

class TopicNotificationLevelButton extends StatelessWidget {
  const TopicNotificationLevelButton({
    super.key,
    required this.siteUrl,
    required this.topic,
    this.showLabel = false,
  });

  final String siteUrl;
  final TopicDetail topic;
  final bool showLabel;

  static const _options = [
    ChoiceMenuOption(
      value: TopicNotificationLevel.watching,
      title: 'Watching',
      description: 'Every reply and unread count',
      icon: DIcons.discourseBellExclamation,
    ),
    ChoiceMenuOption(
      value: TopicNotificationLevel.tracking,
      title: 'Tracking',
      description: 'Mentions, replies, and unread count',
      icon: DIcons.bell,
    ),
    ChoiceMenuOption(
      value: TopicNotificationLevel.normal,
      title: 'Normal',
      description: 'Mentions and replies only',
      icon: DIcons.farBell,
    ),
    ChoiceMenuOption(
      value: TopicNotificationLevel.muted,
      title: 'Muted',
      description: 'No notifications; hidden from Latest',
      icon: DIcons.discourseBellSlash,
    ),
  ];

  static DIconData _iconFor(TopicNotificationLevel level) => switch (level) {
    TopicNotificationLevel.watching => DIcons.discourseBellExclamation,
    TopicNotificationLevel.tracking => DIcons.bell,
    TopicNotificationLevel.normal => DIcons.farBell,
    TopicNotificationLevel.muted => DIcons.discourseBellSlash,
  };

  @override
  Widget build(BuildContext context) {
    return ShellSelector<Object>(
      select: (controller) => controller.lifecycle.capture(siteUrl).session,
      builder: (context, _, _) {
        final controller = ShellScope.read(context);
        final lease = controller.lifecycle.capture(siteUrl);
        return ChoiceMenuAnchor<TopicNotificationLevel>(
          key: ValueKey((controller, siteUrl, topic.id, lease.session)),
          title: 'Topic notifications',
          showPopoverTitle: false,
          value: topic.notificationLevel,
          options: _options,
          onSelected: (level) {
            // Account replacement can precede the anchor's next rebuild.
            if (!lease.isCurrent) return;
            unawaited(
              controller.updateTopicNotificationLevel(siteUrl, topic.id, level),
            );
          },
          builder: (context, openMenu) => showLabel
              ? DButton(
                  key: const ValueKey('topic-notification-level-button'),
                  label: Text(
                    _options
                        .firstWhere(
                          (option) => option.value == topic.notificationLevel,
                        )
                        .title,
                  ),
                  tooltip: 'Topic notifications',
                  onPressed: openMenu,
                  icon: DIcon(_iconFor(topic.notificationLevel), size: 15),
                  variant: DButtonVariant.flat,
                  size: DButtonSize.small,
                )
              : DButton.iconOnly(
                  key: const ValueKey('topic-notification-level-button'),
                  tooltip: 'Topic notifications',
                  onPressed: openMenu,
                  icon: DIcon(_iconFor(topic.notificationLevel), size: 18),
                  variant:
                      topic.notificationLevel.index >=
                          TopicNotificationLevel.tracking.index
                      ? DButtonVariant.transparentPrimary
                      : DButtonVariant.flat,
                  size: DButtonSize.small,
                ),
        );
      },
    );
  }
}
