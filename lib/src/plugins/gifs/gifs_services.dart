import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'gif_picker_session.dart';

const gifsPluginId = PluginId('gifs');

const gifsPickerSessionService = PluginServiceKey<GifPickerSession>(
  owner: gifsPluginId,
  name: 'picker-session',
);
