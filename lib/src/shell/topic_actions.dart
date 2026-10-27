import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../app_shortcuts.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/post_flag.dart';
import '../models/topic.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'adaptive_dialog_action.dart';
import 'bookmark_ui.dart';
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
    this.variant,
    this.size = DButtonSize.chip,
    this.density = DButtonDensity.standard,
    this.buttonKey = const ValueKey('topic-bookmark-button'),
  });

  final String siteUrl;
  final TopicDetail topic;
  final bool busy;
  final DButtonVariant? variant;
  final DButtonSize size;
  final DButtonDensity density;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final icon = busy
        ? const DSpinner()
        : DIcon(
            topic.topicBookmark?.reminderAt != null
                ? DIcons.discourseBookmarkClock
                : topic.hasBookmarks
                ? DIcons.bookmark
                : DIcons.farBookmark,
          );
    final tooltip = topic.hasBookmarks
        ? context.l10n.manageTopicBookmark(topic.bookmarks.length)
        : context.l10n.bookmarkThisTopic;
    final buttonVariant = topic.topicBookmark != null && variant == null
        ? DButtonVariant.primary
        : variant ?? DButtonVariant.ghost;
    // A saved bookmark keeps the neutral surface and accents only its artwork.
    final selectedSurface =
        topic.topicBookmark != null && buttonVariant == DButtonVariant.outline
        ? DControlSurface(
            background: DTokens.of(context).buttonTheme.outline.background,
            hover: DTokens.of(context).buttonTheme.outline.hover,
            foreground: DTokens.of(context).primary,
          )
        : null;
    // A tool shares its group's fill, so only its artwork takes the accent.
    final selectedTool =
        topic.topicBookmark != null && buttonVariant == DButtonVariant.tool;
    void open() => unawaited(
      showTopicBookmarkMenu(
        context: context,
        controller: controller,
        siteUrl: siteUrl,
        topic: topic,
      ),
    );

    return DButton.iconOnly(
      key: buttonKey,
      onPressed: busy ? null : open,
      icon: icon,
      tooltip: tooltip,
      shortcut: const DShortcut(topicBookmarkShortcut),
      loading: busy,
      variant: buttonVariant,
      backgroundColor: selectedSurface?.background,
      foregroundColor:
          selectedSurface?.foreground ??
          (selectedTool ? DTokens.of(context).primary : null),
      interactiveBackgroundColor: selectedSurface?.hover,
      hasPopup: true,
      size: size,
      density: density,
    );
  }
}

/// The disabled [TopicBookmarkButton] shown while its topic loads.
class TopicBookmarkButtonPlaceholder extends StatelessWidget {
  const TopicBookmarkButtonPlaceholder({
    super.key,
    this.variant = DButtonVariant.ghost,
    this.size = DButtonSize.chip,
    this.density = DButtonDensity.standard,
  });

  final DButtonVariant variant;
  final DButtonSize size;
  final DButtonDensity density;

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    onPressed: null,
    icon: const DIcon(DIcons.farBookmark),
    tooltip: context.l10n.bookmarkThisTopic,
    shortcut: const DShortcut(topicBookmarkShortcut),
    variant: variant,
    hasPopup: true,
    size: size,
    density: density,
  );
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
        privateMessage: topic.privateMessage,
        onReplyAsNewTopic: controller.canReplyAsNewTopic(topic)
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
      icon: const DIcon(DIcons.link),
      tooltip: context.l10n.shareTopic,
      variant: DButtonVariant.ghost,
      size: DButtonSize.regular,
    );
  }
}

class TopicStatusButton extends StatefulWidget {
  const TopicStatusButton({
    super.key,
    required this.siteUrl,
    required this.topic,
    this.topicFlags = const [],
    this.variant = DButtonVariant.ghost,
    this.density = DButtonDensity.standard,
    this.size = DButtonSize.chip,
  });

  final String siteUrl;
  final TopicDetail topic;
  final List<PostFlagType> topicFlags;
  final DButtonVariant variant;
  final DButtonDensity density;
  final DButtonSize size;

  @override
  State<TopicStatusButton> createState() => _TopicStatusButtonState();

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
    DToast.show(context, error, type: DToastType.error);
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
    DToast.show(context, error, type: DToastType.error);
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
        title: Text(appL10n.deleteTopic),
        description: Text(
          appL10n.thisRemovesTheTopicAndAllOfItsRepliesStaffMay,
        ),
        cancelLabel: Text(appL10n.cancel),
        actionLabel: Text(appL10n.delete),
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
      DToast.show(context, error, type: DToastType.error);
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
      _TopicCommand.archived => current.canChangeStatus(
        TopicStatusProperty.archived,
      ),
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

