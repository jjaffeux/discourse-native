import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_plugin_data.dart';
import 'chat_user_preferences.dart';

PluginUserPreferenceSection? chatUserPreferenceSection(
  PluginUserPreferenceContext context,
) {
  final settings = context.siteSettings.chatSettings;
  final currentUser = context.currentUserData.chatCurrentUser;
  if (!settings.chatEnabled ||
      (currentUser?.canChat != true && !context.currentUserIsAdmin)) {
    return null;
  }

  return PluginUserPreferenceSection(
    section: chatPreferenceSection,
    title: appL10n.chat,
    icon: DIcons.comment,
    content: _ChatPreferenceForm(
      selectedMode: _effectiveMode(
        context.preferences.chatPreferences.separateSidebarMode,
        settings.separateSidebarMode,
      ),
      enabled: context.editable,
      onChanged: (preference) => context.onEdit(
        chatPreferenceSection,
        (current) =>
            current.withChatPreferences(separateSidebarMode: preference),
      ),
    ),
  );
}

class _ChatPreferenceForm extends StatelessWidget {
  const _ChatPreferenceForm({
    required this.selectedMode,
    required this.enabled,
    required this.onChanged,
  });

  final ChatSeparateSidebarPreference selectedMode;
  final bool enabled;
  final ValueChanged<ChatSeparateSidebarPreference> onChanged;

  @override
  Widget build(BuildContext context) {
    return DCard(
      spacing: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DSelect<ChatSeparateSidebarPreference>.controlled(
          size: DControlSize.preference,
          isExpanded: true,
          key: ValueKey(('chat-separate-sidebar-mode', selectedMode)),
          value: selectedMode,
          label: Text(context.l10n.showSeparateSidebarModesForForumAndChat),
          entries: [
            DSelectOption(
              value: ChatSeparateSidebarPreference.always,
              label: context.l10n.always,
              child: Text(context.l10n.always),
            ),
            DSelectOption(
              value: ChatSeparateSidebarPreference.fullscreen,
              label: context.l10n.whenChatIsInFullscreen,
              child: Text(context.l10n.whenChatIsInFullscreen),
            ),
            DSelectOption(
              value: ChatSeparateSidebarPreference.never,
              label: context.l10n.never,
              child: Text(context.l10n.never),
            ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onChanged(value);
                }
              : null,
          initialValue: selectedMode,
          enabled: enabled,
        ),
      ),
    );
  }
}

ChatSeparateSidebarPreference _effectiveMode(
  ChatSeparateSidebarPreference preference,
  ChatSeparateSidebarMode siteMode,
) => switch (preference) {
  ChatSeparateSidebarPreference.siteDefault => switch (siteMode) {
    ChatSeparateSidebarMode.always => ChatSeparateSidebarPreference.always,
    ChatSeparateSidebarMode.fullscreen =>
      ChatSeparateSidebarPreference.fullscreen,
    _ => ChatSeparateSidebarPreference.never,
  },
  _ => preference,
};
