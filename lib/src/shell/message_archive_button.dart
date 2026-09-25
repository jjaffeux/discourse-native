import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
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
    final user = controller.instanceFor(widget.siteUrl)?.user;
    final groups = topic.allowedMessageGroups
        .where((name) => user?.groups.contains(name) == true)
        .toList();
    final inboxes = [
      if (topic.allowedMessageUsers.contains(user?.username)) 'your inbox',
      for (final group in groups) 'the $group inbox',
    ];
    final scope = inboxes.isEmpty ? 'your inboxes' : inboxes.join(' and ');
    final archived = topic.messageArchived;
    final VoidCallback? onPressed = _busy
        ? null
        : () async {
            final toasts = DToast.of(context);
            final siteUrl = widget.siteUrl;
            final topicId = widget.topic.id;
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
    final tooltip = archived ? 'Move to $scope' : 'Archive from $scope';
    if (widget.compact) {
      return DButton.iconOnly(
        key: const ValueKey('message-archive-button'),
        onPressed: onPressed,
        icon: icon,
        tooltip: tooltip,
        loading: _busy,
        variant: DButtonVariant.outline,
        size: DButtonSize.chip,
      );
    }
    return DButton(
      key: const ValueKey('message-archive-button'),
      onPressed: onPressed,
      icon: icon,
      label: Text(archived ? 'Move to inbox' : 'Archive'),
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
  Widget build(BuildContext context) => const DButton(
    onPressed: null,
    icon: DIcon(DIcons.folder),
    label: Text('Archive'),
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
      title: error ?? (archived ? 'Archived from $scope' : 'Moved to $scope'),
      type: error == null ? DToastType.success : DToastType.error,
      action: error == null && offerUndo
          ? DToastAction(
              label: 'Undo',
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
