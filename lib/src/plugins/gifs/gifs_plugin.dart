import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'gifs_icons.dart';
import 'gifs_services.dart';
import 'gifs_settings.dart';

export 'gifs_settings.dart';

class GifsPlugin
    implements
        SitePlugin,
        IconCatalogPlugin,
        SiteSettingsPlugin<GifsSettings>,
        ComposerToolbarPlugin {
  const GifsPlugin();

  @override
  String get name => 'gifs';

  @override
  PluginIconCatalog get iconCatalog => gifsIconCatalog;

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
    final picker = PluginUiScope.maybe(context, gifsPickerSessionService);
    if (!editor.isCurrent ||
        picker == null ||
        editor.isPluginTarget ||
        editor.loadingBody ||
        !picker.isAvailable(editor.siteUrl)) {
      return const [];
    }
    return [
      ComposerToolbarContribution(
        icon: GifsIcons.gif,
        label: appL10n.searchGIFs,
        onInvoke: () => unawaited(openGifPickerForComposer(context, editor)),
      ),
    ];
  }
}

Future<void> openGifPickerForComposer(
  BuildContext context,
  ComposerEditorHost editor,
) async {
  final picker = PluginUiScope.maybe(context, gifsPickerSessionService);
  if (!editor.isCurrent ||
      editor.isPluginTarget ||
      picker == null ||
      !picker.isAvailable(editor.siteUrl)) {
    return;
  }

  final expectedValue = editor.value;
  final siteUrl = editor.siteUrl;
  final result = await picker.showPicker(context: context, siteUrl: siteUrl);
  if (result == null || !context.mounted) return;

  final stillCurrent =
      editor.isCurrent &&
      editor.value == expectedValue &&
      picker.isAvailable(siteUrl);
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
  DToast.show(
    context,
    appL10n.theComposerChangedWhileTheGIFPickerWasOpenNothingWas,
  );
}