  /// Staff's tools, a group each as the reference gathers them: picking
  /// posts, the topic's state, then deleting it.
  List<List<Widget>> _menuGroups(BuildContext context) {
    final controller = ShellScope.read(context);
    final lease = controller.lifecycle.capture(siteUrl);
    bool ownsController() =>
        context.mounted &&
        !controller.accountSessionDisposed &&
        identical(ShellScope.read(context), controller);

    // The popup retains its options across anchor rebuilds. Each option must
    // retain the same topic and intent, and the account that opened it.
    void select(_TopicCommand command) {
      if (!ownsController() || !lease.isCurrent) return;
      _selectCommand(context, command);
    }

    Widget menuIcon(DIconData icon) =>
        DIcon(icon, size: 13, color: DTokens.of(context).mutedForeground);
    return [
      [
        if (topic.canSelectPosts)
          DDropdownMenuItem(
            onPressed: () => select(_TopicCommand.selectPosts),
            key: const ValueKey('topic-select-posts'),
            leading: menuIcon(DIcons.list),
            leadingGap: 9,
            child: Text(context.l10n.selectPosts),
          ),
      ],
      [
        if (topic.canCloseTopic)
          DDropdownMenuItem(
            onPressed: () => select(_TopicCommand.closed),
            key: const ValueKey('topic-status-closed'),
            leading: menuIcon(DIcons.lock),
            leadingGap: 9,
            child: Text(
              topic.closed ? context.l10n.openTopic : context.l10n.closeTopic,
            ),
          ),
        if (topic.hasPinPreference)
          DDropdownMenuItem(
            onPressed: () => select(_TopicCommand.pinned),
            key: const ValueKey('topic-pin-button'),
            leading: menuIcon(DIcons.thumbtack),
            leadingGap: 9,
            child: Text(
              topic.pinned ? context.l10n.unpinTopic : context.l10n.pinTopic,
            ),
          ),
        if (topic.canChangeStatus(TopicStatusProperty.archived))
          DDropdownMenuItem(
            onPressed: () => select(_TopicCommand.archived),
            key: const ValueKey('topic-status-archived'),
            leading: menuIcon(
              topic.archived ? DIcons.folderOpen : DIcons.folder,
            ),
            leadingGap: 9,
            child: Text(
              topic.archived
                  ? context.l10n.unarchiveTopic
                  : context.l10n.archiveTopic,
            ),
          ),
        if (topic.canToggleTopicVisibility)
          DDropdownMenuItem(
            onPressed: () => select(_TopicCommand.visible),
            key: const ValueKey('topic-status-visible'),
            leading: menuIcon(
              topic.visible ? DIcons.farEyeSlash : DIcons.farEye,
            ),
            leadingGap: 9,
            child: Text(
              topic.visible
                  ? context.l10n.makeTopicUnlisted
                  : context.l10n.makeTopicVisible,
            ),
          ),
      ],
      [
        if (topic.canDeleteTopic)
          DDropdownMenuItem(
            onPressed: () => select(_TopicCommand.delete),
            key: const ValueKey('topic-status-delete'),
            leading: const DIcon(DIcons.trashCan, size: 13),
            leadingGap: 9,
            variant: DDropdownMenuItemVariant.destructive,
            child: Text(context.l10n.deleteTopicTopicactions),
          ),
        if (topic.canRecoverTopic)
          DDropdownMenuItem(
            onPressed: () => select(_TopicCommand.recover),
            key: const ValueKey('topic-status-recover'),
            leading: menuIcon(DIcons.arrowRotateLeft),
            leadingGap: 9,
            child: Text(context.l10n.recoverTopic),
          ),
      ],
    ];
  }

  List<Widget> _menuItems(BuildContext context) =>
      _ruledGroups(_menuGroups(context));

