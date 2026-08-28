import 'package:flutter/material.dart';

import '../../shell/avatar_image.dart';
import '../../theme/app_theme.dart';
import '../plugin_scope.dart';
import 'chat_services.dart';

/// A chat avatar with Discourse's live online treatment.
///
/// Core keeps the outer size unchanged, insets the image by two pixels and
/// paints a one-pixel `success` ring with the page (`secondary`) showing
/// between them. Matching that geometry matters in message gutters: growing
/// the avatar to add an outside border would move every message body.
class ChatUserAvatar extends StatelessWidget {
  const ChatUserAvatar({
    super.key,
    required this.siteUrl,
    required this.userId,
    required this.url,
    required this.size,
    required this.fallback,
  });

  final String siteUrl;
  final int userId;
  final String? url;
  final double size;
  final Widget fallback;

  static Key onlineRingKey(int userId) =>
      ValueKey<String>('chat-online-avatar-$userId');

  @override
  Widget build(BuildContext context) {
    final onlineUsers = PluginScope.require(
      context,
      chatControllerService,
    ).onlineUserIdsListenable(siteUrl);
    return ValueListenableBuilder<Set<int>>(
      valueListenable: onlineUsers,
      builder: (context, ids, _) => ids.contains(userId)
          ? _OnlineAvatar(
              key: onlineRingKey(userId),
              url: url,
              size: size,
              fallback: fallback,
            )
          : _avatar(url: url, size: size, fallback: fallback),
    );
  }
}

class _OnlineAvatar extends StatelessWidget {
  const _OnlineAvatar({
    super.key,
    required this.url,
    required this.size,
    required this.fallback,
  });

  final String? url;
  final double size;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.shell.content,
          shape: BoxShape.circle,
          border: Border.all(color: theme.discourse.success),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: _avatar(url: url, size: size - 4, fallback: fallback),
        ),
      ),
    );
  }
}

Widget _avatar({
  required String? url,
  required double size,
  required Widget fallback,
}) => ClipOval(
  child: SizedBox.square(
    dimension: size,
    child: AvatarImage(url: url, size: size, fallback: fallback),
  ),
);
