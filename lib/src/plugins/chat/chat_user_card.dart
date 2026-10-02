import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_services.dart';
import 'chat_shell_service.dart';

const chatUserCardKey = PluginDataKey<ChatUserCardData>(
  owner: 'chat',
  name: 'user-card',
);

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
      final siteUrl = widget.siteUrl;
      final username = widget.user.username;
      final chat = PluginUiScope.require(context, chatControllerService);
      final shell = PluginUiScope.require(context, chatShellService);
      final channel = await chat.upsertDirectMessageChannel(siteUrl, username);
      if (!mounted || channel == null) return;
      if (widget.siteUrl != siteUrl ||
          widget.user.username != username ||
          shell.currentSiteUrl != siteUrl ||
          !identical(
            PluginUiScope.optional(context, chatControllerService),
            chat,
          ) ||
          !identical(
            PluginUiScope.optional(context, chatShellService),
            shell,
          )) {
        return;
      }

      if (shell.openChannel(channel.id)) widget.close();
    } catch (error) {
      if (!mounted) return;
      final message = switch (error) {
        WriteException(errors: final errors) when errors.isNotEmpty =>
          errors.join('\n'),
        final WriteException error => error.message,
        _ => appL10n.couldNotStartThisChat,
      };
      DToast.show(context, message, type: DToastType.error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DButton(
        key: ValueKey<String>('user-card-chat-${widget.user.username}'),
        label: Text(context.l10n.chat),
        onPressed: _open,
        icon: const DIcon(DIcons.comment),
        variant: DButtonVariant.primary,
        loading: _opening,
      ),
    );
  }
}