  /// Share, flag and mark unread: what anyone can do to the topic itself.
  /// [current] guards each against the account, tab or page having moved on.
  List<Widget> _moreItems(BuildContext context, bool Function() current) {
    final shell = ShellScope.read(context);
    final lease = shell.lifecycle.capture(siteUrl);
    final route = shell.currentContent;
    Widget menuIcon(DIconData icon) =>
        DIcon(icon, size: 13, color: DTokens.of(context).mutedForeground);
    return [
      DDropdownMenuItem(
        key: const ValueKey('topic-share-action'),
        leading: menuIcon(DNativeIcons.shareFromSquare),
        leadingGap: 9,
        onPressed: () {
          if (!current()) return;
          TopicShareButton(
            siteUrl: siteUrl,
            topic: topic,
            route: route,
          )._share(context);
        },
        child: Text(context.l10n.shareTopic),
      ),
      if (topicFlags.isNotEmpty)
        DDropdownMenuItem(
          key: const ValueKey('topic-flag-button'),
          leading: menuIcon(DIcons.flag),
          leadingGap: 9,
          onPressed: () {
            if (current()) _flag(context);
          },
          child: Text(context.l10n.flagTopicTopicactions),
        ),
      if (shell.instanceFor(siteUrl)?.isConnected == true)
        DDropdownMenuItem(
          key: const ValueKey('topic-mark-unread'),
          leading: menuIcon(DNativeIcons.envelopeOpen),
          leadingGap: 9,
          onPressed: shell.topicUnreadWriteInFlight(siteUrl, topic.id)
              ? null
              : () async {
                  if (!current()) return;
                  final error = await shell.markTopicUnread(siteUrl, topic.id);
                  if (context.mounted && lease.isCurrent && error != null) {
                    DToast.show(context, error, type: DToastType.error);
                  }
                },
          child: Text(context.l10n.markTopicUnread),
        ),
    ];
  }
}

/// The non-empty groups in order, a rule between each and the next.
List<Widget> _ruledGroups(Iterable<List<Widget>> groups) => [
  for (final (index, group) in groups.where((g) => g.isNotEmpty).indexed) ...[
    if (index > 0) const DDropdownMenuSeparator(),
    ...group,
  ],
];

