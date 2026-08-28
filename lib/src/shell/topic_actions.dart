import 'dart:async';

import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/post.dart';
import '../models/post_flag.dart';
import '../models/topic.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'bookmark_ui.dart';
import 'choice_menu.dart';
import 'command_menu.dart';
import 'post_flag_editor.dart';
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
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          )
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
  share,
  flag,
  pinned,
  selectPosts,
  closed,
  archived,
  visible,
  delete,
  recover,
}

class TopicStatusButton extends StatelessWidget {
  const TopicStatusButton({
    super.key,
    required this.siteUrl,
    required this.topic,
    this.route,
    this.topicFlags = const [],
  });

  final String siteUrl;
  final TopicDetail topic;
  final ContentRoute? route;
  final List<PostFlagType> topicFlags;

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
            ? () => controller.openReplyAsNewTopic(
                topicContinuationMarkdown(
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

  void _flag(BuildContext context) {
    final controller = ShellScope.read(context);
    if (topicFlags.isEmpty ||
        controller.topicFlagWriteInFlight(siteUrl, topic.id)) {
      return;
    }
    unawaited(
      showTopicFlagEditor(
        context: context,
        siteUrl: siteUrl,
        topic: topic,
        flagTypes: topicFlags,
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
    if (deleted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete topic?'),
          content: const Text(
            'This removes the topic and all of its replies. Staff may be able '
            'to recover it later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('topic-delete-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    final error = await controller.setTopicDeleted(siteUrl, topic.id, deleted);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (deleted && controller.currentInstance?.user?.staff != true) {
      controller.handleBack(canReturnToSidebar: false);
    }
  }

  void _selectCommand(BuildContext context, _TopicCommand command) {
    switch (command) {
      case _TopicCommand.share:
        _share(context);
      case _TopicCommand.flag:
        _flag(context);
      case _TopicCommand.pinned:
        unawaited(_changePin(context));
      case _TopicCommand.selectPosts:
        final controller = ShellScope.read(context);
        controller.setTopicPostSelectionEnabled(
          siteUrl,
          topic.id,
          !controller.topicPostSelectionEnabled(siteUrl, topic.id),
        );
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

  @override
  Widget build(BuildContext context) {
    final hasStatusCommands =
        topic.canCloseTopic ||
        topic.canArchiveTopic ||
        topic.canToggleTopicVisibility;
    final hasPriorToDestructive = topic.canSelectPosts || hasStatusCommands;
    final hasMoreActions = route != null || topicFlags.isNotEmpty;
    final options = [
      if (route != null)
        const CommandMenuOption(
          value: _TopicCommand.share,
          label: 'Share topic',
          icon: DIcons.upRightFromSquare,
          key: ValueKey('topic-share-button'),
        ),
      if (topicFlags.isNotEmpty)
        CommandMenuOption(
          value: _TopicCommand.flag,
          label: 'Flag topic',
          icon: DIcons.flag,
          key: const ValueKey('topic-flag-button'),
          dividerBefore: route != null,
        ),
      if (topic.hasPinPreference)
        CommandMenuOption(
          value: _TopicCommand.pinned,
          label: topic.pinned ? 'Unpin topic' : 'Pin topic',
          icon: DIcons.thumbtack,
          key: const ValueKey('topic-pin-button'),
          dividerBefore: route != null || topicFlags.isNotEmpty,
        ),
      if (topic.canSelectPosts)
        CommandMenuOption(
          value: _TopicCommand.selectPosts,
          label: 'Select posts',
          icon: DIcons.list,
          key: const ValueKey('topic-select-posts'),
          dividerBefore: hasMoreActions || topic.hasPinPreference,
        ),
      if (topic.canCloseTopic)
        CommandMenuOption(
          value: _TopicCommand.closed,
          label: topic.closed ? 'Open topic' : 'Close topic',
          icon: DIcons.lock,
          key: const ValueKey('topic-status-closed'),
          dividerBefore:
              !topic.canSelectPosts &&
              (hasMoreActions || topic.hasPinPreference),
        ),
      if (topic.canArchiveTopic)
        CommandMenuOption(
          value: _TopicCommand.archived,
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
          value: _TopicCommand.visible,
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
          value: _TopicCommand.delete,
          label: 'Delete topic',
          icon: DIcons.trashCan,
          key: const ValueKey('topic-status-delete'),
          dividerBefore: hasPriorToDestructive,
          destructive: true,
        ),
      if (topic.canRecoverTopic)
        CommandMenuOption(
          value: _TopicCommand.recover,
          label: 'Recover topic',
          icon: DIcons.arrowRotateLeft,
          key: const ValueKey('topic-status-recover'),
          dividerBefore: !topic.canDeleteTopic && hasPriorToDestructive,
        ),
    ];
    return ShellSelector<bool>(
      select: (controller) =>
          controller.topicStatusWriteInFlight(siteUrl, topic.id) ||
          controller.topicDeletionWriteInFlight(siteUrl, topic.id) ||
          controller.topicPostSelectionWriteInFlight(siteUrl, topic.id) ||
          controller.topicPinWriteInFlight(siteUrl, topic.id) ||
          controller.topicFlagWriteInFlight(siteUrl, topic.id),
      builder: (context, busy, _) => CommandMenuAnchor<_TopicCommand>(
        title: 'More topic actions',
        options: options,
        enabled: !busy,
        onSelected: (command) => _selectCommand(context, command),
        builder: (context, openMenu) => DButton.iconOnly(
          key: const ValueKey('topic-status-button'),
          tooltip: 'More topic actions',
          onPressed: openMenu,
          loading: busy,
          variant: DButtonVariant.flat,
          size: DButtonSize.small,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const DIcon(DIcons.ellipsis, size: 18),
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

  static String _titleFor(TopicNotificationLevel level) => switch (level) {
    TopicNotificationLevel.watching => 'Watching',
    TopicNotificationLevel.tracking => 'Tracking',
    TopicNotificationLevel.normal => 'Normal',
    TopicNotificationLevel.muted => 'Muted',
  };

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    return ChoiceMenuAnchor<TopicNotificationLevel>(
      title: 'Topic notifications',
      showPopoverTitle: false,
      value: topic.notificationLevel,
      options: _options,
      onSelected: (level) => unawaited(
        controller.updateTopicNotificationLevel(siteUrl, topic.id, level),
      ),
      builder: (context, openMenu) => showLabel
          ? DButton(
              key: const ValueKey('topic-notification-level-button'),
              label: Text(_titleFor(topic.notificationLevel)),
              tooltip: 'Topic notifications',
              onPressed: openMenu,
              icon: DIcon(_iconFor(topic.notificationLevel), size: 18),
              variant:
                  topic.notificationLevel.index >=
                      TopicNotificationLevel.tracking.index
                  ? DButtonVariant.transparentPrimary
                  : DButtonVariant.flat,
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
  }
}
