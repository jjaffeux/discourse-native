// ignore_for_file: prefer_initializing_formals

import '../../models/site_config.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../shell/composer_controller.dart';

const localDatesPluginId = PluginId('discourse-local-dates');

const localDatesUiService = PluginServiceKey<LocalDatesUiService>(
  owner: localDatesPluginId,
  name: 'ui',
);

/// Local Dates' read-only view of the current writing and presentation state.
final class LocalDatesUiService {
  const LocalDatesUiService({
    required PluginComposerHost composer,
    required PluginSiteStateHost siteState,
    required PluginCurrentSiteReader currentSite,
  }) : _composer = composer,
       _siteState = siteState,
       _currentSite = currentSite;

  final PluginComposerHost _composer;
  final PluginSiteStateHost _siteState;
  final PluginCurrentSiteReader _currentSite;

  String? get currentSiteUrl => _currentSite();

  bool isActive(ComposerController value) => _composer.isActive(value);

  SiteConfig configFor(String siteUrl) => _siteState.siteConfigFor(siteUrl);

  String? accountTimezoneFor(String siteUrl) =>
      _siteState.currentUserFor(siteUrl)?.timezone;
}
