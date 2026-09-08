import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/topic_feed.dart';
import '../theme/discourse_typography.dart';
import 'content_reading_lane.dart';
import 'forum_search.dart';
import 'list_navigation_tab.dart';
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
      final theme = Theme.of(context);
      final style = theme.textTheme.bodyMedium;
      final height = math.max(
        52.0,
        MediaQuery.textScalerOf(
                  context,
                ).scale(style?.fontSize ?? DiscourseTypography.sm) *
                (style?.height ?? DiscourseTypography.lineHeightSmall) +
            18,
      );
      return ContentReadingLaneBox(
        widthLimit: topicListContentWidth,
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            key: const ValueKey('message-list-navigation'),
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: topicListHorizontalPadding,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        height: height,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final mode in MessageListMode.values)
                              if (state.group == null || mode.supportsGroup)
                                Padding(
                                  padding: const EdgeInsets.only(right: 3),
                                  child: IntrinsicWidth(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minWidth: 48,
                                      ),
                                      child: ListNavigationTab(
                                        controlKey: ValueKey(
                                          'message-list-${mode.name}',
                                        ),
                                        label: mode.label,
                                        textStyle: style,
                                        selected: state.mode == mode,
                                        onTap: () => ShellScope.read(
                                          context,
                                        ).selectMessageListMode(mode),
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
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
