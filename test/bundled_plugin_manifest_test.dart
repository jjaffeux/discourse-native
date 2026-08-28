import 'package:discourse_native/src/plugin_api/core_plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_services.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_module.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('full manifest installs the deterministic feature graph', () async {
    final installed = PluginInstaller.install(bundledPluginManifest);
    addTearDown(installed.close);

    expect(installed.descriptors.map((descriptor) => descriptor.id.value), [
      'discourse-github',
      'discourse-lazy-videos',
      'discourse-reactions',
      'discourse-local-dates',
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
    final poll = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'poll',
    );
    final chat = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'chat',
    );
    final resenha = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'resenha',
    );

    expect(localDates.syntaxIds, {'discourse-local-dates/local-date'});
    expect(poll.syntaxIds, {'poll/poll'});
    expect(
      chat.dependencies.map(
        (dependency) => (dependency.id.value, dependency.optional),
      ),
      [('discourse-reactions', false), ('gifs', true)],
    );
    expect(chat.routeNamespaces, {'chat'});
    expect(resenha.dependencies.map((dependency) => dependency.id.value), [
      'chat',
    ]);
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
    expect(session.require(gifsApiService), same(api));
    expect(session.require(chatApiService), same(api));
    expect(session.require(chatGifsApiService), same(api));
    expect(session.require(resenhaControllerService), isNotNull);
  });

  test('production Chat works without its optional GIF dependency', () {
    final installed = PluginInstaller.install(
      const PluginManifest([reactionsModule, chatModule]),
    );
    final api = FakeDiscourseApi();
    final shell = _shell(installed, api);
    addTearDown(() async {
      await shell.pluginSession.close();
      shell.dispose();
      await installed.close();
    });

    final session = shell.pluginSession;
    expect(session.require(chatApiService), same(api));
    expect(session.maybeService(gifsApiService), isNull);
    expect(session.maybeService(chatGifsApiService), isNull);
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
