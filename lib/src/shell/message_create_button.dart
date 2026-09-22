import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'shell_scope.dart';

class MessageCreateButton extends StatelessWidget {
  const MessageCreateButton({
    super.key,
    required this.showLabel,
    this.pill = false,
  });

  final bool showLabel;
  final bool pill;

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
        await showDDialog<String>(
          context: context,
          builder: (_, controller) =>
              _MessageRecipientsDialog(controller: controller),
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
              shape: pill ? DButtonShape.pill : DButtonShape.rounded,
              icon: DIcon(pill ? DIcons.plus : DIcons.farPenToSquare),
              tooltip: 'New message',
              variant: DButtonVariant.primary,
              size: DButtonSize.regular,
              onPressed: () => unawaited(_compose(context)),
            )
          : DButton.iconOnly(
              shape: pill ? DButtonShape.pill : DButtonShape.rounded,
              key: const ValueKey('new-message-button'),
              icon: DIcon(pill ? DIcons.plus : DIcons.farPenToSquare),
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
  const _MessageRecipientsDialog({required this.controller});
  final DDialogController<String> controller;

  @override
  State<_MessageRecipientsDialog> createState() =>
      _MessageRecipientsDialogState();
}

class _MessageRecipientsDialogState extends State<_MessageRecipientsDialog> {
  final _form = GlobalKey<FormState>();
  final _recipients = TextEditingController();

  void _continue() {
    if (_form.currentState!.validate()) {
      widget.controller.close(_recipients.text.trim());
    }
  }

  @override
  void dispose() {
    _recipients.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DDialogContent(
    children: [
      const DDialogHeader(children: [DDialogTitle(child: Text('New message'))]),
      SizedBox(
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
      DDialogFooter(
        children: [
          DButton(
            label: const Text('Cancel'),
            variant: DButtonVariant.ghost,
            onPressed: () => widget.controller.close(),
          ),
          DButton(
            label: const Text('Continue'),
            variant: DButtonVariant.primary,
            onPressed: _continue,
          ),
        ],
      ),
    ],
  );
}
