import '../plugin_api/plugin_manifest.dart';
import 'assign/assign_module.dart';
import 'chat/chat_module.dart';
import 'discourse_ai/discourse_ai_module.dart';
import 'discourse_github/discourse_github_module.dart';
import 'discourse_lazy_videos/discourse_lazy_videos_module.dart';
import 'gifs/gifs_module.dart';
import 'local_dates/local_dates_module.dart';
import 'poll/poll_module.dart';
import 'reactions/reactions_module.dart';
import 'resenha/resenha_module.dart';

final PluginManifest bundledPluginManifest = PluginManifest([
  localDatesModule,
  discourseGithubModule,
  discourseLazyVideosModule,
  reactionsModule,
  pollModule,
  gifsModule,
  discourseAiModule,
  assignModule,
  chatModule,
  resenhaModule,
]);

final PluginManifest bundledPluginManifestWithoutDiagnostics = PluginManifest([
  localDatesModule,
  discourseGithubModule,
  discourseLazyVideosModule,
  reactionsModule,
  pollModule,
  gifsModule,
  discourseAiModule,
  assignModule,
  chatModule,
  const ResenhaModule.withoutDiagnostics(),
]);
