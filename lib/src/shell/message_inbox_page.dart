import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/topic_feed.dart';
import 'content_reading_lane.dart';
import 'forum_search.dart';
import 'message_create_button.dart';
import 'shell_scope.dart';
import 'title_bar.dart';
import 'topic_list_layout.dart';
import 'topic_list_view.dart';

class MessageInboxPage extends StatelessWidget {
  const MessageInboxPage({super.key, required this.feed});

  final TopicFeed feed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        // Narrow non-macOS headers keep room for the inbox identity. Search
        // remains mounted in the content lane when it cannot fit beside it.
        if (!ShellTitleBar.isSupported && constraints.maxWidth < 636)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ForumSearch(dense: true),
          ),
        const _MessageListNavigation(),
        Expanded(child: TopicListView(feed: feed)),
      ],
    ),
  );
}

class _MessageListNavigation extends StatelessWidget {
  const _MessageListNavigation();

  @override
  Widget build(
    BuildContext context,
  ) => ShellSelector<({MessageListMode mode, String? group})>(
    select: (controller) => (
      mode: controller.currentContent?.messageListMode ?? MessageListMode.inbox,
      group: controller.currentContent?.messageGroupName,
    ),
    builder: (context, state, _) {
      return ContentReadingLaneBox(
        widthLimit: topicListContentWidth,
        child: LayoutBuilder(
          builder: (context, constraints) => ConstrainedBox(
            key: const ValueKey('message-list-navigation'),
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: topicListHorizontalPadding,
                vertical: 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: DTabs<MessageListMode>.controlled(
                      value: state.mode,
                      onChanged: (mode) {
                        if (mode == null) return;
                        ShellScope.read(context).selectMessageListMode(mode);
                      },
                      children: [
                        DTabList<MessageListMode>(
                          variant: DTabListVariant.line,
                          children: [
                            for (final mode in MessageListMode.values)
                              if (state.group == null || mode.supportsGroup)
                                DTabTrigger(
                                  key: ValueKey('message-list-${mode.name}'),
                                  value: mode,
                                  child: Text(mode.label),
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  MessageCreateButton(
                    showLabel:
                        ContentReadingLane.breakpointWidthOf(
                          context,
                          constraints.maxWidth,
                        ) >=
                        760,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
