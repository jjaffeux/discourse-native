import '../../plugin_api/plugin_manifest.dart';
import 'gif_picker_session.dart';

const gifsPluginId = PluginId('gifs');

const gifsPickerSessionService = PluginServiceKey<GifPickerSession>(
  owner: gifsPluginId,
  name: 'picker-session',
);
