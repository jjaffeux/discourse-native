import 'package:flutter/widgets.dart';

import '../../models/emoji_usage.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../shell_scope.dart';
import 'components/emoji.dart';
import 'controller.dart';

/// Opens the emoji picker for a forum composer, with the shell as its emoji
/// host. Plugin composers bring their own host through
/// [openEmojiPickerForComposer].
Future<void> openEmojiPickerForTopicComposer({
  required BuildContext context,
  required ComposerController composer,
  String initialQuery = '',
  Rect? anchor,
}) {
  // An edit's body is filled asynchronously. Inserting into the temporary
  // empty document would either be overwritten by loadedBody or turn a normal
  // load into a stale-document warning.
  if (!composer.isEditing) return Future<void>.value();

  final shell = ShellScope.maybeRead(context);
  if (shell == null) return Future<void>.value();

  bool owns() =>
      context.mounted &&
      identical(ShellScope.maybeRead(context), shell) &&
      identical(shell.visibleComposer, composer);

  final emoji = PluginEmojiHost(
    preferences: shell.emojiPickerStore,
    siteConfigFor: shell.siteConfigFor,
    loadCatalog: (siteUrl, {refresh = false}) => refresh
        ? shell.refreshEmojiCatalog(siteUrl)
        : shell.ensureEmojiCatalog(siteUrl),
    loadSearchAliases: (siteUrl, {refresh = false}) => refresh
        ? shell.refreshEmojiSearchAliases(siteUrl)
        : shell.ensureEmojiSearchAliases(siteUrl),
    resolveUrl: shell.emojiUrlFor,
  );

  return openEmojiPickerForComposer(
    context: context,
    emoji: emoji,
    composer: composer,
    pickerContext: CoreEmojiUsageContexts.topic,
    stillOwns: owns,
    initialQuery: initialQuery,
    anchor: anchor,
  );
}
