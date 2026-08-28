import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../plugin_scope.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_services.dart';

/// Stars the current account's membership in one followed channel.
class ChatChannelStarButton extends StatelessWidget {
  const ChatChannelStarButton({
    super.key,
    required this.siteUrl,
    required this.channelId,
  });

  final String siteUrl;
  final int channelId;

  @override
  Widget build(BuildContext context) {
    final chat = PluginScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) {
        if (channel == null || !channel.membership.following) {
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: chat,
          builder: (context, _) {
            final starred = channel.membership.starred;
            final busy = chat.channelStarWriteInFlight(siteUrl, channel.id);
            return DButton.iconOnly(
              key: const ValueKey('chat-channel-star-button'),
              tooltip: starred
                  ? 'Remove from starred channels'
                  : 'Add to starred channels',
              onPressed: busy
                  ? null
                  : () => unawaited(_change(context, chat, !starred)),
              loading: busy,
              variant: DButtonVariant.flat,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : DIcon(starred ? DIcons.star : DIcons.farStar, size: 18),
            );
          },
        );
      },
    );
  }

  Future<void> _change(
    BuildContext context,
    ChatController chat,
    bool starred,
  ) async {
    final error = await chat.updateChannelStarred(siteUrl, channelId, starred);
    if (error == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
  }
}
