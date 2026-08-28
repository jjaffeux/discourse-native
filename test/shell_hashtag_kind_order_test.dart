import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _expectedOrder = ['category', 'tag', 'room'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a registered hashtag kind reaches composer search and lookup in order',
    (tester) async {
      final plugins = PluginInstaller.install(
        const PluginManifest([_HashtagModule()]),
      );
      final api = FakeDiscourseApi(feeds: const {'/latest.json': <Topic>[]});
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
        plugins: plugins,
      );
      var closed = false;
      Future<void> close() async {
        if (closed) return;
        closed = true;
        await shell.pluginSession.close();
        shell.dispose();
        await plugins.close();
      }

      addTearDown(close);

      await tester.runAsync(() async {
        await shell.load();
        await pumpEventQueue();
      });
      final composer = _openReply(shell);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextField(controller: composer.text)),
        ),
      );

      composer.text.value = const TextEditingValue(
        text: 'see #lou',
        selection: TextSelection.collapsed(offset: 8),
      );
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();

      expect(api.hashtagSearchesRequested, ['lou']);
      expect(api.hashtagSearchOrdersRequested, [_expectedOrder]);
      expect(api.hashtagLookupsRequested, isEmpty);

      // Finishing a hand-typed ref makes the editor project it. That public
      // projection path asks the shell to resolve the ref before drawing it.
      composer.text.value = const TextEditingValue(
        text: 'see #lounge now',
        selection: TextSelection.collapsed(offset: 0),
      );
      await tester.pump();
      await tester.pump();

      expect(api.hashtagLookupsRequested, [
        {'lounge'},
      ]);
      expect(api.hashtagLookupOrdersRequested, [_expectedOrder]);

      // Dispose the composer before the widget-test invariant checks for
      // timers; typing deliberately started its two-second draft debounce.
      await tester.pumpWidget(const SizedBox.shrink());
      await close();
    },
  );
}

ComposerController _openReply(ShellController shell) {
  shell.store.put(
    _siteUrl,
    const TopicDetail(id: 7, title: 'Topic', stream: [], canCreatePost: true),
  );
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  shell.openReply();
  return shell.visibleComposer!;
}

final class _HashtagModule implements PluginModule {
  const _HashtagModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('hashtag-order-probe'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const _HashtagPlugin());
  }
}

final class _HashtagPlugin implements SitePlugin, HashtagKindPlugin {
  const _HashtagPlugin();

  @override
  String get name => 'hashtag-order-probe';

  @override
  List<PluginHashtagKind> get hashtagKinds => const [
    PluginHashtagKind('room', _presentRoom),
  ];
}

HashtagPresentation _presentRoom(HashtagPresentationRequest request) =>
    HashtagPresentation.fromRequest(
      request,
      fallbackIcon: DIcons.microphoneLines,
      colorPolicy: HashtagColorPolicy.none,
    );
