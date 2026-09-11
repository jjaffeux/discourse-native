import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../app_shortcuts.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'keyboard_navigation.dart';
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
    next: index >= 0 && index + 1 < ids.length ? ids[index + 1] : fallback,
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
      shell.openTopicFromList(topic, fromKeyboard: fromKeyboard);
    }
  }

  unawaited(open());
  return true;
}

class TopicListBottomBar extends StatelessWidget {
  const TopicListBottomBar({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ShellScope.identityOf(context).topicFeeds,
    builder: (context, _) => ShellSelector<_AdjacentTopics>(
      select: _adjacentTopics,
      builder: (context, state, _) => ColoredBox(
        key: const ValueKey('topic-list-bottom-bar'),
        color: Theme.of(context).shell.content,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).shell.divider),
            ),
          ),
          child: SizedBox(
            height: topicBottomBarHeight(context),
            child: Padding(
              padding: topicBottomBarPadding,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  DButton.iconOnly(
                    key: const ValueKey('inbox-previous-topic'),
                    tooltip: 'Previous topic',
                    shortcut: DShortcut.sequence(
                      ReadingCommand.openPreviousTopic.prefix!,
                      ReadingCommand.openPreviousTopic.shortcuts.cast(),
                    ),
                    icon: const DIcon(DIcons.chevronLeft, size: 13),
                    onPressed: state.previous == null
                        ? null
                        : () => openAdjacentTopic(context, next: false),
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.small,
                  ),
                  DButton.iconOnly(
                    key: const ValueKey('inbox-next-topic'),
                    tooltip: 'Next topic',
                    shortcut: DShortcut.sequence(
                      ReadingCommand.openNextTopic.prefix!,
                      ReadingCommand.openNextTopic.shortcuts.cast(),
                    ),
                    icon: const DIcon(DIcons.chevronRight, size: 13),
                    onPressed: state.next == null && (!state.more || state.busy)
                        ? null
                        : () => openAdjacentTopic(context, next: true),
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.small,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
