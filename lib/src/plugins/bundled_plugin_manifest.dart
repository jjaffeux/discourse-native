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

/// The deterministic composition of plugins which ship in the core package.
///
/// Resenha is a separately packaged native plugin. The full application adds
/// it from its outer composition root under `profiles/full`.
const PluginManifest bundledPluginManifest = PluginManifest([
  discourseGithubModule,
  discourseLazyVideosModule,
  reactionsModule,
  localDatesModule,
  pollModule,
  gifsModule,
  discourseAiModule,
  assignModule,
  chatModule,
]);

/// Compatibility name for widget hosts which own their diagnostics lifecycle.
///
/// The package-owned bundle has no app-global diagnostics plugin now that
/// Resenha is composed only by the full application.
const PluginManifest bundledPluginManifestWithoutDiagnostics =
    bundledPluginManifest;
