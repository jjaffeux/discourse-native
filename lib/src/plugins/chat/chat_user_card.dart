import 'package:flutter/material.dart';

import '../../data/discourse_api_contracts.dart';
import '../../models/user_card.dart';
import '../../plugin_api/plugin_data.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_services.dart';
import 'chat_shell_extension.dart';

const chatUserCardKey = PluginDataKey<ChatUserCardData>(
  owner: 'chat',
  name: 'user-card',
);

/// Chat's personalized contribution to a user-card serializer.
@immutable
final class ChatUserCardData {
  const ChatUserCardData({required this.canChat});

  final bool canChat;

  @override
  bool operator ==(Object other) =>
      other is ChatUserCardData && other.canChat == canChat;

  @override
  int get hashCode => canChat.hashCode;
}

/// The Chat-owned control rendered in core's user-card action region.
class ChatUserCardButton extends StatefulWidget {
  const ChatUserCardButton({
    super.key,
    required this.siteUrl,
    required this.user,
    required this.close,
  });

  final String siteUrl;
  final UserCard user;
  final VoidCallback close;

  @override
  State<ChatUserCardButton> createState() => _ChatUserCardButtonState();
}

class _ChatUserCardButtonState extends State<ChatUserCardButton> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final chat = PluginUiScope.require(context, chatControllerService);
      final channel = await chat.upsertDirectMessageChannel(
        widget.siteUrl,
        widget.user.username,
      );
      if (!mounted || channel == null) return;

      final shell = PluginUiScope.require(context, chatShellService);
      if (shell.openChannel(channel.id)) widget.close();
    } catch (error) {
      if (!mounted) return;
      final message = switch (error) {
        WriteException(errors: final errors) when errors.isNotEmpty =>
          errors.join('\n'),
        final WriteException error => error.message,
        _ => 'Could not start this chat.',
      };
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: ValueKey<String>('user-card-chat-${widget.user.username}'),
        onPressed: _opening ? null : _open,
        icon: _opening
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const DIcon(DIcons.comment, size: 16),
        label: const Text('Chat'),
      ),
    );
  }
}
