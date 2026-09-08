import 'package:discourse_native/discourse_ui.dart' show DAvatar;
import 'package:flutter/material.dart';

import '../../models/user_flair.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/avatar_image.dart';
import '../../shell/group_flair.dart';
import '../../theme/app_theme.dart';
import 'chat_services.dart';

/// Insets the image within a fixed outer size so the upstream online ring does
/// not move message gutters.
/// Group flair sits outside the image clip, at core's 45% badge size and 10%
/// trailing/bottom overhang, without changing that layout footprint.
class ChatUserAvatar extends StatelessWidget {
  const ChatUserAvatar({
    super.key,
    required this.siteUrl,
    required this.userId,
    required this.url,
    required this.size,
    required this.fallback,
    this.flair,
  });

  final String siteUrl;
  final int userId;
  final String? url;
  final double size;
  final Widget fallback;
  final UserFlair? flair;

  static Key onlineRingKey(int userId) =>
      ValueKey<String>('chat-online-avatar-$userId');

  @override
  Widget build(BuildContext context) {
    final onlineUsers = PluginUiScope.require(
      context,
      chatControllerService,
    ).onlineUserIdsListenable(siteUrl);
    return ValueListenableBuilder<Set<int>>(
      valueListenable: onlineUsers,
      builder: (context, ids, _) {
        final avatar = ids.contains(userId)
            ? _OnlineAvatar(
                key: onlineRingKey(userId),
                url: url,
                size: size,
                fallback: fallback,
              )
            : _avatar(url: url, size: size, fallback: fallback);
        final badge = flair;
        if (badge == null) return avatar;
        final badgeSize = size * .45;
        return SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              PositionedDirectional(
                end: -size * .1,
                bottom: -size * .1,
                child: Tooltip(
                  message: badge.label,
                  child: GroupFlairBadge(
                    url: badge.url,
                    color: badge.color,
                    backgroundColor: badge.backgroundColor,
                    size: badgeSize,
                    iconSize: badgeSize,
                    borderRadius: badge.backgroundColor == null
                        ? 0
                        : badgeSize / 2,
                    defaultColor: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
}) => DAvatar.frame(
  child: SizedBox.square(
    dimension: size,
    child: AvatarImage(url: url, size: size, fallback: fallback),
  ),
);
