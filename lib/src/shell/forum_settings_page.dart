import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'forum_appearance_settings.dart';
import 'forum_display_settings.dart';
import 'settings_section_tabs.dart';
import 'shell_scope.dart';

/// Forum settings occupy the normal content panel so the surrounding workspace
/// is the live result of every appearance edit.
class ForumSettingsPage extends StatefulWidget {
  const ForumSettingsPage({super.key, required this.siteUrl});
  final String siteUrl;

  @override
  State<ForumSettingsPage> createState() => _ForumSettingsPageState();
}

class _ForumSettingsPageState extends State<ForumSettingsPage> {
  String _section = 'display';

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.identityOf(context);
    final appSettings = shell.appSettings;
    final forumSettings = shell.forumSettings;
    return DPageSurface.headed(
      identity: widget.siteUrl,
      icon: DIcons.gear,
      title: Text(context.l10n.interface),
      controls: SettingsSectionTabs<String>(
        value: _section,
        onChanged: (value) => setState(() => _section = value),
        sections: [
          (value: 'display', label: context.l10n.display, key: null),
          (value: 'themes', label: context.l10n.themes, key: null),
          (
            value: 'accessibility',
            label: context.l10n.accessibility,
            key: null,
          ),
        ],
      ),
      child: switch (_section) {
        'display' => ForumDisplaySettings(
          appSettings: appSettings,
          forumSettings: forumSettings,
        ),
        'accessibility' => DScrollArea(
          padding: EdgeInsets.only(
            bottom: DScrollChrome.bottomInsetOf(context),
          ),
          child: DPageReadingLaneBox(
            padding: const EdgeInsets.all(16),
            widthLimit: DPageReadingLane.maxWidth - 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListenableBuilder(
                  listenable: appSettings,
                  builder: (context, _) => DSwitchTile(
                    key: const ValueKey('disable-gif-animations-switch'),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    title: DLabel(
                      child: Text(context.l10n.disableGIFAnimations),
                    ),
                    subtitle: DFieldDescription(
                      child: Text(
                        context.l10n.pauseGIFsByDefaultInPostsAndChatMessages,
                      ),
                    ),
                    value: appSettings.disableGifAnimations,
                    onChanged: (value) =>
                        unawaited(appSettings.setDisableGifAnimations(value)),
                  ),
                ),
              ],
            ),
          ),
        ),
        _ => ForumAppearanceSettings(
          key: ValueKey(widget.siteUrl),
          siteUrl: widget.siteUrl,
        ),
      },
    );
  }
}
