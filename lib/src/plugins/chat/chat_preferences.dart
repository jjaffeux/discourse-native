import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../models/user_preferences.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../theme/d_icons.dart';
import 'chat_plugin_data.dart';

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
    section: PreferenceSection.chat,
    title: 'Chat',
    icon: DIcons.comment,
    content: _ChatPreferenceForm(
      selectedMode: _effectiveMode(
        context.preferences.chatSeparateSidebarMode,
        settings.separateSidebarMode,
      ),
      enabled: context.editable,
      onChanged: (preference) => context.onEdit(
        (current) => current.copyWith(chatSeparateSidebarMode: preference),
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
        padding: const EdgeInsets.all(20),
        child: DSelect<ChatSeparateSidebarPreference>.controlled(
          isExpanded: true,
          key: ValueKey(('chat-separate-sidebar-mode', selectedMode)),
          value: selectedMode,
          label: const Text('Show separate sidebar modes for forum and chat'),
          entries: const [
            DSelectOption(
              value: ChatSeparateSidebarPreference.always,
              label: 'Always',
              child: Text('Always'),
            ),
            DSelectOption(
              value: ChatSeparateSidebarPreference.fullscreen,
              label: 'When chat is in fullscreen',
              child: Text('When chat is in fullscreen'),
            ),
            DSelectOption(
              value: ChatSeparateSidebarPreference.never,
              label: 'Never',
              child: Text('Never'),
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
