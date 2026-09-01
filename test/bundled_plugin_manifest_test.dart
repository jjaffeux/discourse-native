import 'package:discourse_native/src/plugin_api/core_plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/chat/chat_conversation_contract.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/discourse_github/discourse_github_module.dart';
import 'package:discourse_native/src/plugins/discourse_github/discourse_github_services.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_services.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_contract.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_module.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

void main() {
  test('bundled manifest installs the deterministic feature graph', () async {
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
    final poll = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'poll',
    );
    final github = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'discourse-github',
    );
    final chat = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'chat',
    );
    final discourseAi = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'discourse-ai',
    );
    final assign = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'discourse-assign',
    );

    expect(localDates.syntaxIds, {'discourse-local-dates/local-date'});
    expect(poll.syntaxIds, {'poll/poll'});
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
    expect(assign.routeNamespaces, {'assign'});
    expect(chat.liveChannelScopes.map((scope) => scope.path), {
      '/chat',
      '/presence/chat',
    });
    expect(discourseAi.liveChannelScopes.map((scope) => scope.path), {
      '/discourse-ai',
    });
    expect(
      installed.registry.diagnosticsPlugins.map(
        (plugin) => plugin.diagnosticsId,
      ),
      ['resenha'],
    );
  });

  test('core manifest installs without optional features', () async {
    final core = PluginInstaller.install(corePluginManifest);
    addTearDown(core.close);

    expect(core.descriptors, isEmpty);
    expect(core.registry.plugins, isEmpty);
  });

  test('host-focused widget manifest omits native media sessions', () async {
    final installed = PluginInstaller.install(bundledWidgetTestManifest);
    addTearDown(installed.close);

    expect(
      installed.descriptors.map((descriptor) => descriptor.id.value),
      bundledPluginManifest.modules
          .map((module) => module.descriptor.id.value)
          .where((id) => id != 'resenha'),
    );
  });

  test('bundled production sessions resolve the dependency chain', () {
    final installed = PluginInstaller.install(bundledPluginManifest);
    final api = FakeDiscourseApi();
    final shell = _shell(installed, api);
    addTearDown(() async {
      await shell.pluginSession.close();
      shell.dispose();
      await installed.close();
    });

    final session = shell.pluginSession;
    expect(
      session.require(chatGifsService),
      same(session.require(gifsPickerSessionService)),
    );
    final ChatConversationCapability _ = session.require(
      chatConversationService,
    );
    final CookedTimeParser _ = session.require(
      localDatesCookedTimeParserService,
    );
  });

  test(
    'a Chat-only manifest registers conversations without the GIF service',
    () {
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
      final ChatConversationCapability _ = session.require(
        chatConversationService,
      );
      expect(session.maybeService(gifsPickerSessionService), isNull);
    },
  );

  test('GitHub oneboxes degrade without their optional cooked-time parser', () {
    final githubOnly = PluginInstaller.install(
      const PluginManifest([discourseGithubModule]),
    );
    final withLocalDates = PluginInstaller.install(
      PluginManifest([discourseGithubModule, localDatesModule]),
    );
    final githubOnlySession = githubOnly.openSession(
      const PluginHostBindings.empty(),
    );
    final withLocalDatesShell = _shell(withLocalDates, FakeDiscourseApi());
    final withLocalDatesSession = withLocalDatesShell.pluginSession;
    addTearDown(() async {
      await githubOnlySession.close();
      await withLocalDatesSession.close();
      withLocalDatesShell.dispose();
      await githubOnly.close();
      await withLocalDates.close();
    });

    expect(
      githubOnlySession.maybeService(localDatesCookedTimeParserService),
      isNull,
    );
    final CookedTimeParser _ = withLocalDatesSession.require(
      localDatesCookedTimeParserService,
    );
    expect(
      withLocalDatesSession.require(discourseGithubCookedTimeParserService),
      same(withLocalDatesSession.require(localDatesCookedTimeParserService)),
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
