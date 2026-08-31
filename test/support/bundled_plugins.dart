import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/assign/assign_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_module.dart';
import 'package:discourse_native/src/plugins/discourse_github/discourse_github_module.dart';
import 'package:discourse_native/src/plugins/discourse_lazy_videos/discourse_lazy_videos_module.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_api.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_module.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_module.dart';
import 'package:discourse_native/src/plugins/poll/poll_module.dart';
import 'package:discourse_native/src/plugins/poll/polls_api.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_api.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_module.dart';

ChatApi _chatApi(PluginApiTransport transport) => transport as ChatApi;

GifsApi _gifsApi(PluginApiTransport transport) => transport as GifsApi;

PollsApi _pollsApi(PluginApiTransport transport) => transport as PollsApi;

({ReactionsApi reads, ReactionsWriteApi writes}) _reactionsApis(
  PluginApiTransport transport,
  DiscourseModelCodec _,
) => (reads: transport as ReactionsApi, writes: transport as ReactionsWriteApi);

final PluginManifest _testBundledPluginManifest = PluginManifest([
  localDatesModule,
  discourseGithubModule,
  discourseLazyVideosModule,
  const ReactionsModule(apiFactory: _reactionsApis),
  const PollModule(apiFactory: _pollsApi),
  const GifsModule(apiFactory: _gifsApi),
  discourseAiModule,
  assignModule,
  const ChatModule(apiFactory: _chatApi),
]);

InstalledPlugins? _installedPlugins;

InstalledPlugins get installedPlugins =>
    _installedPlugins ??= PluginInstaller.install(_testBundledPluginManifest);

PluginRegistry get pluginRegistry => installedPlugins.registry;

List<SitePlugin> get sitePlugins => pluginRegistry.plugins;

final PluginManifest bundledWidgetTestManifest = _testBundledPluginManifest;