class _TopicStatusButtonState extends State<TopicStatusButton> {
  List<Widget> _openItems = const [];

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.identityOf(context);
    final items = widget._menuItems(context);
    return ShellSelector<bool>(
      select: widget._busy,
      builder: (context, busy, _) => DButtonGroup.spaced(
        size: widget.size,
        children: [
          _TopicMoreActionsButton(status: widget),
          DDropdownMenu(
            sheetOnMobile: true,
            mobileSheetVariant: DSheetVariant.adaptiveMenu,
            onOpenChange: (open, reason) {
              if (open) {
                // Keep the displayed commands and their captured topic/account
                // together until dismissal, even when the header rebuilds.
                setState(() => _openItems = widget._menuItems(this.context));
              }
            },
            content: DDropdownMenuContent(
              semanticLabel: context.l10n.moreTopicActions,
              highlightInitialFocus: false,
              align: DPopoverAlign.end,
              width: 224,
              padding: DControlStyle.isTouch(context)
                  ? const EdgeInsets.fromLTRB(8, 0, 8, 8)
                  : DInsets.menu,
              children: _openItems,
            ),
            child: DDropdownMenuTrigger(
              builder: (context, state) => _topicStatusTrigger(
                key: const ValueKey('topic-status-button'),
                focusNode: state.focusNode,
                expanded: state.open,
                onPressed: busy || items.isEmpty
                    ? null
                    : () {
                        if (controller.accountSessionDisposed ||
                            !identical(ShellScope.read(context), controller) ||
                            widget._busy(controller)) {
                          return;
                        }
                        state.toggle();
                      },
                loading: busy,
                variant: widget.variant,
                density: widget.density,
                size: widget.size,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicMoreActionsButton extends StatefulWidget {
  const _TopicMoreActionsButton({required this.status});
  final TopicStatusButton status;
  @override
  State<_TopicMoreActionsButton> createState() =>
      _TopicMoreActionsButtonState();
}

class _TopicMoreActionsButtonState extends State<_TopicMoreActionsButton> {
  List<Widget>? _openItems;
  TopicStatusButton get status => widget.status;

  @override
  Widget build(BuildContext context) {
    final items = status._moreItems(
      context,
      _currentCheck(context, status.siteUrl),
    );
    return DDropdownMenu(
      sheetOnMobile: true,
      mobileSheetVariant: DSheetVariant.adaptiveMenu,
      onOpenChange: (open, _) =>
          setState(() => _openItems = open ? items : null),
      content: DDropdownMenuContent(
        width: 224,
        semanticLabel: context.l10n.topicActionsMenu,
        highlightInitialFocus: false,
        padding: DControlStyle.isTouch(context)
            ? const EdgeInsets.fromLTRB(8, 0, 8, 8)
            : DInsets.menu,
        children: _openItems ?? items,
      ),
      child: DDropdownMenuTrigger(
        builder: (context, state) => DButton.iconOnly(
          key: const ValueKey('topic-more-actions'),
          focusNode: state.focusNode,
          hasPopup: true,
          expanded: state.open,
          onPressed: state.toggle,
          variant: status.variant,
          size: status.size,
          density: status.density,
          tooltip: context.l10n.topicActionsMenu,
          icon: const DIcon(DIcons.ellipsis),
        ),
      ),
    );
  }
}

/// Whether a command chosen now still belongs to the account, tab and page
/// [context] showed when its menu was built.
bool Function() _currentCheck(BuildContext context, String siteUrl) {
  final shell = ShellScope.read(context);
  final lease = shell.lifecycle.capture(siteUrl);
  final tab = shell.activeTabId;
  final route = shell.currentContent;
  return () =>
      context.mounted &&
      lease.isCurrent &&
      identical(ShellScope.maybeRead(context), shell) &&
      shell.activeTabId == tab &&
      identical(shell.currentContent, route);
}

/// On a phone, where the head has no room for three buttons, one: what the
/// topic's plugins offer (assigning it), what anyone can do to it, then
/// staff's tools, a group each, in one sheet.
class TopicActionsButton extends StatefulWidget {
  const TopicActionsButton({
    super.key,
    required this.siteUrl,
    required this.topic,
    this.topicFlags = const [],
    this.sectionActions = const [],
  });

  final String siteUrl;
  final TopicDetail topic;
  final List<PostFlagType> topicFlags;
  final List<List<TopicPropertyAction>> sectionActions;

  @override
  State<TopicActionsButton> createState() => _TopicActionsButtonState();
}

class _TopicActionsButtonState extends State<TopicActionsButton> {
  List<Widget>? _openItems;

  @override
  Widget build(BuildContext context) {
    final status = TopicStatusButton(
      siteUrl: widget.siteUrl,
      topic: widget.topic,
      topicFlags: widget.topicFlags,
    );
    final current = _currentCheck(context, widget.siteUrl);
    Widget menuIcon(DIconData icon) =>
        DIcon(icon, size: 13, color: DTokens.of(context).mutedForeground);
    final items = _ruledGroups([
      for (final actions in widget.sectionActions)
        [
          for (final action in actions)
            DDropdownMenuItem(
              key: action.key,
              leading: menuIcon(action.icon),
              leadingGap: 9,
              // The sheet closes as it is chosen; the button stays to anchor
              // what the action opens.
              onPressed: () {
                if (current()) action.onSelected(this.context);
              },
              child: Text(action.label),
            ),
        ],
      status._moreItems(context, current),
      ...status._menuGroups(context),
    ]);
    return ShellSelector<bool>(
      select: status._busy,
      builder: (context, busy, _) => DDropdownMenu(
        sheetOnMobile: true,
        mobileSheetVariant: DSheetVariant.adaptiveMenu,
        onOpenChange: (open, _) =>
            setState(() => _openItems = open ? items : null),
        content: DDropdownMenuContent(
          width: 224,
          semanticLabel: context.l10n.topicActionsMenu,
          highlightInitialFocus: false,
          padding: DControlStyle.isTouch(context)
              ? const EdgeInsets.fromLTRB(8, 0, 8, 8)
              : DInsets.menu,
          children: _openItems ?? items,
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton.iconOnly(
            key: const ValueKey('topic-more-actions'),
            focusNode: state.focusNode,
            hasPopup: true,
            expanded: state.open,
            loading: busy,
            onPressed: busy ? null : state.toggle,
            variant: DButtonVariant.tool,
            size: DButtonSize.filter,
            tooltip: context.l10n.topicActionsMenu,
            icon: const DIcon(DIcons.ellipsis),
          ),
        ),
      ),
    );
  }
}

/// The disabled [TopicStatusButton] shown while its topic loads, so the
/// header's actions keep their place when the menu becomes available.
class TopicStatusButtonPlaceholder extends StatelessWidget {
  const TopicStatusButtonPlaceholder({
    super.key,
    this.variant = DButtonVariant.ghost,
    this.density = DButtonDensity.standard,
    this.size = DButtonSize.chip,
  });

  final DButtonVariant variant;
  final DButtonDensity density;
  final DButtonSize size;

  @override
  Widget build(BuildContext context) =>
      _topicStatusTrigger(variant: variant, density: density, size: size);
}

Widget _topicStatusTrigger({
  Key? key,
  FocusNode? focusNode,
  bool expanded = false,
  VoidCallback? onPressed,
  bool loading = false,
  required DButtonVariant variant,
  required DButtonDensity density,
  required DButtonSize size,
}) => DButton.iconOnly(
  key: key,
  tooltip: appL10n.moreTopicActions,
  focusNode: focusNode,
  hasPopup: true,
  expanded: expanded,
  onPressed: onPressed,
  loading: loading,
  variant: variant,
  size: size,
  density: density,
  icon: const DIcon(DIcons.wrench, size: 14),
);

class TopicNotificationLevelButton extends StatelessWidget {
  const TopicNotificationLevelButton({
    super.key,
    required this.siteUrl,
    required this.topic,
    this.showChevron = false,
    this.variant,
    this.size = DButtonSize.chip,
    this.density = DButtonDensity.standard,
    this.buttonKey = const ValueKey('topic-notification-level-button'),
  });

  final String siteUrl;
  final TopicDetail topic;
  final bool showChevron;
  final DButtonVariant? variant;
  final DButtonSize size;
  final DButtonDensity density;
  final Key buttonKey;

  static List<DNotificationLevelOption<TopicNotificationLevel>> get _options =>
      [
        DNotificationLevelOption(
          value: TopicNotificationLevel.watching,
          emphasized: true,
          label: appL10n.watching,
          description: appL10n.everyReplyAndUnreadCount,
          icon: const DIcon(DNativeIcons.bellRing),
        ),
        DNotificationLevelOption(
          value: TopicNotificationLevel.tracking,
          emphasized: true,
          label: appL10n.tracking,
          description: appL10n.mentionsRepliesAndUnreadCount,
          icon: const DIcon(DIcons.bell),
        ),
        DNotificationLevelOption(
          value: TopicNotificationLevel.normal,
          label: appL10n.normal,
          description: appL10n.mentionsAndRepliesOnly,
          icon: const DIcon(DIcons.bell),
        ),
        DNotificationLevelOption(
          value: TopicNotificationLevel.muted,
          label: appL10n.muted,
          description: appL10n.noNotificationsHiddenFromLatest,
          icon: const DIcon(DNativeIcons.bellOff),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return ShellSelector<Object>(
      select: (controller) => controller.lifecycle.capture(siteUrl).session,
      builder: (context, _, _) {
        final controller = ShellScope.read(context);
        final lease = controller.lifecycle.capture(siteUrl);
        return DNotificationLevelMenu<TopicNotificationLevel>(
          key: ValueKey((controller, siteUrl, topic.id, lease.session)),
          semanticLabel: context.l10n.topicNotifications,
          sheetOnMobile: true,
          mobileSheetVariant: DSheetVariant.adaptiveMenu,
          buttonKey: buttonKey,
          showChevron: showChevron,
          variant: variant,
          size: size,
          density: density,
          value: topic.notificationLevel,
          options: _options,
          onChanged: (level) {
            // Account replacement can precede the anchor's next rebuild.
            if (!lease.isCurrent) return;
            unawaited(
              controller.updateTopicNotificationLevel(siteUrl, topic.id, level),
            );
          },
        );
      },
    );
  }
}

/// The disabled [TopicNotificationLevelButton] shown while its topic loads,
/// at the default level until the topic's own level arrives.
class TopicNotificationLevelPlaceholder extends StatelessWidget {
  const TopicNotificationLevelPlaceholder({
    super.key,
    this.showChevron = false,
    this.variant,
    this.size = DButtonSize.chip,
    this.density = DButtonDensity.standard,
  });

  final bool showChevron;
  final DButtonVariant? variant;
  final DButtonSize size;
  final DButtonDensity density;

  @override
  Widget build(BuildContext context) =>
      DNotificationLevelMenu<TopicNotificationLevel>(
        semanticLabel: context.l10n.topicNotifications,
        showChevron: showChevron,
        variant: variant,
        size: size,
        density: density,
        value: TopicNotificationLevel.normal,
        options: TopicNotificationLevelButton._options,
        onChanged: null,
      );
}
