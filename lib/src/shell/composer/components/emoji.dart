import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../../../models/emoji_usage.dart';
import '../../../plugin_api/core_plugin_host.dart';
import '../../emoji_picker.dart';
import '../controller.dart';

typedef ComposerOwnership = bool Function();

Future<void> openEmojiPickerForComposer({
  required BuildContext context,
  required PluginEmojiHost emoji,
  required ComposerController composer,
  required EmojiUsageContext pickerContext,
  required ComposerOwnership stillOwns,
  String initialQuery = '',
  Rect? anchor,
}) async {
  final siteUrl = composer.target.siteUrl;
  if (!stillOwns() ||
      !composer.isEditing ||
      !emoji.siteConfigFor(siteUrl).emojiEnabled) {
    return;
  }

  final expectedDocument = composer.text.text;
  final expectedSelection = composer.text.selection;
  try {
    final result = await showEmojiPicker(
      context: context,
      siteUrl: siteUrl,
      pickerContext: pickerContext,
      store: emoji.preferences,
      loadCatalog: ({refresh = false}) =>
          emoji.loadCatalog(siteUrl, refresh: refresh),
      loadSearchAliases: ({refresh = false}) =>
          emoji.loadSearchAliases(siteUrl, refresh: refresh),
      initialQuery: initialQuery,
      anchor: anchor,
      anchorContext: context,
    );
    if (result == null) return;

    final unchanged =
        stillOwns() &&
        composer.isEditing &&
        composer.text.text == expectedDocument &&
        emoji.siteConfigFor(siteUrl).emojiEnabled;
    if (!unchanged) {
      if (context.mounted) {
        DToast.show(
          context,
          appL10n.theComposerChangedWhileTheEmojiPickerWasOpenNothingWas,
        );
      }
      return;
    }

    if (expectedSelection.isValid &&
        expectedSelection.start >= 0 &&
        expectedSelection.end <= composer.text.text.length) {
      composer.text.value = composer.text.value.copyWith(
        selection: expectedSelection,
        composing: TextRange.empty,
      );
    }
    composer.insertEmoji(result);
    unawaited(
      emoji.preferences
          .trackEmoji(siteUrl: siteUrl, context: pickerContext, emoji: result)
          .catchError((_) {}),
    );
  } finally {
    if (stillOwns() && composer.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (stillOwns() && composer.isEditing) {
          composer.focus.requestFocus();
        }
      });
    }
  }
}
