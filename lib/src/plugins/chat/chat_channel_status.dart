import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/d_button.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';

Future<void> showChatChannelStatusDialog({
  required BuildContext context,
  required ChatController chat,
  required String siteUrl,
  required ChatChannel channel,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      _ChannelStatusDialog(chat: chat, siteUrl: siteUrl, channel: channel),
);

class _ChannelStatusDialog extends StatefulWidget {
  const _ChannelStatusDialog({
    required this.chat,
    required this.siteUrl,
    required this.channel,
  });

  final ChatController chat;
  final String siteUrl;
  final ChatChannel channel;

  @override
  State<_ChannelStatusDialog> createState() => _ChannelStatusDialogState();
}

class _ChannelStatusDialogState extends State<_ChannelStatusDialog> {
  bool _saving = false;
  String? _error;

  bool get _closing => widget.channel.status == ChatChannelStatus.open;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.chat.setChannelClosed(
      widget.siteUrl,
      widget.channel.id,
      closed: _closing,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('chat-channel-status-dialog'),
    title: Text(_closing ? 'Close channel' : 'Open channel'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _closing
              ? 'Closing the channel prevents non-staff users from sending new messages or editing existing messages.'
              : 'Reopening the channel lets all members send messages and edit their existing messages.',
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Text(
            error,
            key: const ValueKey('chat-channel-status-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      DButton(
        label: const Text('Cancel'),
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
      ),
      DButton(
        key: const ValueKey('chat-channel-status-confirm'),
        label: Text(_closing ? 'Close channel' : 'Open channel'),
        onPressed: () => unawaited(_save()),
        variant: _closing ? DButtonVariant.danger : DButtonVariant.primary,
        loading: _saving,
      ),
    ],
  );
}
