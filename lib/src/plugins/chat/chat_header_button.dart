import 'dart:async';

import 'package:flutter/material.dart';

import '../../plugin_api/plugin_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_controller.dart';
import 'chat_notification_counter.dart';
import 'chat_plugin_data.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

class ChatHeaderButton extends StatelessWidget {
  const ChatHeaderButton({
    super.key,
    this.hideWhenChatActive = false,
    this.ringColor,
  });

  final bool hideWhenChatActive;

  final Color? ringColor;

  static const Key buttonKey = ValueKey('chat-header-button');
  static const Key unreadDotKey = ValueKey('chat-header-unread-dot');
  static const Key urgentBadgeKey = ValueKey('chat-header-urgent-badge');

  @override
  Widget build(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    final chat = PluginUiScope.require(context, chatControllerService);
    return ListenableBuilder(
      listenable: Listenable.merge([shell, chat]),
      builder: (context, _) {
        final siteUrl = shell.currentSiteUrl;
        final user = shell.currentUser;
        if (!shell.showHeaderShortcut || siteUrl == null || user == null) {
          return const SizedBox.shrink();
        }
        if (hideWhenChatActive && shell.chatActive) {
          return const SizedBox.shrink();
        }
        final totals = shell.currentTotals;
        // Null preserves legacy cached accounts until their session refresh.
        if (totals?.hasChatEnabled != true ||
            user.chatCurrentUser?.hasChatEnabled == false) {
          return const SizedBox.shrink();
        }

        final preference =
            user.chatCurrentUser?.headerIndicatorPreference ??
            ChatHeaderIndicatorPreference.allNew;
        final indicator = shell.doNotDisturbActive(siteUrl)
            ? ChatHeaderIndicator.none
            : chat.headerIndicator(siteUrl, preference);
        final urgentCount = indicator.urgentCount;
        final tooltip = urgentCount != null
            ? 'Chat, $urgentCount urgent ${urgentCount == 1 ? 'message' : 'messages'}'
            : indicator.unread
            ? 'Chat, unread messages'
            : 'Chat';

        return DButton.iconOnly(
          key: buttonKey,
          tooltip: tooltip,
          onPressed: () => unawaited(shell.openShortcut()),
          variant: DButtonVariant.flat,
          icon: ExcludeSemantics(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const DIcon(DIcons.comment, size: 22),
                if (urgentCount != null)
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
          ),
        );
      },
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({this.ringColor});

  final Color? ringColor;

  @override
  Widget build(BuildContext context) => Container(
    key: ChatHeaderButton.unreadDotKey,
    // Core uses a 14px box with a 2px header-coloured border.
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
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
        border: ringColor == null
            ? null
            : Border.all(color: ringColor!, width: 2),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontSize: DiscourseTypography.fontDown3,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
