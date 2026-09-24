import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'shell_scope.dart';

typedef _InboxOwner = ({
  String? siteUrl,
  Object? session,
  String? tabId,
  String? routeId,
  String? sourceId,
  List<String> groups,
});

class MessageInboxTitle extends StatelessWidget {
  const MessageInboxTitle({
    super.key,
    required this.selectedGroup,
    this.trailing,
    this.keepTopicOpen = false,
  });

  final String? selectedGroup;
  final Widget? trailing;
  final bool keepTopicOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            child: MessageInboxSelector(
              selectedGroup: selectedGroup,
              keepTopicOpen: keepTopicOpen,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class MessageInboxSelector extends StatelessWidget {
  const MessageInboxSelector({
    super.key,
    required this.selectedGroup,
    this.keepTopicOpen = false,
    this.useSelect = false,
  });

  static const _personal = 'personal:';

  final String? selectedGroup;
  final bool keepTopicOpen;
  final bool useSelect;

  @override
  Widget build(BuildContext context) => ShellSelector<_InboxOwner>(
    select: (controller) {
      final instance = controller.currentInstance;
      return (
        siteUrl: instance?.url,
        session: instance == null
            ? null
            : controller.lifecycle.capture(instance.url).session,
        tabId: controller.activeTabId,
        routeId: controller.currentContent?.id,
        sourceId: controller.topicListContent?.id,
        groups: instance?.user?.messageGroupNames ?? const [],
      );
    },
    builder: (context, owner, _) {
      final controller = ShellScope.read(context);
      final lease = owner.siteUrl == null
          ? null
          : controller.lifecycle.capture(owner.siteUrl!);
      final groups = {
        ...owner.groups,
        // A restored inbox may precede a fresh membership payload. Preserve
        // its label while keeping Personal available as a way back.
        ?selectedGroup,
      };
      final value = selectedGroup == null ? _personal : 'group:$selectedGroup';
      final options = [
        const DMessageInboxOption(
          value: _personal,
          label: 'Personal',
          description: 'Private messages sent directly to you',
          icon: DIcon(DIcons.user),
        ),
        for (final group in groups)
          DMessageInboxOption(
            value: 'group:$group',
            label: group,
            description: 'Private messages sent to @$group',
            icon: const DIcon(DIcons.users),
          ),
      ];
      void select(String choice) {
        // Navigation or account replacement may precede the next frame that
        // removes the old popup.
        if (!context.mounted ||
            lease == null ||
            !lease.isCurrent ||
            controller.currentInstance?.url != owner.siteUrl ||
            controller.activeTabId != owner.tabId ||
            controller.currentContent?.id != owner.routeId ||
            controller.topicListContent?.id != owner.sourceId) {
          return;
        }
        controller.selectMessageInbox(
          choice == _personal ? null : choice.substring('group:'.length),
          keepTopicOpen: keepTopicOpen,
        );
      }

      return KeyedSubtree(
        key: ValueKey((controller, owner.siteUrl, owner.session, owner.tabId)),
        child: useSelect
            ? DSelect<String>.controlled(
                size: DControlSize.filter,
                key: const ValueKey('message-inbox-selector'),
                value: value,
                semanticLabel: 'Choose inbox',
                width: 160,
                valueBuilder: (context, value, item) => Row(
                  children: [
                    IconTheme.merge(
                      data: IconThemeData(
                        size: DControlStyle.iconDimension(
                          DControlSize.filter,
                          context: context,
                        ),
                        color: DTokens.of(context).mutedForeground,
                      ),
                      child: options
                          .firstWhere((option) => option.value == value)
                          .icon,
                    ),
                    const SizedBox(width: DSpacing.controlGap),
                    Flexible(child: Text(item!.textValue)),
                  ],
                ),
                entries: [
                  for (final option in options)
                    DSelectItem(
                      value: option.value,
                      textValue: option.label,
                      semanticLabel: option.description,
                      child: Text(option.label),
                    ),
                ],
                enabled: lease != null,
                onChanged: (choice) {
                  if (choice != null) select(choice);
                },
              )
            : DMessageInboxMenu<String>(
                buttonKey: const ValueKey('message-inbox-selector'),
                value: value,
                options: options,
                onChanged: lease == null ? null : select,
              ),
      );
    },
  );
}
