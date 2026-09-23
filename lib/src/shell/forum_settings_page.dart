import 'package:flutter/material.dart';

import 'forum_appearance_settings.dart';

/// Forum settings occupy the normal content panel so the surrounding workspace
/// is the live result of every appearance edit.
class ForumSettingsPage extends StatelessWidget {
  const ForumSettingsPage({super.key, required this.siteUrl});
  final String siteUrl;

  @override
  Widget build(BuildContext context) =>
      ForumAppearanceSettings(key: ValueKey(siteUrl), siteUrl: siteUrl);
}
