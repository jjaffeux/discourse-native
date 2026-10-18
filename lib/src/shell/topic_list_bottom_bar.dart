import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../app_shortcuts.dart';
import '../models/content_route.dart';
import '../models/forum_workspace.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'forum_theme_surfaces.dart';
import 'keyboard_navigation.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';

typedef _AdjacentTopics = ({int? previous, int? next, bool more, bool busy});

_AdjacentTopics _adjacentTopics(ShellController shell, ShellTabContext tab) {
  final feed = tab.currentFeed;
  final count = feed?.rowCount ?? 0;
  final topicId = tab.readingTopicId;
  final index = feed?.indexOfTopic(topicId ?? -1) ?? -1;
  final fallback = topicId != null && index < 0 && count > 0 ? 0 : null;
  return (
    previous: index > 0 ? index - 1 : fallback,
    next: topicId == null
        ? (count > 0 ? 0 : null)
        : index >= 0 && index + 1 < count
        ? index + 1
        : fallback,
    more: index >= 0 && index == count - 1 && tab.currentFeed?.hasMore == true,
    busy: tab.currentFeed?.loadingMore == true,
  );
}

bool openAdjacentTopic(
  BuildContext context, {
  required bool next,
  bool fromKeyboard = false,
}) {
  final shell = ShellScope.read(context);
  final tab = ForumTabScope.tabOf(context);
  final state = _adjacentTopics(shell, tab);
  final row = next ? state.next : state.previous;
  final instance = shell.currentInstance;
  if (instance == null || (row == null && !(next && state.more))) return false;
  final siteUrl = instance.url;
  final lease = shell.lifecycle.capture(siteUrl);
  final source = tab.currentFeedId;
  final route = tab.currentContent;
  final tabId = tab.activeTabId;
  final focus = FocusManager.instance.primaryFocus;

  Future<void> open() async {
    var targetRow = row;
    var cancelled = false;
    void checkOwner() {
      cancelled |=
          !context.mounted ||
          !identical(ShellScope.read(context), shell) ||
          !tab.isCurrent ||
          !lease.isCurrent ||
          !shell.isTabVisible(tab.tabId) ||
          shell.currentInstance?.url != siteUrl ||
          tab.activeTabId != tabId ||
          tab.currentFeedId != source ||
          tab.currentContent != route;
    }

    bool current() {
      checkOwner();
      return !cancelled &&
          (!fromKeyboard ||
              (navigationShortcutsAllowed(context) &&
                  FocusManager.instance.primaryFocus == focus));
    }

    void focusChanged() => cancelled = true;
    shell.addListener(checkOwner);
    if (fromKeyboard) FocusManager.instance.addListener(focusChanged);
    try {
      if (targetRow == null && source != null) {
        await tab.loadMoreFeed(source);
        if (!current()) return;
        targetRow = _adjacentTopics(shell, tab).next;
      }
      if (targetRow == null) return;
      var feed = tab.currentFeed;
      var target = feed?.topicIdAt(targetRow);
      if (source != null &&
          feed != null &&
          (target == null ||
              !shell.store.containsRecord<Topic>(siteUrl, target))) {
        final sourceRow = feed.sourceRowFor(targetRow);
        await shell.topicFeeds.ensureRange(
          instance: instance,
          destinationId: source,
          firstRow: sourceRow,
          lastRow: sourceRow,
        );
        if (!current()) return;
        final refreshed = _adjacentTopics(shell, tab);
        targetRow = next ? refreshed.next : refreshed.previous;
        feed = tab.currentFeed;
        target = targetRow == null ? null : feed?.topicIdAt(targetRow);
      }
      if (!current()) return;
      final topic = target == null
          ? null
          : shell.store.read<Topic>(siteUrl, target);
      if (topic != null) {
        final target = _readerBeside(shell, tab);
        (target == null ? tab : shell.tabContext(target)).openTopicFromList(
          topic,
          revealInList: true,
        );
      }
    } finally {
      shell.removeListener(checkOwner);
      if (fromKeyboard) FocusManager.instance.removeListener(focusChanged);
    }
  }

  unawaited(open());
  return true;
}

// The arrows follow the topic being read, which a desktop list can show in
// the other panel; selecting that reader keeps the list in place.
String? _readerBeside(ShellController shell, ShellTabContext tab) {
  final active = tab.activeTab;
  if (!shell.desktopPanelsEnabled ||
      active == null ||
      active.currentContent.isTopic) {
    return null;
  }
  final other = shell.selectedTabIn(
    active.panel == ForumPanel.main ? ForumPanel.secondary : ForumPanel.main,
  );
  if (other == null ||
      !other.currentContent.isTopic ||
      other.currentContent.topicId != tab.readingTopicId) {
    return null;
  }
  return other.id;
}

class TopicListBottomBar extends StatelessWidget {
  const TopicListBottomBar({super.key, this.leading, this.trailingInset = 0});

  final Widget? leading;
  final double trailingInset;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ShellScope.identityOf(context).topicFeeds,
    builder: (context, _) {
      final shell = ShellScope.of(context);
      final tab = ForumTabScope.tabOf(context);
      final topicOpen = tab.readingTopicId != null;
      if (leading == null &&
          !topicOpen &&
          !DismissNewTopicsButton.isVisible(shell, context: tab)) {
        return const SizedBox.shrink();
      }
      return TopicListFooter(
        trailingInset: trailingInset,
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              if (leading case final action?)
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: action,
                  ),
                )
              else
                const Spacer(),
              DismissNewTopicsButton(
                compact:
                    constraints.maxWidth <
                    480 * MediaQuery.textScalerOf(context).scale(14) / 14,
              ),
              if (topicOpen) const TopicNavigationButtons(),
            ],
          ),
        ),
      );
    },
  );
}

