import '../../data/api_credentials.dart';
import '../../data/site_lifecycle.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'gifs_api.dart';

const gifsPluginId = PluginId('gifs');

const gifsApiService = PluginServiceKey<GifsApi>(
  owner: gifsPluginId,
  name: 'api',
);

/// GIF-owned dependencies needed while its composer picker is open.
///
/// Keeping these beside the feature's API service lets the toolbar use the
/// narrow composer editor host for document state instead of reaching through
/// the application shell for either concern.
final class GifsPickerHost {
  const GifsPickerHost({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  final GifsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
}

const gifsPickerHostService = PluginServiceKey<GifsPickerHost>(
  owner: gifsPluginId,
  name: 'picker-host',
);
