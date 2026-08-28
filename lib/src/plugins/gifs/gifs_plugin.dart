import 'dart:async';

import 'package:flutter/material.dart';

import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/composer_controller.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_icons.dart';
import 'gif_picker.dart';
import 'gifs_services.dart';

/// Discourse core's authenticated Klipy picker contribution.
class GifsPlugin implements SitePlugin, ComposerToolbarPlugin {
  const GifsPlugin();

  @override
  String get name => 'gifs';

  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerController composer,
  ) {
    final shell = ShellScope.maybeRead(context);
    if (shell == null ||
        composer.target.isChat ||
        composer.loadingBody ||
        !shell.siteConfigFor(composer.target.siteUrl).gifsEnabled) {
      return const [];
    }
    return [
      ComposerToolbarContribution(
        icon: DIcons.gif,
        label: 'Search GIFs',
        onInvoke: () => unawaited(openGifPickerForComposer(context, composer)),
      ),
    ];
  }
}

/// Opens the shared picker and inserts its result into an unchanged topic
/// composer draft.
Future<void> openGifPickerForComposer(
  BuildContext context,
  ComposerController composer,
) async {
  final shell = ShellScope.maybeRead(context);
  if (shell == null ||
      !identical(shell.visibleComposer, composer) ||
      !shell.siteConfigFor(composer.target.siteUrl).gifsEnabled) {
    return;
  }

  final expectedDocument = composer.text.text;
  final expectedSelection = composer.text.selection;
  final siteUrl = composer.target.siteUrl;
  final api = PluginScope.maybeOf(context)?.maybeService(gifsApiService);
  if (api == null) return;
  final result = await showGifPicker(
    context: context,
    siteUrl: siteUrl,
    api: api,
    credentials: shell.authenticator,
    lifecycle: shell.lifecycle,
    config: shell.siteConfigFor(siteUrl),
  );
  if (result == null || !context.mounted) return;

  final stillCurrent =
      identical(ShellScope.maybeRead(context), shell) &&
      identical(shell.visibleComposer, composer) &&
      composer.text.text == expectedDocument &&
      shell.siteConfigFor(siteUrl).gifsEnabled;
  if (!stillCurrent) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'The composer changed while the GIF picker was open. Nothing was changed.',
        ),
      ),
    );
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
  composer.insertBlock(result.markdown);
  composer.focus.requestFocus();
}
