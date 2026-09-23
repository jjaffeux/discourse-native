import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/forum_theme.dart';
import '../models/forum_theme_share.dart';

Future<void> copyForumTheme(BuildContext context, ForumTheme theme) async {
  try {
    await Clipboard.setData(ClipboardData(text: ForumThemeShare.encode(theme)));
    if (context.mounted) {
      DToast.show(context, 'Theme copied. Paste it into a post or chat.');
    }
  } catch (_) {
    if (context.mounted) {
      DToast.show(context, 'Could not copy theme. Try again.');
    }
  }
}
