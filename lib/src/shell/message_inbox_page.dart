import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/topic_feed.dart';
import '../theme/d_icons.dart';
import 'message_inbox_title.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'topic_list_view.dart';

class MessageInboxPage extends StatelessWidget {
  const MessageInboxPage({
    super.key,
    required this.feed,
    this.actions,
    this.keepTopicOpen = false,
  });

  final TopicFeed feed;
  final Widget? actions;
  final bool keepTopicOpen;

  @override
  Widget build(BuildContext context) => DPageSurface.headed(
    title: Row(
      children: [
        if (context.isTouch &&
            (!ShellScope.read(context).mobileNavigationEnabled ||
                ForumTabScope.tabOf(context).canPopContent))
          DButton.iconOnly(
            icon: const DIcon(DIcons.arrowLeft),
            tooltip: context.l10n.back,
            variant: DButtonVariant.ghost,
            onPressed: () =>
                ShellScope.read(context).handleBack(canReturnToSidebar: true),
          ),
        Expanded(child: Text(context.l10n.messages)),
      ],
    ),
    controls:
        ForumTabScope.tabOf(context).currentContent?.isSearchList != true &&
            ForumTabScope.tabOf(context).topicListContent?.isSearchList != true
        ? Row(
            children: [
              Expanded(
                child: _MessageListNavigation(keepTopicOpen: keepTopicOpen),
              ),
              ?actions,
            ],
          )
        : null,
    child: TopicListView(feed: feed, inbox: true),
  );
}

class _MessageListNavigation extends StatelessWidget {
  const _MessageListNavigation({required this.keepTopicOpen});

  final bool keepTopicOpen;

  @override
  Widget build(BuildContext context) =>
      ForumTabSelector<({MessageListMode mode, String? group})>(
        select: (controller, tab) {
          final route = tab.topicListContent ?? tab.currentContent;
          return (
            mode: route?.messageListMode ?? MessageListMode.inbox,
            group: route?.messageGroupName,
          );
        },
        builder: (context, state, _) {
          if (context.isTouch) {
            final controller = ShellScope.read(context);
            return Row(
              key: const ValueKey('message-list-navigation'),
              spacing: DSpacing.controlGap,
              children: [
                Flexible(
                  child: SizedBox(
                    width: 120,
                    child: DSelect<MessageListMode>.controlled(
                      size: DControlSize.filter,
                      key: const ValueKey('message-list-menu'),
                      value: state.mode,
                      semanticLabel: context.l10n.messageLists,
                      width: 120,
                      entries: [
                        for (final mode in MessageListMode.values)
                          if (state.group == null || mode.supportsGroup)
                            DSelectItem(
                              value: mode,
                              textValue: mode.label,
                              child: Text(
                                mode.label,
                                key: ValueKey('message-list-${mode.name}'),
                              ),
                            ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) {
                          controller.selectMessageListMode(
                            mode,
                            keepTopicOpen: keepTopicOpen,
                          );
                        }
                      },
                    ),
                  ),
                ),
                Flexible(
                  child: SizedBox(
                    width: 160,
                    child: MessageInboxSelector(
                      selectedGroup: state.group,
                      keepTopicOpen: keepTopicOpen,
                      useSelect: true,
                    ),
                  ),
                ),
              ],
            );
          }
          return Row(
            key: const ValueKey('message-list-navigation'),
            spacing: DSpacing.sm,
            children: [
              Flexible(
                child: DDropdownMenu(
                  content: DDropdownMenuContent(
                    width: 240,
                    semanticLabel: context.l10n.messageLists,
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
                      size: DButtonSize.filter,
                      focusNode: trigger.focusNode,
                      hasPopup: true,
                      expanded: trigger.open,
                      onPressed: trigger.toggle,
                    ),
                  ),
                ),
              ),
              Flexible(
                flex: 2,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: MessageInboxSelector(
                    selectedGroup: state.group,
                    keepTopicOpen: keepTopicOpen,
                  ),
                ),
              ),
            ],
          );
        },
      );
}
