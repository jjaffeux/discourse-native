import 'package:flutter/widgets.dart';

import '../../data/api_credentials.dart';
import '../../data/site_lifecycle.dart';
import '../../plugin_api/core_plugin_host.dart';
import 'gif.dart';
import 'gif_picker.dart';
import 'gif_picker_session.dart';
import 'gifs_api.dart';
import 'gifs_settings.dart';

/// Builds the production picker session from GIF-private infrastructure.
GifPickerSession createGifPickerSession({
  required GifsApi api,
  required ApiCredentialReader credentials,
  required SiteLifecycle lifecycle,
  required PluginSiteConfigReader siteConfigFor,
}) => _DefaultGifPickerSession(api, credentials, lifecycle, siteConfigFor);

final class _DefaultGifPickerSession implements GifPickerSession {
  const _DefaultGifPickerSession(
    this._api,
    this._credentials,
    this._lifecycle,
    this._siteConfigFor,
  );

  final GifsApi _api;
  final ApiCredentialReader _credentials;
  final SiteLifecycle _lifecycle;
  final PluginSiteConfigReader _siteConfigFor;

  @override
  bool isAvailable(String siteUrl) =>
      _siteConfigFor(siteUrl).gifsSettings.enabled;

  @override
  Future<GifResult?> showPicker({
    required BuildContext context,
    required String siteUrl,
  }) {
    final settings = _siteConfigFor(siteUrl).gifsSettings;
    if (!settings.enabled) return Future<GifResult?>.value();
    return showGifPicker(
      context: context,
      siteUrl: siteUrl,
      api: _api,
      credentials: _credentials,
      lifecycle: _lifecycle,
      settings: settings,
    );
  }
}
