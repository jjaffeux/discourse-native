import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/discourse_typography.dart';
import 'shell_scope.dart';
import 'title_bar.dart';

class MessageCreateButton extends StatelessWidget {
  const MessageCreateButton({super.key, required this.showLabel});

  final bool showLabel;

  Future<void> _compose(BuildContext context) async {
    final controller = ShellScope.read(context);
    final instance = controller.currentInstance;
    final user = instance?.user;
    final tabId = controller.activeTabId;
    final route = controller.currentContent;
    if (instance == null || user == null || route?.isMessages != true) return;
    final recipients =
        route!.messageGroupName ??
        await showDialog<String>(
          context: context,
          builder: (_) => const _MessageRecipientsDialog(),
        );
    if (!context.mounted ||
        recipients == null ||
        controller.activeTabId != tabId ||
        controller.currentInstance?.user?.id != user.id ||
        controller.currentContent != route) {
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
              label: const Text('New message'),
              icon: const DIcon(DIcons.farPenToSquare, size: 16),
              tooltip: 'New message',
              variant: DButtonVariant.primary,
              size: DButtonSize.small,
              onPressed: () => unawaited(_compose(context)),
            )
          : DButton.iconOnly(
              key: const ValueKey('new-message-button'),
              icon: const DIcon(DIcons.farPenToSquare, size: 18),
              tooltip: 'New message',
              variant: DButtonVariant.primary,
              size: DButtonSize.small,
              insetSurface: ShellTitleBar.isSupported,
              onPressed: () => unawaited(_compose(context)),
            );
      if (!showLabel || !ShellTitleBar.isSupported) return button;
      return SizedBox(
        height: math.max(
          36,
          MediaQuery.textScalerOf(
                    context,
                  ).scale(DiscourseTypography.fontDown1) *
                  1.2 +
              18,
        ),
        child: button,
      );
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
        child: TextFormField(
          key: const ValueKey('new-message-recipients'),
          controller: _recipients,
          autofocus: true,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'To',
            helperText: 'Usernames or groups, separated by commas',
            helperMaxLines: 2,
          ),
          validator: (value) =>
              (value ?? '')
                  .split(',')
                  .every((recipient) => recipient.trim().isEmpty)
              ? 'Choose at least one recipient.'
              : null,
          onFieldSubmitted: (_) => _continue(),
        ),
      ),
    ),
    actions: [
      DButton(
        label: const Text('Cancel'),
        variant: DButtonVariant.flat,
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
