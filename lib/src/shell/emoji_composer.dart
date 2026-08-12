import 'dart:async';

import 'package:flutter/material.dart';

import '../data/emoji_picker_store.dart';
import 'composer_controller.dart';
import 'emoji_picker.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

typedef ComposerOwnership = bool Function();

/// Opens the shared picker and inserts its result into an unchanged composer.
///
/// The caller supplies ownership because topic composers live in the shell
/// while chat composers live in their channel widget. Everything else —
/// document/selection capture, stale-result rejection, insertion and focus —
/// is deliberately identical.
Future<void> openEmojiPickerForComposer({
  required BuildContext context,
  required ShellController shell,
  required ComposerController composer,
  required EmojiPickerContext pickerContext,
  required ComposerOwnership stillOwns,
  String initialQuery = '',
  Rect? anchor,
}) async {
  final siteUrl = composer.target.siteUrl;
  if (!stillOwns() || !shell.siteConfigFor(siteUrl).emojiEnabled) return;

  final expectedDocument = composer.text.text;
  final expectedSelection = composer.text.selection;
  try {
    final result = await showEmojiPicker(
      context: context,
      siteUrl: siteUrl,
      pickerContext: pickerContext,
      store: shell.emojiPickerStore,
      loadCatalog: ({refresh = false}) => refresh
          ? shell.refreshEmojiCatalog(siteUrl)
          : shell.ensureEmojiCatalog(siteUrl),
      loadSearchAliases: ({refresh = false}) => refresh
          ? shell.refreshEmojiSearchAliases(siteUrl)
          : shell.ensureEmojiSearchAliases(siteUrl),
      initialQuery: initialQuery,
      anchor: anchor,
      anchorContext: context,
    );
    if (result == null) return;

    final unchanged =
        stillOwns() &&
        !composer.isDisposed &&
        composer.text.text == expectedDocument &&
        shell.siteConfigFor(siteUrl).emojiEnabled;
    if (!unchanged) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'The composer changed while the emoji picker was open. Nothing was changed.',
            ),
          ),
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
      shell.emojiPickerStore
          .trackEmoji(siteUrl: siteUrl, context: pickerContext, emoji: result)
          .catchError((_) {}),
    );
  } finally {
    if (stillOwns() && !composer.isDisposed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (stillOwns() && !composer.isDisposed) {
          composer.focus.requestFocus();
        }
      });
    }
  }
}

/// Topic/edit composer entry point. Chat supplies its local ownership closure
/// directly to [openEmojiPickerForComposer].
Future<void> openEmojiPickerForTopicComposer({
  required BuildContext context,
  required ComposerController composer,
  String initialQuery = '',
  Rect? anchor,
}) {
  // An edit's body is filled asynchronously. Inserting into the temporary
  // empty document would either be overwritten by loadedBody or turn a normal
  // load into a stale-document warning.
  if (composer.loadingBody) return Future<void>.value();

  final shell = ShellScope.maybeRead(context);
  if (shell == null) return Future<void>.value();

  bool owns() =>
      context.mounted &&
      identical(ShellScope.maybeRead(context), shell) &&
      identical(shell.visibleComposer, composer);

  return openEmojiPickerForComposer(
    context: context,
    shell: shell,
    composer: composer,
    pickerContext: EmojiPickerContext.topic,
    stillOwns: owns,
    initialQuery: initialQuery,
    anchor: anchor,
  );
}
