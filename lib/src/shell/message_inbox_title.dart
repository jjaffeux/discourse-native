import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'shell_scope.dart';

typedef _InboxOwner = ({
  String? siteUrl,
  Object? session,
  String? tabId,
  Object? routeIdentity,
  Object? sourceIdentity,
  List<String> groups,
});

class MessageInboxTitle extends StatelessWidget {
  const MessageInboxTitle({super.key, this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('message-inbox-title'),
    children: [
      Flexible(
        child: DText(
          context.l10n.messages,
          variant: DTextVariant.h3,
          headingLevel: 1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      ?trailing,
    ],
  );
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
  Widget build(BuildContext context) => ForumTabSelector<_InboxOwner>(
    select: (controller, tab) {
      final instance = controller.currentInstance;
      return (
        siteUrl: tab.isCurrent ? tab.siteUrl : null,
        session: tab.lease?.session,
        tabId: tab.tabId,
        routeIdentity: tab.currentContent?.destination.identity,
        sourceIdentity: tab.topicListContent?.destination.identity,
        groups: tab.isCurrent
            ? instance?.user?.messageGroupNames ?? const []
            : const [],
      );
    },
    builder: (context, owner, _) {
      final controller = ShellScope.read(context);
      final tab = ForumTabScope.tabOf(context);
      final lease = tab.lease;
      final groups = {
        ...owner.groups,
        // A restored inbox may precede a fresh membership payload. Preserve
        // its label while keeping Personal available as a way back.
        ?selectedGroup,
      };
      final value = selectedGroup == null ? _personal : 'group:$selectedGroup';
      final options = [
        DMessageInboxOption(
          value: _personal,
          label: context.l10n.personal,
          description: context.l10n.privateMessagesSentDirectlyToYou,
          icon: const DIcon(DIcons.user),
        ),
        for (final group in groups)
          DMessageInboxOption(
            value: 'group:$group',
            label: group,
            description: context.l10n.privateMessagesSentTo((group).toString()),
            icon: const DIcon(DIcons.users),
          ),
      ];
      void select(String choice) {
        // Navigation or account replacement may precede the next frame that
        // removes the old popup.
        if (!context.mounted ||
            lease == null ||
            !lease.isCurrent ||
            !identical(lease.session, owner.session) ||
            !tab.isCurrent ||
            controller.currentInstance?.url != owner.siteUrl ||
            tab.tabId != owner.tabId ||
            tab.currentContent?.destination.identity != owner.routeIdentity ||
            tab.topicListContent?.destination.identity !=
                owner.sourceIdentity) {
          return;
        }
        tab.selectMessageInbox(
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
                semanticLabel: context.l10n.chooseInbox,
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
                enabled: tab.isCurrent,
                onChanged: (choice) {
                  if (choice != null) select(choice);
                },
              )
            : DMessageInboxMenu<String>(
                buttonKey: const ValueKey('message-inbox-selector'),
                size: DButtonSize.filter,
                variant: DButtonVariant.secondary,
                value: value,
                options: options,
                onChanged: tab.isCurrent ? select : null,
              ),
      );
    },
  );
}
