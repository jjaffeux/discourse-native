import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/forum_theme.dart';
import '../models/forum_theme_share.dart';

Future<void> copyForumTheme(BuildContext context, ForumTheme theme) async {
  try {
    await Clipboard.setData(ClipboardData(text: ForumThemeShare.encode(theme)));
    if (context.mounted) {
      DToast.show(context, appL10n.themeCopiedPasteItIntoAPostOrChat);
    }
  } catch (_) {
    if (context.mounted) {
      DToast.show(context, appL10n.couldNotCopyThemeTryAgain);
    }
  }
}
