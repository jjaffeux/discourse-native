import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
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
    final shell = ShellScope.maybeIdentityOf(context);
    if (shell == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (chooseForum)
            DDropdownMenu(
              content: DDropdownMenuContent(
                width: 280,
                semanticLabel: 'Choose forum for new topic',
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
                  label: const Text('New topic'),
                  icon: const DIcon(DIcons.plus),
                  variant: DButtonVariant.transparentBackground,
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
          DButton.iconOnly(
            tooltip: 'Previous topic',
            icon: const RotatedBox(
              quarterTurns: 2,
              child: DIcon(DIcons.chevronDown),
            ),
            variant: DButtonVariant.transparentBackground,
            onPressed: onPrevious,
          ),
          DButton.iconOnly(
            tooltip: 'Next topic',
            icon: const DIcon(DIcons.chevronDown),
            variant: DButtonVariant.transparentBackground,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
