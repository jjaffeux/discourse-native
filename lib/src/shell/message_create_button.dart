import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'shell_scope.dart';

class MessageCreateButton extends StatelessWidget {
  const MessageCreateButton({
    super.key,
    required this.showLabel,
    this.pill = false,
    this.fillWidth = false,
  });

  final bool showLabel;
  final bool pill;
  final bool fillWidth;

  void _compose(BuildContext context) {
    final controller = ShellScope.read(context);
    final instance = controller.currentInstance;
    final source = controller.topicListContent ?? controller.currentContent;
    if (instance == null || source?.isMessages != true) return;
    controller.openPrivateMessage(
      siteUrl: instance.url,
      targetRecipients: source!.messageGroupName ?? '',
    );
  }

  @override
  Widget build(BuildContext context) => ShellSelector<bool>(
    select: (controller) =>
        controller.currentInstance?.isConnected == true &&
        controller.currentInstance?.user?.canSendPrivateMessages == true,
    builder: (context, permitted, _) {
      if (!permitted) return const SizedBox.shrink();
      final button = showLabel
          ? DButton(
              key: const ValueKey('new-message-button'),
              label: const Text('New message', softWrap: true, maxLines: 2),
              shape: pill ? DButtonShape.pill : DButtonShape.rounded,
              icon: DIcon(pill ? DIcons.plus : DIcons.farPenToSquare),
              tooltip: 'New message',
              variant: DButtonVariant.primary,
              size: DButtonSize.action,
              onPressed: () => _compose(context),
            )
          : fillWidth
          ? DButton(
              key: const ValueKey('new-message-button'),
              label: const SizedBox.shrink(),
              semanticLabel: 'New message',
              icon: DIcon(pill ? DIcons.plus : DIcons.farPenToSquare),
              tooltip: 'New message',
              shape: pill ? DButtonShape.pill : DButtonShape.rounded,
              variant: DButtonVariant.primary,
              size: DButtonSize.action,
              onPressed: () => _compose(context),
            )
          : DButton.iconOnly(
              shape: pill ? DButtonShape.pill : DButtonShape.rounded,
              key: const ValueKey('new-message-button'),
              icon: DIcon(pill ? DIcons.plus : DIcons.farPenToSquare),
              tooltip: 'New message',
              variant: DButtonVariant.primary,
              size: DButtonSize.action,
              onPressed: () => _compose(context),
            );
      return button;
    },
  );
}
