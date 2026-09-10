import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../models/user_flair.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/avatar_image.dart';
import '../../shell/group_flair.dart';
import 'chat_services.dart';

/// Uses DAvatar's core-compatible ring without moving message gutters.
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
        final online = ids.contains(userId);
        final avatar = _avatar(
          key: online ? onlineRingKey(userId) : null,
          url: url,
          size: size,
          fallback: fallback,
          ring: online,
        );
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
                child: DTooltip(
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

Widget _avatar({
  Key? key,
  required String? url,
  required double size,
  required Widget fallback,
  bool ring = false,
}) => DAvatar(
  key: key,
  dimension: size,
  ring: ring,
  ringSemanticLabel: ring ? 'Online' : null,
  child: AvatarImage(
    url: url,
    size: ring ? size - 4 : size,
    fallback: fallback,
  ),
);
