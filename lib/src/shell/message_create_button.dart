import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'shell_scope.dart';

class MessageCreateButton extends StatelessWidget {
  const MessageCreateButton({super.key, required this.showLabel});

  final bool showLabel;

  Future<void> _compose(BuildContext context) async {
    final controller = ShellScope.read(context);
    final instance = controller.currentInstance;
    final user = instance?.user;
    final tabId = controller.activeTabId;
    final route = controller.currentContent;
    final source = controller.topicListContent ?? route;
    if (instance == null || user == null || source?.isMessages != true) return;
    final lease = controller.lifecycle.capture(instance.url);
    final recipients =
        source!.messageGroupName ??
        await showDialog<String>(
          context: context,
          builder: (_) => const _MessageRecipientsDialog(),
        );
    if (!context.mounted ||
        recipients == null ||
        !lease.isCurrent ||
        controller.currentInstance?.url != instance.url ||
        controller.activeTabId != tabId ||
        controller.currentInstance?.user?.id != user.id ||
        controller.currentContent != route ||
        controller.topicListContent != source) {
      return;
    }
    controller.openPrivateMessage(
      siteUrl: instance.url,
      targetRecipients: recipients,
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
              icon: const DIcon(DIcons.farPenToSquare),
              tooltip: 'New message',
              variant: DButtonVariant.primary,
              size: DButtonSize.regular,
              onPressed: () => unawaited(_compose(context)),
            )
          : DButton.iconOnly(
              key: const ValueKey('new-message-button'),
              icon: const DIcon(DIcons.farPenToSquare),
              tooltip: 'New message',
              variant: DButtonVariant.primary,
              size: DButtonSize.regular,
              onPressed: () => unawaited(_compose(context)),
            );
      return button;
    },
  );
}

class _MessageRecipientsDialog extends StatefulWidget {
  const _MessageRecipientsDialog();

  @override
  State<_MessageRecipientsDialog> createState() =>
      _MessageRecipientsDialogState();
}

class _MessageRecipientsDialogState extends State<_MessageRecipientsDialog> {
  final _form = GlobalKey<FormState>();
  final _recipients = TextEditingController();

  void _continue() {
    if (_form.currentState!.validate()) {
      Navigator.of(context).pop(_recipients.text.trim());
    }
  }

  @override
  void dispose() {
    _recipients.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New message'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _form,
        child: DInput(
          key: const ValueKey('new-message-recipients'),
          controller: _recipients,
          autofocus: true,
          autocorrect: false,
          labelText: 'To',
          helperText: 'Usernames or groups, separated by commas',
          validator: (value) =>
              (value ?? '')
                  .split(',')
                  .every((recipient) => recipient.trim().isEmpty)
              ? 'Choose at least one recipient.'
              : null,
          onSubmitted: (_) => _continue(),
        ),
      ),
    ),
    actions: [
      DButton(
        label: const Text('Cancel'),
        variant: DButtonVariant.ghost,
        onPressed: () => Navigator.of(context).pop(),
      ),
      DButton(
        label: const Text('Continue'),
        variant: DButtonVariant.primary,
        onPressed: _continue,
      ),
    ],
  );
}
