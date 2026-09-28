import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'shell_scope.dart';
import 'topic_create_button.dart';

/// Footer for plugin/combined sources which own their navigation separately.
class TopicSourceFooter extends StatelessWidget {
  const TopicSourceFooter({
    super.key,
    this.onPrevious,
    this.onNext,
    this.chooseForum = false,
  });
  final VoidCallback? onPrevious, onNext;
  final bool chooseForum;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.maybeOf(context);
    if (shell == null ||
        (!chooseForum &&
            !shell.canCreateTopicFromSidebar &&
            shell.currentContent?.isTopic != true)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (chooseForum)
            DDropdownMenu(
              content: DDropdownMenuContent(
                width: 280,
                semanticLabel: context.l10n.chooseForumForNewTopic,
                children: [
                  for (var index = 0; index < shell.instances.length; index++)
                    if (shell.instances[index].isConnected)
                      DDropdownMenuItem(
                        onPressed: () {
                          shell.selectInstance(index);
                          unawaited(shell.openNewTopicFromSidebar());
                        },
                        child: Text(shell.instances[index].title),
                      ),
                ],
              ),
              child: DDropdownMenuTrigger(
                builder: (context, trigger) => DButton(
                  label: Text(context.l10n.newTopic),
                  icon: const DIcon(DIcons.plus),
                  variant: DButtonVariant.primary,
                  focusNode: trigger.focusNode,
                  hasPopup: true,
                  expanded: trigger.open,
                  onPressed: trigger.toggle,
                ),
              ),
            )
          else if (shell.canCreateTopicFromSidebar)
            TopicCreateButton(
              compact: true,
              onPressed: () => unawaited(shell.openNewTopicFromSidebar()),
            ),
          const Spacer(),
          if (shell.currentContent?.isTopic == true) ...[
            DButton.iconOnly(
              tooltip: context.l10n.previousTopic,
              icon: const RotatedBox(
                quarterTurns: 2,
                child: DIcon(DIcons.chevronDown),
              ),
              variant: DButtonVariant.outline,
              onPressed: onPrevious,
            ),
            DButton.iconOnly(
              tooltip: context.l10n.nextTopic,
              icon: const DIcon(DIcons.chevronDown),
              variant: DButtonVariant.outline,
              onPressed: onNext,
            ),
          ],
        ],
      ),
    );
  }
}
