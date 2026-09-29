import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../theme/app_theme.dart';
import 'about_dialog.dart';

@Preview(name: 'About — light', group: 'Shell', size: Size(440, 500))
Widget aboutDialogLightPreview() => _preview(AppTheme.light);

@Preview(name: 'About — dark', group: 'Shell', size: Size(440, 500))
Widget aboutDialogDarkPreview() => _preview(AppTheme.dark);

@Preview(name: 'About — narrow', group: 'Shell', size: Size(320, 568))
Widget aboutDialogNarrowPreview() => _preview(AppTheme.light);

Widget _preview(ThemeData theme) => MaterialApp(
  theme: theme,
  home: DDialog<void>(
    initiallyOpen: true,
    trigger: DDialogTrigger(
      builder: (context, open) => const SizedBox.shrink(),
    ),
    content: const NativeAboutDialog(),
  ),
);
