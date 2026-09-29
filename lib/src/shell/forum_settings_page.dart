import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DPageReadingLaneBox(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          widthLimit: DPageReadingLane.maxWidth - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const DIcon(DIcons.gear),
                  const SizedBox(width: 10),
                  Text(
                    context.l10n.settings,
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
                children: [
                  DTabList<String>(
                    variant: DTabListVariant.line,
                    children: [
                      DTabTrigger(
                        value: 'display',
                        child: Text(context.l10n.display),
                      ),
                      DTabTrigger(
                        value: 'themes',
                        child: Text(context.l10n.themes),
                      ),
                      DTabTrigger(
                        value: 'accessibility',
                        child: Text(context.l10n.accessibility),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        Expanded(
          child: switch (_section) {
            'display' => ForumDisplaySettings(
              appSettings: appSettings,
              forumSettings: ShellScope.identityOf(context).forumSettings,
            ),
            'accessibility' => DPageReadingLaneBox(
              padding: const EdgeInsets.all(16),
              widthLimit: DPageReadingLane.maxWidth - 32,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListenableBuilder(
                    listenable: appSettings,
                    builder: (context, _) => DSwitchTile(
                      key: const ValueKey('disable-gif-animations-switch'),
                      hoverHighlight: true,
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
            _ => ForumAppearanceSettings(
              key: ValueKey(widget.siteUrl),
              siteUrl: widget.siteUrl,
            ),
          },
        ),
      ],
    );
  }
}
