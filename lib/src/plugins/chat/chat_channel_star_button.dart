import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_services.dart';

class ChatChannelStarButton extends StatelessWidget {
  const ChatChannelStarButton({
    super.key,
    required this.siteUrl,
    required this.channelId,
    this.size = DButtonSize.regular,
  });

  final String siteUrl;
  final int channelId;
  final DButtonSize size;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
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
                  ? context.l10n.removeFromStarredChannels
                  : context.l10n.addToStarredChannels,
              onPressed: busy
                  ? null
                  : () => unawaited(_change(context, chat, !starred)),
              loading: busy,
              variant: DButtonVariant.ghost,
              size: size,
              icon: busy
                  ? const SizedBox.square(dimension: 18, child: DSpinner())
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
    DToast.show(context, error, type: DToastType.error);
  }
}
