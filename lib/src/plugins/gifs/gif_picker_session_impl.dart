import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/widgets.dart';

import 'gif.dart';
import 'gif_picker_session.dart';
import 'gifs_api.dart';
import 'gifs_settings.dart';

typedef GifPickerPresenter =
    Future<GifResult?> Function({
      required BuildContext context,
      required String siteUrl,
      required GifsApi api,
      required PluginRequestHost requests,
      required GifsSettings settings,
    });

GifPickerSession createGifPickerSession({
  required GifsApi api,
  required PluginRequestHost requests,
  required PluginSiteConfigReader siteConfigFor,
  required GifPickerPresenter show,
}) => _DefaultGifPickerSession(api, requests, siteConfigFor, show);

final class _DefaultGifPickerSession implements GifPickerSession {
  const _DefaultGifPickerSession(
    this._api,
    this._requests,
    this._siteConfigFor,
    this._show,
  );

  final GifsApi _api;
  final PluginRequestHost _requests;
  final PluginSiteConfigReader _siteConfigFor;
  final GifPickerPresenter _show;

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
    return _show(
      context: context,
      siteUrl: siteUrl,
      api: _api,
      requests: _requests,
      settings: settings,
    );
  }
}
