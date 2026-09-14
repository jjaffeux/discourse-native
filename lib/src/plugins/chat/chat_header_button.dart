import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../plugin_api/plugin_scope.dart';
import '../../shell/adaptive_shell.dart';
import '../../shell/header_notification_button.dart';
import '../../theme/app_theme.dart';
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

        final exitsChat =
            shell.fullPageChatActive &&
            shell.separateSidebarMode != ChatSeparateSidebarMode.never;
        if (exitsChat) {
          return DButton.iconOnly(
            key: buttonKey,
            tooltip: 'Exit chat',
            onPressed: shell.closeSidebarPanel,
            variant: DButtonVariant.ghost,
            icon: const DIcon(DIcons.shuffle),
          );
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

        void openChat() => unawaited(
          shell.openShortcut(
            drawerAvailable:
                ShellLayout.forWidth(MediaQuery.sizeOf(context).width) !=
                ShellLayout.compact,
          ),
        );
        final theme = Theme.of(context);
        if (urgentCount != null) {
          return headerNotificationButton(
            context,
            key: buttonKey,
            countKey: urgentBadgeKey,
            icon: const DIcon(DIcons.comment, size: 20),
            count: urgentCount,
            color: theme.discourse.success,
            surface: ringColor ?? theme.shell.content,
            tooltip: tooltip,
            semanticLabel: tooltip,
            onPressed: openChat,
          );
        }
        return DButton.iconOnly(
          key: buttonKey,
          tooltip: tooltip,
          onPressed: openChat,
          variant: DButtonVariant.ghost,
          icon: ExcludeSemantics(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const DIcon(DIcons.comment, size: 22),
                if (indicator.unread)
                  PositionedDirectional(
                    top: -2,
                    end: -3,
                    child: DNotificationDot.overlay(
                      key: unreadDotKey,
                      color: theme.discourse.notificationIndicator,
                      ringColor: ringColor,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
