import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

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
    this.isBot = false,
  });

  final String siteUrl;
  final int userId;
  final String? url;
  final double size;
  final Widget fallback;
  final UserFlair? flair;
  final bool isBot;

  static Key onlineRingKey(int userId) =>
      ValueKey<String>('chat-online-avatar-$userId');

  @override
  Widget build(BuildContext context) {
    final onlineUsers = PluginUiScope.require(
      context,
      chatControllerService,
    ).onlineUserIdsListenable(siteUrl);
    return _UserOnlineBuilder(
      onlineUsers: onlineUsers,
      userId: userId,
      builder: (context, online) {
        final avatar = _avatar(
          key: online ? onlineRingKey(userId) : null,
          url: url,
          size: size,
          fallback: fallback,
          ring: online,
        );
        final badge = flair;
        final bot = badge == null && (isBot || userId < 0);
        if (badge == null && !bot) return avatar;
        final colors = Theme.of(context).colorScheme;
        String hex(Color color) =>
            (color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0');
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
                  message: bot ? context.l10n.chatBotAccount : badge!.label,
                  child: GroupFlairBadge(
                    url: bot ? 'robot' : badge!.url,
                    color: bot ? hex(colors.surface) : badge?.color,
                    backgroundColor: bot
                        ? hex(colors.onSurface)
                        : badge?.backgroundColor,
                    size: badgeSize,
                    iconSize: badgeSize,
                    borderRadius: !bot && badge?.backgroundColor == null
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

/// The online set is replaced for every presence delivery about anyone on the
/// site, so only a change in this user's own membership may schedule a frame.
class _UserOnlineBuilder extends StatefulWidget {
  const _UserOnlineBuilder({
    required this.onlineUsers,
    required this.userId,
    required this.builder,
  });

  final ValueListenable<Set<int>> onlineUsers;
  final int userId;
  final Widget Function(BuildContext context, bool online) builder;

  @override
  State<_UserOnlineBuilder> createState() => _UserOnlineBuilderState();
}

class _UserOnlineBuilderState extends State<_UserOnlineBuilder> {
  late bool _online;

  bool get _isOnline => widget.onlineUsers.value.contains(widget.userId);

  @override
  void initState() {
    super.initState();
    _online = _isOnline;
    widget.onlineUsers.addListener(_syncOnline);
  }

  @override
  void didUpdateWidget(_UserOnlineBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.onlineUsers, widget.onlineUsers)) {
      oldWidget.onlineUsers.removeListener(_syncOnline);
      widget.onlineUsers.addListener(_syncOnline);
    }
    _online = _isOnline;
  }

  void _syncOnline() {
    final online = _isOnline;
    if (online != _online) setState(() => _online = online);
  }

  @override
  void dispose() {
    widget.onlineUsers.removeListener(_syncOnline);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _online);
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
  ringSemanticLabel: ring ? appL10n.online : null,
  child: AvatarImage(
    url: url,
    size: ring ? size - 4 : size,
    fallback: fallback,
  ),
);
