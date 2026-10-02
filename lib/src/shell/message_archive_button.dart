import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../models/post.dart';
import '../theme/d_icons.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

class MessageArchiveButton extends StatefulWidget {
  const MessageArchiveButton({
    super.key,
    required this.siteUrl,
    required this.topic,
    this.compact = false,
  });

  final String siteUrl;
  final TopicDetail topic;

  /// Draws an icon-only chip so it sits among the mobile topic header's
  /// compact actions instead of beside the reader's Reply button.
  final bool compact;

  @override
  State<MessageArchiveButton> createState() => _MessageArchiveButtonState();
}

class _MessageArchiveButtonState extends State<MessageArchiveButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TopicDetail?>(
    valueListenable: ShellScope.read(
      context,
    ).store.ref<TopicDetail>(widget.siteUrl, widget.topic.id),
    builder: (context, topic, _) =>
        _buildButton(context, topic ?? widget.topic),
  );

  Widget _buildButton(BuildContext context, TopicDetail topic) {
    final controller = ShellScope.read(context);
    final siteUrl = widget.siteUrl;
    final topicId = topic.id;
    final lease = controller.lifecycle.capture(siteUrl);
    final user = controller.instanceFor(siteUrl)?.user;
    final groups = topic.allowedMessageGroups
        .where((name) => user?.groups.contains(name) == true)
        .toList();
    final inboxes = [
      if (topic.allowedMessageUsers.contains(user?.username))
        context.l10n.yourInbox,
      for (final group in groups) context.l10n.theInbox((group).toString()),
    ];
    final scope = inboxes.isEmpty
        ? context.l10n.yourInboxes
        : inboxes.join(context.l10n.and);
    final archived = topic.messageArchived;
    final VoidCallback? onPressed = _busy
        ? null
        : () async {
            if (!mounted ||
                !context.mounted ||
                !lease.isCurrent ||
                widget.siteUrl != siteUrl ||
                widget.topic.id != topicId ||
                !identical(ShellScope.read(context), controller)) {
              return;
            }
            final toasts = DToast.of(context);
            setState(() => _busy = true);
            try {
              await _moveMessage(
                controller: controller,
                toasts: toasts,
                siteUrl: siteUrl,
                topicId: topicId,
                archived: !archived,
                scope: scope,
                offerUndo: true,
              );
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          };
    final icon = DIcon(archived ? DIcons.envelope : DIcons.folder);
    final tooltip = archived
        ? context.l10n.moveTo((scope).toString())
        : context.l10n.archiveFrom((scope).toString());
    if (widget.compact) {
      return DButton.iconOnly(
        key: const ValueKey('message-archive-button'),
        onPressed: onPressed,
        icon: icon,
        tooltip: tooltip,
        loading: _busy,
        variant: DButtonVariant.outline,
        size: DButtonSize.filter,
      );
    }
    return DButton(
      key: const ValueKey('message-archive-button'),
      onPressed: onPressed,
      icon: icon,
      label: Text(archived ? context.l10n.moveToInbox : context.l10n.archive),
      tooltip: tooltip,
      loading: _busy,
      variant: DButtonVariant.outline,
      size: DButtonSize.regular,
    );
  }
}

/// The disabled [MessageArchiveButton] shown while its message loads.
class MessageArchiveButtonPlaceholder extends StatelessWidget {
  const MessageArchiveButtonPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => DButton(
    onPressed: null,
    icon: const DIcon(DIcons.folder),
    label: Text(context.l10n.archive),
    variant: DButtonVariant.outline,
    size: DButtonSize.regular,
  );
}

Future<void> _moveMessage({
  required ShellController controller,
  required DToastController toasts,
  required String siteUrl,
  required int topicId,
  required bool archived,
  required String scope,
  required bool offerUndo,
}) async {
  final lease = controller.lifecycle.capture(siteUrl);
  final error = await controller.updateMessageArchived(
    siteUrl,
    topicId,
    archived,
  );
  if (!lease.isCurrent || controller.currentInstance?.url != siteUrl) {
    return;
  }
  toasts.add(
    DToastOptions(
      title:
          error ??
          (archived
              ? appL10n.archivedFrom((scope).toString())
              : appL10n.movedTo((scope).toString())),
      type: error == null ? DToastType.success : DToastType.error,
      action: error == null && offerUndo
          ? DToastAction(
              label: appL10n.undo,
              dismissOnPressed: true,
              onPressed: () {
                if (!lease.isCurrent) return;
                unawaited(
                  _moveMessage(
                    controller: controller,
                    toasts: toasts,
                    siteUrl: siteUrl,
                    topicId: topicId,
                    archived: !archived,
                    scope: scope,
                    offerUndo: false,
                  ),
                );
              },
            )
          : null,
    ),
    id: ('message-archive', siteUrl, topicId),
  );
}
