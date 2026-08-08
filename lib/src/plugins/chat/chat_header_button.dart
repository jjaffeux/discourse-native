import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/discourse_user.dart';
import '../../shell/shell_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';

typedef _ChatHeaderSnapshot = ({
  String? siteUrl,
  DiscourseUser? user,
  bool chatActive,
});

/// The Chat plugin's shortcut beside the account avatar.
///
/// Core mounts this only for an account allowed to chat, hides it while mobile
/// chat is active, and gives urgent activity a count while ordinary channel
/// activity gets a dot. This widget intentionally reads the same channel
/// tracking records as the sidebar rows; two independently maintained totals
/// would drift as soon as a channel is read here.
class ChatHeaderButton extends StatelessWidget {
  const ChatHeaderButton({
    super.key,
    this.hideWhenChatActive = false,
    this.ringColor,
  });

  /// True in the compact shell, matching core's mobile active-state rule.
  final bool hideWhenChatActive;

  /// The painted surface behind the badge's separating ring.
  final Color? ringColor;

  static const Key buttonKey = ValueKey('chat-header-button');
  static const Key unreadDotKey = ValueKey('chat-header-unread-dot');
  static const Key urgentBadgeKey = ValueKey('chat-header-urgent-badge');

  @override
  Widget build(BuildContext context) => ShellSelector<_ChatHeaderSnapshot>(
    select: (controller) {
      final instance = controller.currentInstance;
      return (
        siteUrl: instance?.url,
        user: instance?.user,
        chatActive:
            ChatChannel.channelIdIn(controller.currentContent?.id ?? '') !=
            null,
      );
    },
    builder: (context, account, _) {
      final siteUrl = account.siteUrl;
      final user = account.user;
      if (siteUrl == null || user == null) return const SizedBox.shrink();
      if (hideWhenChatActive && account.chatActive) {
        return const SizedBox.shrink();
      }

      final controller = ShellScope.read(context);
      return ListenableBuilder(
        listenable: Listenable.merge([
          controller.accountActivity.totalsListenable,
          controller.chat,
        ]),
        builder: (context, _) {
          final totals = controller.accountActivity.totalsFor(siteUrl);
          // The totals key and CurrentUser#has_chat_enabled are guarded by the
          // same three conditions in core. The nullable user value keeps an
          // account stored by an older app usable until its session refresh.
          if (totals?.hasChatEnabled != true || user.hasChatEnabled == false) {
            return const SizedBox.shrink();
          }

          final indicator = user.isInDoNotDisturb
              ? ChatHeaderIndicator.none
              : controller.chat.headerIndicator(
                  siteUrl,
                  user.chatHeaderIndicatorPreference,
                );

          return IconButton(
            key: buttonKey,
            tooltip: 'Chat',
            onPressed: () => unawaited(controller.openChat()),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const DIcon(DIcons.comment, size: 22),
                if (indicator.urgentCount != null)
                  Positioned(
                    top: -8,
                    right: -12,
                    child: _UrgentBadge(
                      label: indicator.label!,
                      ringColor: ringColor,
                    ),
                  )
                else if (indicator.unread)
                  Positioned(
                    top: -5,
                    right: -6,
                    child: _UnreadDot(ringColor: ringColor),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({this.ringColor});

  final Color? ringColor;

  @override
  Widget build(BuildContext context) => Container(
    key: ChatHeaderButton.unreadDotKey,
    // Core uses a 14px content box and a 2px header-coloured border.
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      shape: BoxShape.circle,
      border: ringColor == null
          ? null
          : Border.all(color: ringColor!, width: 2),
    ),
  );
}

class _UrgentBadge extends StatelessWidget {
  const _UrgentBadge({required this.label, this.ringColor});

  final String label;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: ChatHeaderButton.urgentBadgeKey,
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.discourse.success,
        borderRadius: BorderRadius.circular(10),
        border: ringColor == null
            ? null
            : Border.all(color: ringColor!, width: 2),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.surface,
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
