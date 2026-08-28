import 'package:discourse_native/src/plugin_api/core_plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/discourse_github/discourse_github_module.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker_session.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_services.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_contract.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_module.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_module.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('full manifest installs the deterministic feature graph', () async {
    final installed = PluginInstaller.install(bundledPluginManifest);
    addTearDown(installed.close);

    expect(installed.descriptors.map((descriptor) => descriptor.id.value), [
      'discourse-local-dates',
      'discourse-github',
      'discourse-lazy-videos',
      'discourse-reactions',
      'poll',
      'gifs',
      'discourse-ai',
      'discourse-assign',
      'chat',
      'resenha',
    ]);

    final localDates = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'discourse-local-dates',
    );
    final github = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'discourse-github',
    );
    final chat = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'chat',
    );
    final resenha = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'resenha',
    );

    expect(localDates.syntaxIds, {'local-dates'});
    expect(
      github.dependencies.map(
        (dependency) => (dependency.id.value, dependency.optional),
      ),
      [('discourse-local-dates', true)],
    );
    expect(
      chat.dependencies.map(
        (dependency) => (dependency.id.value, dependency.optional),
      ),
      [('gifs', true)],
    );
    expect(chat.routeNamespaces, {'chat'});
    expect(
      resenha.dependencies.map(
        (dependency) => (dependency.id.value, dependency.optional),
      ),
      [('chat', false)],
    );
    expect(resenha.routeNamespaces, {'resenha'});
    expect(resenha.exclusiveClaims, {'app-global-media-session'});
    expect(
      installed.registry.diagnosticsPlugins.map(
        (plugin) => plugin.diagnosticsId,
      ),
      ['resenha'],
    );
  });

  test('core and diagnostics-free compatibility manifests install', () async {
    final core = PluginInstaller.install(corePluginManifest);
    final withoutDiagnostics = PluginInstaller.install(
      bundledPluginManifestWithoutDiagnostics,
    );
    addTearDown(core.close);
    addTearDown(withoutDiagnostics.close);

    expect(core.descriptors, isEmpty);
    expect(core.registry.plugins, isEmpty);
    expect(
      withoutDiagnostics.descriptors.map((descriptor) => descriptor.id.value),
      bundledPluginManifest.modules.map((module) => module.descriptor.id.value),
    );
    expect(withoutDiagnostics.registry.diagnosticsPlugins, isEmpty);
  });

  test('full production sessions resolve the declared dependency chain', () {
    final installed = PluginInstaller.install(bundledPluginManifest);
    final api = FakeDiscourseApi();
    final shell = _shell(installed, api);
    addTearDown(() async {
      await shell.pluginSession.close();
      shell.dispose();
      await installed.close();
    });

    final session = shell.pluginSession;
    expect(session.require(gifsPickerSessionService), isA<GifPickerSession>());
    expect(session.require(chatConversationService), isNotNull);
    expect(session.require(localDatesCookedTimeParserService), isNotNull);
    expect(session.require(resenhaControllerService), isNotNull);
  });

  test('production Chat works without optional GIFs or Reactions', () {
    final installed = PluginInstaller.install(
      const PluginManifest([chatModule]),
    );
    final api = FakeDiscourseApi();
    final shell = _shell(installed, api);
    addTearDown(() async {
      await shell.pluginSession.close();
      shell.dispose();
      await installed.close();
    });

    final session = shell.pluginSession;
    expect(session.require(chatConversationService), isNotNull);
    expect(session.maybeService(gifsPickerSessionService), isNull);
  });

  test('GitHub oneboxes degrade without their optional cooked-time parser', () {
    final githubOnly = PluginInstaller.install(
      const PluginManifest([discourseGithubModule]),
    );
    final withLocalDates = PluginInstaller.install(
      const PluginManifest([discourseGithubModule, localDatesModule]),
    );
    final githubOnlySession = githubOnly.openSession(
      const PluginHostBindings.empty(),
    );
    final withLocalDatesSession = withLocalDates.openSession(
      const PluginHostBindings.empty(),
    );
    addTearDown(() async {
      await githubOnlySession.close();
      await withLocalDatesSession.close();
      await githubOnly.close();
      await withLocalDates.close();
    });

    expect(
      githubOnlySession.maybeService(localDatesCookedTimeParserService),
      isNull,
    );
    expect(
      withLocalDatesSession.require(localDatesCookedTimeParserService),
      isNotNull,
    );
  });

  test('Resenha keeps Chat as a required conversation provider', () {
    expect(
      () => PluginInstaller.install(const PluginManifest([resenhaModule])),
      throwsA(isA<PluginInstallationException>()),
    );
  });
}

ShellController _shell(InstalledPlugins plugins, FakeDiscourseApi api) {
  return ShellController(
    instanceStore: FakeInstanceStore(),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: plugins,
  );
}
