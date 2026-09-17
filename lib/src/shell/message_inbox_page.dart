import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/topic_feed.dart';
import '../theme/d_icons.dart';
import 'content_reading_lane.dart';
import 'shell_scope.dart';
import 'topic_list_layout.dart';
import 'topic_list_view.dart';

class MessageInboxPage extends StatelessWidget {
  const MessageInboxPage({
    super.key,
    required this.feed,
    this.heading,
    this.keepTopicOpen = false,
  });

  final TopicFeed feed;
  final Widget? heading;
  final bool keepTopicOpen;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ?heading,
      _MessageListNavigation(keepTopicOpen: keepTopicOpen),
      Expanded(
        child: TopicListView(feed: feed, inbox: true, showHeader: false),
      ),
    ],
  );
}

class _MessageListNavigation extends StatelessWidget {
  const _MessageListNavigation({required this.keepTopicOpen});

  final bool keepTopicOpen;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<({MessageListMode mode, String? group})>(
        select: (controller) {
          final route =
              controller.topicListContent ?? controller.currentContent;
          return (
            mode: route?.messageListMode ?? MessageListMode.inbox,
            group: route?.messageGroupName,
          );
        },
        builder: (context, state, _) => ContentReadingLaneBox(
          widthLimit: topicListContentWidth,
          child: ConstrainedBox(
            key: const ValueKey('message-list-navigation'),
            constraints: const BoxConstraints(minHeight: 38),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: topicListHorizontalPadding,
                vertical: 8,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: DDropdownMenu(
                  content: DDropdownMenuContent(
                    width: 240,
                    semanticLabel: 'Message lists',
                    children: [
                      for (final mode in MessageListMode.values)
                        if (state.group == null || mode.supportsGroup)
                          DDropdownMenuItem(
                            key: ValueKey('message-list-${mode.name}'),
                            trailing: state.mode == mode
                                ? const DIcon(DIcons.check, size: 14)
                                : null,
                            onPressed: () =>
                                ShellScope.read(context).selectMessageListMode(
                                  mode,
                                  keepTopicOpen: keepTopicOpen,
                                ),
                            child: Text(mode.label),
                          ),
                    ],
                  ),
                  child: DDropdownMenuTrigger(
                    builder: (context, trigger) => DButton(
                      key: const ValueKey('message-list-menu'),
                      label: Text(state.mode.label),
                      icon: const DIcon(DIcons.chevronDown, size: 12),
                      iconPosition: DButtonIconPosition.end,
                      variant: DButtonVariant.secondary,
                      shape: DButtonShape.pill,
                      focusNode: trigger.focusNode,
                      hasPopup: true,
                      expanded: trigger.open,
                      onPressed: trigger.toggle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
