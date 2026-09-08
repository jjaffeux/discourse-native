import 'package:flutter/material.dart';

import '../../discourse_ui.dart' show DSeparator;
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'choice_menu.dart';
import 'shell_scope.dart';

class MessageInboxTitle extends StatelessWidget {
  const MessageInboxTitle({
    super.key,
    required this.selectedGroup,
    this.trailing,
  });

  static const _personal = 'personal:';

  final String? selectedGroup;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ShellSelector<List<String>>(
    select: (controller) =>
        controller.currentInstance?.user?.messageGroupNames ?? const [],
    builder: (context, memberships, _) {
      final theme = Theme.of(context);
      final groups = [
        ...memberships,
        // A restored inbox may precede a fresh membership payload. Preserve
        // its label while keeping Personal available as a way back.
        if (selectedGroup != null && !memberships.contains(selectedGroup))
          selectedGroup!,
      ];
      return Row(
        key: const ValueKey('message-inbox-title'),
        children: [
          Flexible(
            child: Text(
              'Messages',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DSeparator(
            orientation: Axis.vertical,
            length: 18,
            space: 21,
            color: theme.shell.divider,
          ),
          Flexible(
            flex: 2,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: ChoiceMenuAnchor<String>(
                key: const ValueKey('message-inbox-picker'),
                title: 'Choose an inbox',
                showPopoverTitle: false,
                value: selectedGroup == null
                    ? _personal
                    : 'group:$selectedGroup',
                options: [
                  const ChoiceMenuOption(
                    value: _personal,
                    title: 'Personal',
                    description: 'Private messages sent directly to you',
                    icon: DIcons.user,
                  ),
                  for (final group in groups)
                    ChoiceMenuOption(
                      value: 'group:$group',
                      title: group,
                      description: 'Private messages sent to @$group',
                      icon: DIcons.users,
                    ),
                ],
                onSelected: (choice) =>
                    ShellScope.read(context).selectMessageInbox(
                      choice == _personal
                          ? null
                          : choice.substring('group:'.length),
                    ),
                builder: (context, openMenu) => DButton(
                  key: const ValueKey('message-inbox-selector'),
                  onPressed: openMenu,
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          selectedGroup ?? 'Personal',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const DIcon(DIcons.chevronDown, size: 10),
                    ],
                  ),
                  icon: DIcon(
                    selectedGroup == null ? DIcons.user : DIcons.users,
                    size: 14,
                  ),
                  tooltip: 'Choose inbox',
                  semanticLabel: 'Choose inbox: ${selectedGroup ?? 'Personal'}',
                  variant: DButtonVariant.flat,
                  size: DButtonSize.small,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      );
    },
  );
}
