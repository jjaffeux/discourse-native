import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'content_reading_lane.dart';
import 'forum_appearance_settings.dart';
import 'forum_display_settings.dart';
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
    final appSettings = ShellScope.identityOf(context).appSettings;
    return ContentReadingLane(
      basePadding: const EdgeInsets.all(16),
      builder: (context, lane) => Padding(
        padding: lane.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const DIcon(DIcons.gear),
                const SizedBox(width: 10),
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            DTabs<String>.controlled(
              value: _section,
              onChanged: (value) {
                if (value != null) setState(() => _section = value);
              },
              children: const [
                DTabList<String>(
                  variant: DTabListVariant.line,
                  children: [
                    DTabTrigger(value: 'display', child: Text('Display')),
                    DTabTrigger(value: 'themes', child: Text('Themes')),
                    DTabTrigger(
                      value: 'accessibility',
                      child: Text('Accessibility'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: switch (_section) {
                'display' => ForumDisplaySettings(
                  appSettings: appSettings,
                  forumSettings: ShellScope.identityOf(context).forumSettings,
                ),
                'accessibility' => ListenableBuilder(
                  listenable: appSettings,
                  builder: (context, _) => DSwitchTile(
                    key: const ValueKey('disable-gif-animations-switch'),
                    title: const DLabel(child: Text('Disable GIF animations')),
                    subtitle: const DFieldDescription(
                      child: Text(
                        'Pause GIFs by default in posts and chat messages.',
                      ),
                    ),
                    value: appSettings.disableGifAnimations,
                    onChanged: (value) =>
                        unawaited(appSettings.setDisableGifAnimations(value)),
                  ),
                ),
                _ => ForumAppearanceSettings(
                  key: ValueKey(widget.siteUrl),
                  siteUrl: widget.siteUrl,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
