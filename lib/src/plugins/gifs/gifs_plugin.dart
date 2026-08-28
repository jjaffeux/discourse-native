import 'dart:async';

import 'package:flutter/material.dart';

import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../theme/d_icons.dart';
import 'gif_picker.dart';
import 'gifs_services.dart';
import 'gifs_settings.dart';

export 'gifs_settings.dart';

/// Discourse core's authenticated Klipy picker contribution.
class GifsPlugin
    implements
        SitePlugin,
        SiteSettingsPlugin<GifsSettings>,
        ComposerToolbarPlugin {
  const GifsPlugin();

  @override
  String get name => 'gifs';

  @override
  PluginDataPersistenceCodec<GifsSettings> get siteSettingsCodec =>
      gifsSettingsPersistenceCodec;

  @override
  GifsSettings readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      GifsSettings.fromSiteSettings(json);

  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerEditorHost editor,
  ) {
    if (!editor.isCurrent ||
        editor.isPluginTarget ||
        editor.loadingBody ||
        !editor.siteSettings.gifsSettings.enabled) {
      return const [];
    }
    return [
      ComposerToolbarContribution(
        icon: DIcons.gif,
        label: 'Search GIFs',
        onInvoke: () => unawaited(openGifPickerForComposer(context, editor)),
      ),
    ];
  }
}

/// Opens the shared picker and inserts its result into an unchanged topic
/// composer draft.
Future<void> openGifPickerForComposer(
  BuildContext context,
  ComposerEditorHost editor,
) async {
  if (!editor.isCurrent ||
      editor.isPluginTarget ||
      !editor.siteSettings.gifsSettings.enabled) {
    return;
  }

  final expectedValue = editor.value;
  final siteUrl = editor.siteUrl;
  final picker = PluginScope.maybeOf(
    context,
  )?.maybeService(gifsPickerHostService);
  if (picker == null) return;
  final result = await showGifPicker(
    context: context,
    siteUrl: siteUrl,
    api: picker.api,
    credentials: picker.credentials,
    lifecycle: picker.lifecycle,
    settings: editor.siteSettings.gifsSettings,
  );
  if (result == null || !context.mounted) return;

  final stillCurrent =
      editor.isCurrent &&
      editor.value == expectedValue &&
      editor.siteSettings.gifsSettings.enabled;
  if (!stillCurrent) {
    _changedComposerMessage(context);
    return;
  }

  if (!editor.insertBlock(
    expectedValue: expectedValue,
    markdown: result.markdown,
  )) {
    _changedComposerMessage(context);
    return;
  }
  editor.requestFocus();
}

void _changedComposerMessage(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(
      content: Text(
        'The composer changed while the GIF picker was open. Nothing was changed.',
      ),
    ),
  );
}
