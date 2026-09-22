import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../app_shortcuts.dart';
import '../models/content_route.dart';
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

_AdjacentTopics _adjacentTopics(ShellController shell) {
  final ids = shell.currentFeed?.topicIds ?? const <int>[];
  final topicId = shell.currentContent?.topicId;
  final index = ids.indexOf(topicId ?? -1);
  final fallback = topicId != null && index < 0 ? ids.firstOrNull : null;
  return (
    previous: index > 0 ? ids[index - 1] : fallback,
    next: topicId == null
        ? ids.firstOrNull
        : index >= 0 && index + 1 < ids.length
        ? ids[index + 1]
        : fallback,
    more:
        index >= 0 &&
        index == ids.length - 1 &&
        shell.currentFeed?.hasMore == true,
    busy: shell.currentFeed?.loadingMore == true,
  );
}

bool openAdjacentTopic(
  BuildContext context, {
  required bool next,
  bool fromKeyboard = false,
}) {
  final shell = ShellScope.read(context);
  final state = _adjacentTopics(shell);
  final id = next ? state.next : state.previous;
  final siteUrl = shell.currentInstance?.url;
  if (siteUrl == null || (id == null && !(next && state.more))) return false;
  final lease = shell.lifecycle.capture(siteUrl);
  final source = shell.currentFeedId;
  final route = shell.currentContent;
  final tabId = shell.activeTabId;
  final focus = FocusManager.instance.primaryFocus;

  Future<void> open() async {
    var target = id;
    if (target == null && source != null) {
      var cancelled = false;
      void checkOwner() {
        cancelled |=
            !context.mounted ||
            !lease.isCurrent ||
            shell.currentInstance?.url != siteUrl ||
            shell.activeTabId != tabId ||
            shell.currentFeedId != source ||
            shell.currentContent != route;
      }

      void focusChanged() => cancelled = true;
      shell.addListener(checkOwner);
      if (fromKeyboard) FocusManager.instance.addListener(focusChanged);
      try {
        await shell.loadMoreFeed(source);
      } finally {
        shell.removeListener(checkOwner);
        if (fromKeyboard) FocusManager.instance.removeListener(focusChanged);
      }
      checkOwner();
      if (!context.mounted ||
          cancelled ||
          (fromKeyboard &&
              (!navigationShortcutsAllowed(context) ||
                  FocusManager.instance.primaryFocus != focus))) {
        return;
      }
      target = _adjacentTopics(shell).next;
    }
    final topic = target == null
        ? null
        : shell.store.read<Topic>(siteUrl, target);
    if (topic != null) {
      shell.openTopicFromList(topic, revealInList: true);
    }
  }

  unawaited(open());
  return true;
}

class TopicListBottomBar extends StatelessWidget {
  const TopicListBottomBar({super.key, this.leading, this.trailingInset = 0});

  final Widget? leading;
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
              ShellSelector<bool>(
                select: (shell) => shell.currentContent?.isTopic == true,
                builder: (context, topicOpen, _) => topicOpen
                    ? const TopicNavigationButtons()
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Adjacent-topic actions following the current source list.
class TopicNavigationButtons extends StatelessWidget {
  const TopicNavigationButtons({super.key, this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ShellScope.identityOf(context).topicFeeds,
    builder: (context, _) => ShellSelector<_AdjacentTopics>(
      select: _adjacentTopics,
      builder: (context, state, _) => Flex(
        direction: vertical ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: [
          DButton.iconOnly(
            key: const ValueKey('inbox-previous-topic'),
            tooltip:
                ShellScope.read(context).topicListContent?.isMessages == true
                ? 'Previous message'
                : 'Previous topic',
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
          SizedBox(
            width: vertical ? 0 : DSpacing.xs,
            height: vertical ? DSpacing.xs : 0,
          ),
          DButton.iconOnly(
            key: const ValueKey('inbox-next-topic'),
            tooltip:
                ShellScope.read(context).topicListContent?.isMessages == true
                ? 'Next message'
                : 'Next topic',
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ShellScope.identityOf(context).topicFeeds,
    builder: (context, _) {
      final shell = ShellScope.of(context);
      if (shell.currentTopicListMode != TopicListMode.newActivity &&
              shell.currentTopicListMode != TopicListMode.newTopics &&
              shell.currentTopicListMode != TopicListMode.newReplies ||
          (!shell.canDismissNewTopics && !shell.dismissingNewTopics)) {
        return const SizedBox.shrink();
      }
      final label = switch (shell.currentTopicListMode) {
        TopicListMode.newTopics => 'Dismiss new topics',
        TopicListMode.newReplies => 'Dismiss new replies',
        _ => 'Dismiss New',
      };
      Future<void> dismiss() async {
        final lease = shell.lifecycle.capture(shell.currentInstance!.url);
        final error = await shell.dismissNewTopics();
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
                loading: shell.dismissingNewTopics,
                variant: DButtonVariant.outline,
                onPressed: shell.dismissingNewTopics ? null : dismiss,
              )
            : DButton(
                key: const ValueKey('dismiss-new-topics'),
                label: Text(label),
                loading: shell.dismissingNewTopics,
                variant: DButtonVariant.outline,
                onPressed: shell.dismissingNewTopics ? null : dismiss,
              ),
      );
    },
  );
}
