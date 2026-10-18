// ignore_for_file: prefer_initializing_formals

import 'package:discourse_native/discourse_plugin_sdk.dart';

const localDatesPluginId = PluginId('discourse-local-dates');

const localDatesUiService = PluginServiceKey<LocalDatesUiService>(
  owner: localDatesPluginId,
  name: 'ui',
);

final class LocalDatesUiService {
  const LocalDatesUiService({
    required PluginSiteStateHost siteState,
    required PluginCurrentSiteReader currentSite,
  }) : _siteState = siteState,
       _currentSite = currentSite;

  final PluginSiteStateHost _siteState;
  final PluginCurrentSiteReader _currentSite;

  String? get currentSiteUrl => _currentSite();

  SiteConfig configFor(String siteUrl) => _siteState.siteConfigFor(siteUrl);

  String? accountTimezoneFor(String siteUrl) =>
      _siteState.currentUserFor(siteUrl)?.timezone;
}
