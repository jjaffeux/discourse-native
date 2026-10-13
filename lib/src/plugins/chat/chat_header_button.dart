import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_controller.dart';
import 'chat_header_menu.dart';
import 'chat_notification_counter.dart';
import 'chat_plugin_data.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

class ChatHeaderButton extends StatefulWidget {
  const ChatHeaderButton({super.key, this.ringColor, this.trailingSpacing = 0});

  final Color? ringColor;

  /// Space after the visible shortcut, removed together with a hidden shortcut.
  final double trailingSpacing;

  static const Key buttonKey = ValueKey('chat-header-button');
  static const Key unreadDotKey = ValueKey('chat-header-unread-dot');
  static const Key urgentBadgeKey = ValueKey('chat-header-urgent-badge');

  @override
  State<ChatHeaderButton> createState() => _ChatHeaderButtonState();
}

class _ChatHeaderButtonState extends State<ChatHeaderButton> {
  final _menu = DDropdownMenuController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  Widget _withSpacing(Widget button) => widget.trailingSpacing == 0
      ? button
      : Padding(
          padding: EdgeInsetsDirectional.only(end: widget.trailingSpacing),
          child: button,
        );

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
        final mobile = context.isTouch;
        if (mobile && shell.chatActive) {
          return const SizedBox.shrink();
        }
        final totals = shell.currentTotals;
        // Null preserves legacy cached accounts until their session refresh.
        if (!shell.chatAvailable(siteUrl) ||
            totals?.hasChatEnabled != true ||
            user.chatCurrentUser?.hasChatEnabled == false) {
          return const SizedBox.shrink();
        }

        void openChat() => unawaited(shell.openHeaderShortcut(mobile: mobile));
        final preference =
            user.chatCurrentUser?.headerIndicatorPreference ??
            ChatHeaderIndicatorPreference.allNew;
        final indicator =
            (!mobile && shell.fullPageChatActive) ||
                shell.doNotDisturbActive(siteUrl)
            ? ChatHeaderIndicator.none
            : chat.headerIndicator(siteUrl, preference);
        final urgentCount = indicator.urgentCount;
        final unreadCount = indicator.unread
            ? [
                ...chat.publicChannels(siteUrl),
                ...chat.directChannels(siteUrl),
              ].fold(
                0,
                (count, channel) =>
                    count +
                    channel.tracking.unreadCount +
                    channel.unreadThreadCount,
              )
            : 0;
        final count = urgentCount ?? unreadCount;
        final tooltip = urgentCount != null
            ? context.l10n.chatUrgent(urgentCount)
            : indicator.unread
            ? '${context.l10n.chat}, ${context.l10n.unreadChatplugin(count)}'
            : context.l10n.chat;

        final theme = Theme.of(context);
        Widget button({
          required VoidCallback onPressed,
          FocusNode? focusNode,
          bool expanded = false,
        }) {
          if (count > 0) {
            return headerNotificationButton(
              context,
              key: ChatHeaderButton.buttonKey,
              countKey: urgentCount != null
                  ? ChatHeaderButton.urgentBadgeKey
                  : ChatHeaderButton.unreadDotKey,
              icon: const DIcon(DIcons.comment, size: 20),
              count: count,
              color: theme.discourse.success,
              surface: widget.ringColor ?? theme.shell.content,
              tooltip: tooltip,
              semanticLabel: tooltip,
              onPressed: onPressed,
              focusNode: focusNode,
              hasPopup: !mobile,
              expanded: expanded,
            );
          }
          return DButton.iconOnly(
            key: ChatHeaderButton.buttonKey,
            tooltip: tooltip,
            onPressed: onPressed,
            focusNode: focusNode,
            hasPopup: !mobile,
            expanded: expanded,
            variant: expanded ? DButtonVariant.primary : DButtonVariant.ghost,
            shape: DButtonShape.pill,
            icon: const DIcon(DIcons.comment, size: 20),
          );
        }

        if (mobile) return _withSpacing(button(onPressed: openChat));
        return _withSpacing(
          DDropdownMenu(
            key: ValueKey((siteUrl, user.id)),
            controller: _menu,
            content: DDropdownMenuContent(
              semanticLabel: context.l10n.chat,
              align: DPopoverAlign.end,
              width: DesktopHeaderMenu.width,
              autofocus: false,
              children: [
                ChatHeaderMenu(siteUrl: siteUrl, onDismiss: _menu.close),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (context, trigger) => button(
                focusNode: trigger.focusNode,
                expanded: trigger.open,
                onPressed: trigger.toggle,
              ),
            ),
          ),
        );
      },
    );
  }
}
