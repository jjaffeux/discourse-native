import '../../plugin_api/plugin_manifest.dart';
import 'gifs_api.dart';

const gifsPluginId = PluginId('gifs');

const gifsApiService = PluginServiceKey<GifsApi>(
  owner: gifsPluginId,
  name: 'api',
);
