import 'package:flutter/material.dart';

import '../../models/user_preferences.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/select.dart';
import '../../theme/app_theme.dart';
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
    final theme = Theme.of(context);
    return Material(
      color: theme.shell.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.shell.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: DSelectField<ChatSeparateSidebarPreference>(
          key: ValueKey(('chat-separate-sidebar-mode', selectedMode)),
          initialValue: selectedMode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Show separate sidebar modes for forum and chat',
          ),
          items: const [
            DropdownMenuItem(
              value: ChatSeparateSidebarPreference.always,
              child: Text('Always'),
            ),
            DropdownMenuItem(
              value: ChatSeparateSidebarPreference.fullscreen,
              child: Text('When chat is in fullscreen'),
            ),
            DropdownMenuItem(
              value: ChatSeparateSidebarPreference.never,
              child: Text('Never'),
            ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onChanged(value);
                }
              : null,
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
