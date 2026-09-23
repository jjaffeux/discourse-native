import 'package:flutter/material.dart';

import '../../data/forum_settings_store.dart';
import '../../models/forum_theme.dart';
import '../../shell/forum_settings_controller.dart';
import '../../shell/oneboxes/forum_theme.dart';

/// Uses an isolated library so exercising Apply and Undo cannot affect a forum.
class OneboxThemeSample extends StatefulWidget {
  const OneboxThemeSample({super.key, this.longName = false});
  final bool longName;

  static const theme = ForumTheme(
    id: 'custom-moss',
    name: 'Moss',
    brightness: Brightness.light,
    primary: Color(0xff2e4034),
    secondary: Color(0xfff8f8f2),
    tertiary: Color(0xff5d7954),
    quaternary: Color(0xffb39469),
    danger: Color(0xffb85e48),
    success: Color(0xff518751),
    love: Color(0xffb16a86),
    darkerSidebars: true,
    alternate: ForumTheme(
      id: 'custom-moss',
      name: 'Moss',
      brightness: Brightness.dark,
      primary: Color(0xffe2e8d9),
      secondary: Color(0xff202b25),
      tertiary: Color(0xffafc699),
      quaternary: Color(0xffc9ad7c),
      danger: Color(0xffd98770),
      success: Color(0xff9fc28e),
      love: Color(0xffcd92a6),
      darkerSidebars: true,
    ),
  );

  @override
  State<OneboxThemeSample> createState() => _OneboxThemeSampleState();
}

class _OneboxThemeSampleState extends State<OneboxThemeSample> {
  final _settings = ForumSettingsController(store: ForumSettingsStore.memory());

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ForumThemeOnebox(
    theme: widget.longName
        ? ForumTheme.fromJson({
            ...OneboxThemeSample.theme.toJson(),
            'name': 'A calm green theme for comfortable daily reading',
          }, id: 'custom-long-name')
        : OneboxThemeSample.theme,
    siteUrl: 'https://example.com',
    settings: _settings,
  );
}
