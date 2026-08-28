import 'package:flutter/material.dart';

import '../models/topic_feed.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'choice_menu.dart';
import 'shell_scope.dart';
import 'topic_list_view.dart';

/// The connected account's personal and group private-message inboxes.
class MessageInboxPage extends StatelessWidget {
  const MessageInboxPage({super.key, required this.feed});

  static const String _personal = 'personal:';
  static String _groupValue(String group) => 'group:$group';

  final TopicFeed feed;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<({List<String> groups, String? selectedGroup})>(
      select: (controller) => (
        groups: controller.currentInstance?.user?.messageGroupNames ?? const [],
        selectedGroup: controller.currentContent?.messageGroupName,
      ),
      builder: (context, inboxes, _) {
        final selectedGroup = inboxes.selectedGroup;
        final groups = [
          ...inboxes.groups,
          // A restored route may briefly predate a fresh session payload. Keep
          // its identity visible until that refresh settles, while Personal
          // remains available as a safe way out if membership changed.
          if (selectedGroup != null && !inboxes.groups.contains(selectedGroup))
            selectedGroup,
        ];
        if (groups.isEmpty) return TopicListView(feed: feed);

        return Column(
          children: [
            _MessageInboxPicker(groups: groups, selectedGroup: selectedGroup),
            Expanded(child: TopicListView(feed: feed)),
          ],
        );
      },
    );
  }
}

class _MessageInboxPicker extends StatelessWidget {
  const _MessageInboxPicker({
    required this.groups,
    required this.selectedGroup,
  });

  final List<String> groups;
  final String? selectedGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = selectedGroup == null
        ? MessageInboxPage._personal
        : MessageInboxPage._groupValue(selectedGroup!);
    final options = [
      const ChoiceMenuOption(
        value: MessageInboxPage._personal,
        title: 'Personal',
        description: 'Private messages sent directly to you',
        icon: DIcons.user,
      ),
      for (final group in groups)
        ChoiceMenuOption(
          value: MessageInboxPage._groupValue(group),
          title: group,
          description: 'Private messages sent to @$group',
          icon: DIcons.users,
        ),
    ];

    return Container(
      key: const ValueKey('message-inbox-picker'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: Row(
        children: [
          Text(
            'Inbox',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: ChoiceMenuAnchor<String>(
              title: 'Choose an inbox',
              showPopoverTitle: false,
              value: value,
              options: options,
              onSelected: (choice) =>
                  ShellScope.read(context).selectMessageInbox(
                    choice == MessageInboxPage._personal
                        ? null
                        : choice.substring('group:'.length),
                  ),
              builder: (context, openMenu) => DButton(
                key: const ValueKey('message-inbox-selector'),
                onPressed: openMenu,
                label: Text(
                  selectedGroup ?? 'Personal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                icon: const DIcon(DIcons.chevronDown, size: 14),
                tooltip: 'Choose inbox',
                variant: DButtonVariant.standard,
                size: DButtonSize.small,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
