// ignore_for_file: prefer_initializing_formals

import 'package:flutter/widgets.dart';

import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../shell/composer_controller.dart';
import 'gif.dart';
import 'gif_picker.dart';
import 'gifs_api.dart';
import 'gifs_settings.dart';

const gifsPluginId = PluginId('gifs');

const gifsApiService = PluginServiceKey<GifsApi>(
  owner: gifsPluginId,
  name: 'api',
);

const gifsSessionService = PluginServiceKey<GifsSessionService>(
  owner: gifsPluginId,
  name: 'session',
);

/// GIF-owned UI/session facade. Callers can open the feature picker without
/// receiving credential storage or site-lifecycle authority.
final class GifsSessionService {
  const GifsSessionService({
    required GifsApi api,
    required PluginRequestHost requests,
    required PluginComposerHost composer,
  }) : _api = api,
       _requests = requests,
       _composer = composer;

  final GifsApi _api;
  final PluginRequestHost _requests;
  final PluginComposerHost _composer;

  GifsSettings settingsFor(String siteUrl) =>
      _composer.siteConfigFor(siteUrl).gifsSettings;

  bool isActive(ComposerController value) => _composer.isActive(value);

  Future<GifResult?> openPicker({
    required BuildContext context,
    required String siteUrl,
    required GifsSettings settings,
  }) => showGifPicker(
    context: context,
    siteUrl: siteUrl,
    api: _api,
    requests: _requests,
    settings: settings,
  );
}
