import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_services.dart';
import 'chat_user_avatar.dart';

/// What a chat is of, as its mark: a person's face, a group's, or a channel's
/// tile in its category's colour.
class ChatConversationAvatar extends StatelessWidget {
  const ChatConversationAvatar({
    super.key,
    required this.siteUrl,
    required this.channel,
    required this.size,
  }) : _inbox = false;

  const ChatConversationAvatar.inbox({
    super.key,
    required this.siteUrl,
    required this.channel,
    required this.size,
  }) : _inbox = true;

  final String siteUrl;
  final ChatChannel channel;
  final double size;
  final bool _inbox;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final color = channel.categoryColor ?? tokens.mutedForeground;
    final desktopChannel =
        _inbox && !context.isTouch && !channel.isDirectMessage;
    final surface = desktopChannel
        ? tokens.categoryControlSurface(color)
        : null;
    final background = surface?.background ?? color.withValues(alpha: .22);
    final fallback = DAvatarFallback(
      backgroundColor: background,
      foregroundColor: surface?.foreground ?? color,
      child: channel.isDirectMessage
          ? channel.isGroup || channel.users.length > 1
                ? DIcon(DIcons.users, size: size / 2)
                : Text(
                    channel.title.characters.take(1).toString().toUpperCase(),
                  )
          : desktopChannel
          ? const DIconGlyphTheme(
              scale: 1,
              child: DIcon(DIcons.hashtag, size: 15),
            )
          : Text(
              '#',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontSize: size * .6,
                fontWeight: FontWeight.w400,
              ),
            ),
    );
    if (!channel.isDirectMessage && channel.emoji != null) {
      final emojiHost = PluginUiScope.require(context, chatEmojiHostService);
      return DAvatar(
        dimension: size,
        border: false,
        borderRadius: BorderRadius.circular(DRadius.bubble),
        decorative: true,
        fallback: DAvatarFallback(
          backgroundColor: background,
          child: EmojiImage(
            url: emojiHost.resolveUrl(siteUrl, channel.emoji!),
            size: size / 2,
            alt: ':${channel.emoji}:',
          ),
        ),
      );
    }
    if (channel.isDirectMessage &&
        channel.users.length == 1 &&
        !channel.isGroup) {
      return ChatUserAvatar(
        siteUrl: siteUrl,
        userId: channel.users.first.id,
        url: channel.avatarUrl,
        size: size,
        fallback: fallback,
      );
    }
    return DAvatar(
      dimension: size,
      border: false,
      borderRadius: channel.isDirectMessage
          ? null
          : BorderRadius.circular(DRadius.bubble),
      decorative: true,
      fallback: fallback,
    );
  }
}