/// The production topic pane footer, also used by the appearance preview.
class TopicListFooter extends StatelessWidget {
  const TopicListFooter({
    super.key,
    required this.child,
    this.trailingInset = 0,
  });

  final Widget child;
  final double trailingInset;

  @override
  Widget build(BuildContext context) => DCardFooter(
    key: const ValueKey('topic-list-bottom-bar'),
    backgroundColor: context.isTouch
        ? Theme.of(context).shell.content
        : ForumWindowBackground.footerColor(
            context,
            DTokens.of(context).footerBackground,
          ),
    borderColor: context.isTouch ? null : DTokens.of(context).footerBorder,
    rounded: !context.isTouch,
    padding: EdgeInsets.zero,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: topicBottomBarHeight(context)),
      child: Padding(
        padding: topicBottomBarPadding.add(
          EdgeInsetsDirectional.only(end: trailingInset),
        ),
        child: child,
      ),
    ),
  );
}

/// Adjacent-topic actions following the current source list.
class TopicNavigationButtons extends StatelessWidget {
  const TopicNavigationButtons({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ShellScope.identityOf(context).topicFeeds,
    builder: (context, _) => ForumTabSelector<_AdjacentTopics>(
      select: _adjacentTopics,
      builder: (context, state, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DButton.iconOnly(
            key: const ValueKey('inbox-previous-topic'),
            tooltip:
                ForumTabScope.tabOf(context).topicListContent?.isMessages ==
                    true
                ? context.l10n.previousMessage
                : context.l10n.previousTopic,
            shortcut: DShortcut.sequence(
              ReadingCommand.openPreviousTopic.prefix!,
              ReadingCommand.openPreviousTopic.shortcuts.cast(),
            ),
            icon: const RotatedBox(
              quarterTurns: 2,
              child: DIcon(DIcons.chevronDown),
            ),
            onPressed: state.previous == null
                ? null
                : () => openAdjacentTopic(context, next: false),
            variant: DButtonVariant.outline,
            size: DButtonSize.regular,
          ),
          const SizedBox(width: DSpacing.xs),
          DButton.iconOnly(
            key: const ValueKey('inbox-next-topic'),
            tooltip:
                ForumTabScope.tabOf(context).topicListContent?.isMessages ==
                    true
                ? context.l10n.nextMessage
                : context.l10n.nextTopic,
            shortcut: DShortcut.sequence(
              ReadingCommand.openNextTopic.prefix!,
              ReadingCommand.openNextTopic.shortcuts.cast(),
            ),
            icon: const DIcon(DIcons.chevronDown),
            onPressed: state.next == null && (!state.more || state.busy)
                ? null
                : () => openAdjacentTopic(context, next: true),
            variant: DButtonVariant.outline,
            size: DButtonSize.regular,
          ),
        ],
      ),
    ),
  );
}

class DismissNewTopicsButton extends StatelessWidget {
  const DismissNewTopicsButton({super.key, this.compact = false});

  final bool compact;

  static bool isVisible(ShellController shell, {ShellTabContext? context}) {
    final tab = context ?? shell.focusedTabContext;
    return (tab.currentTopicListMode == TopicListMode.newActivity ||
            tab.currentTopicListMode == TopicListMode.newTopics ||
            tab.currentTopicListMode == TopicListMode.newReplies) &&
        (tab.canDismissNewTopics || tab.dismissingNewTopics);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ShellScope.identityOf(context).topicFeeds,
    builder: (context, _) {
      final shell = ShellScope.of(context);
      final tab = ForumTabScope.tabOf(context);
      if (!isVisible(shell, context: tab)) {
        return const SizedBox.shrink();
      }
      final label = switch (tab.currentTopicListMode) {
        TopicListMode.newTopics => context.l10n.dismissNewTopics,
        TopicListMode.newReplies => context.l10n.dismissNewReplies,
        _ => context.l10n.dismissNew,
      };
      final siteUrl = shell.currentInstance!.url;
      final lease = shell.lifecycle.capture(siteUrl);
      final tabId = tab.activeTabId;
      final route = tab.topicListContent;
      Future<void> dismiss() async {
        if (!context.mounted ||
            !tab.isCurrent ||
            !lease.isCurrent ||
            !identical(ShellScope.read(context), shell) ||
            shell.currentInstance?.url != siteUrl ||
            tab.activeTabId != tabId ||
            tab.topicListContent != route) {
          return;
        }
        final error = await tab.dismissNewTopics();
        if (context.mounted && lease.isCurrent && error != null) {
          DToast.show(context, error, type: DToastType.error);
        }
      }

      return Padding(
        padding: const EdgeInsetsDirectional.only(end: DSpacing.controlGap),
        child: compact
            ? DButton.iconOnly(
                key: const ValueKey('dismiss-new-topics'),
                tooltip: label,
                icon: const DIcon(DIcons.check),
                loading: tab.dismissingNewTopics,
                variant: DButtonVariant.outline,
                onPressed: tab.dismissingNewTopics ? null : dismiss,
              )
            : DButton(
                key: const ValueKey('dismiss-new-topics'),
                label: Text(label),
                loading: tab.dismissingNewTopics,
                variant: DButtonVariant.outline,
                onPressed: tab.dismissingNewTopics ? null : dismiss,
              ),
      );
    },
  );
}
