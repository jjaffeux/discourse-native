import 'dart:async';

import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
final _pluginShells = <ShellController>{};

void _disposePluginShell(ShellController shell) {
  if (_pluginShells.remove(shell)) shell.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'an isolated plugin composer accepts title and tags without a body',
    () async {
      final shell = await _pluginShell();
      final outcomes = <PluginTopicCreationOutcome>[];
      await shell.openNewTopic();
      final unrelated = shell.visibleComposer!;
      unrelated.title.text = 'Keep this unrelated draft';
      unrelated.text.text = 'Keep this draft body unchanged';

      expect(
        await shell.openNewTopicFromPlugin(
          OpenNewTopicComposerRequest(
            siteUrl: _siteUrl,
            sourceRouteId: shell.currentContent!.id,
            initialTitle: 'A task with no initial notes',
            initialTags: const ['planned', 'workflow'],
            onCompleted: outcomes.add,
          ),
        ),
        OpenComposerResult.opened,
      );

      final composer = shell.visibleComposer!;
      expect(composer, isNot(same(unrelated)));
      expect(composer.title.text, 'A task with no initial notes');
      expect(composer.tags.map((tag) => tag.name), ['planned', 'workflow']);
      expect(composer.raw, isEmpty);
      expect(composer.canSubmit, isFalse);
      expect(unrelated.raw, 'Keep this draft body unchanged');
      shell.closeComposer(composer: composer);
      expect(outcomes, [isA<PluginTopicCreationCancelled>()]);
      expect(shell.visibleComposer, same(unrelated));
    },
  );

  for (final queued in [false, true]) {
    test(
      'reports only this composer completion once (queued=$queued)',
      () async {
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': <Topic>[]},
          creatableFeedPaths: const {'/latest.json'},
          creation: queued
              ? const PostCreation(
                  outcome: PostOutcome.enqueued,
                  draftSequence: 1,
                )
              : null,
        );
        final shell = await _pluginShell(api: api);
        final outcomes = <PluginTopicCreationOutcome>[];
        await shell.openNewTopicFromPlugin(
          OpenNewTopicComposerRequest(
            siteUrl: _siteUrl,
            sourceRouteId: shell.currentContent!.id,
            initialTitle: 'A specific plugin-created topic',
            seed: const ComposerSeed(raw: 'Enough text for a valid new topic.'),
            onCompleted: outcomes.add,
          ),
        );
        final composer = shell.visibleComposer!;
        expect(outcomes, isEmpty);
        expect(composer.canSubmit, isTrue);
        await shell.submitComposer(composer: composer);
        expect(outcomes, hasLength(1));
        if (queued) {
          expect(outcomes.single, isA<PluginTopicCreationQueued>());
        } else {
          expect(outcomes.single, isA<PluginTopicCreated>());
          expect((outcomes.single as PluginTopicCreated).topicId, 901);
        }
        shell.closeComposer(composer: composer);
        expect(outcomes, hasLength(1));
      },
    );
  }

  test('account retirement cancels a plugin creation continuation', () async {
    final shell = await _pluginShell();
    final outcomes = <PluginTopicCreationOutcome>[];
    await shell.openNewTopicFromPlugin(
      OpenNewTopicComposerRequest(
        siteUrl: _siteUrl,
        sourceRouteId: shell.currentContent!.id,
        initialTitle: 'An account-bound topic',
        onCompleted: outcomes.add,
      ),
    );
    _disposePluginShell(shell);
    expect(outcomes, [isA<PluginTopicCreationCancelled>()]);
  });

  test(
    'a throwing completion cannot retain an already posted composer',
    () async {
      final shell = await _pluginShell();
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      await shell.openNewTopicFromPlugin(
        OpenNewTopicComposerRequest(
          siteUrl: _siteUrl,
          sourceRouteId: shell.currentContent!.id,
          initialTitle: 'A topic whose observer fails',
          seed: const ComposerSeed(raw: 'A valid body for the created topic.'),
          onCompleted: (_) => throw StateError('plugin observer failed'),
        ),
      );
      final composer = shell.visibleComposer!;

      await shell.submitComposer(composer: composer);

      expect(errors, hasLength(1));
      expect(composer.isDisposed, isTrue);
      expect(shell.currentContent?.topicId, 901);
    },
  );

  test('completion can retire the shell without later publication', () async {
    final shell = await _pluginShell();
    var completions = 0;
    await shell.openNewTopicFromPlugin(
      OpenNewTopicComposerRequest(
        siteUrl: _siteUrl,
        sourceRouteId: shell.currentContent!.id,
        initialTitle: 'A topic completed before disposal',
        seed: const ComposerSeed(raw: 'A valid body for the created topic.'),
        onCompleted: (outcome) {
          expect(outcome, isA<PluginTopicCreated>());
          completions++;
          _disposePluginShell(shell);
        },
      ),
    );

    await shell.submitComposer(composer: shell.visibleComposer!);

    expect(_pluginShells.contains(shell), isFalse);
    expect(completions, 1);
  });

  test('opens a new-topic composer with an opaque seed unchanged', () async {
    final drafts = FakeDraftStore();
    await drafts.write(
      _siteUrl,
      'new_topic',
      const ComposerDraft(reply: 'An unrelated saved topic').encode(),
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
          user: const DiscourseUser(id: 7, username: 'reader'),
        ),
      ]),
      api: FakeDiscourseApi(
        feeds: const {'/latest.json': <Topic>[]},
        creatableFeedPaths: const {'/latest.json'},
      ),
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: drafts,
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    await pumpEventQueue();

    final routeId = shell.currentContent!.id;
    const seed = 'opaque-extension-payload:\n  <keep this exactly>';

    expect(
      await shell.openNewTopicFromPlugin(
        const OpenNewTopicComposerRequest(
          siteUrl: _siteUrl,
          sourceRouteId: 'stale-route',
          seed: ComposerSeed(raw: seed),
        ),
      ),
      OpenComposerResult.sourceChanged,
    );
    expect(shell.visibleComposer, isNull);

    expect(
      await shell.openNewTopicFromPlugin(
        OpenNewTopicComposerRequest(
          siteUrl: _siteUrl,
          sourceRouteId: routeId,
          seed: const ComposerSeed(raw: seed),
        ),
      ),
      OpenComposerResult.opened,
    );
    expect(shell.visibleComposer!.target.isNewTopic, isTrue);
    expect(shell.visibleComposer!.raw, seed);
  });

  for (final sameKey in [false, true]) {
    test(
      'a route change cancels a pending seed without replacing its composer (same-key: $sameKey)',
      () async {
        final api = _GatedComposerApi();
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance(
              'meta.discourse.org',
              user: const DiscourseUser(id: 7, username: 'reader'),
            ),
          ]),
          api: api,
          authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);
        await shell.load();

        shell.pushContent(
          ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
        );
        shell.store.put(
          _siteUrl,
          const TopicDetail(
            id: 7,
            title: 'Topic',
            stream: [],
            canCreatePost: true,
          ),
        );
        shell.openReply();
        final retained = shell.visibleComposer!;
        retained.text.text = 'Keep this reply';

        final opening = shell.openNewTopicFromPlugin(
          const OpenNewTopicComposerRequest(
            siteUrl: _siteUrl,
            sourceRouteId: 'topic-7',
            seed: ComposerSeed(raw: 'A new topic seed'),
          ),
        );
        await api.capabilityStarted.future;

        shell.pushContent(
          sameKey
              ? const ContentRoute(
                  destination: FeedDestination(
                    key: 'topic-7',
                    mode: TopicListMode.latest,
                  ),
                  title: 'Latest',
                  icon: DIcons.list,
                )
              : ContentRoute.newTab(),
        );
        api.capabilityGate.complete();

        expect(await opening, OpenComposerResult.sourceChanged);
        expect(shell.visibleComposer, same(retained));
        expect(shell.visibleComposer?.raw, 'Keep this reply');
      },
    );
  }
}

Future<ShellController> _pluginShell({FakeDiscourseApi? api}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
        user: const DiscourseUser(id: 7, username: 'reader'),
      ),
    ]),
    api:
        api ??
        FakeDiscourseApi(
          feeds: const {'/latest.json': <Topic>[]},
          creatableFeedPaths: const {'/latest.json'},
        ),
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  _pluginShells.add(shell);
  addTearDown(() => _disposePluginShell(shell));
  await shell.load();
  await pumpEventQueue();
  return shell;
}

final class _GatedComposerApi extends FakeDiscourseApi {
  _GatedComposerApi()
    : super(
        feeds: const {'/latest.json': <Topic>[]},
        creatableFeedPaths: const {'/latest.json'},
      );

  final capabilityStarted = Completer<void>();
  final capabilityGate = Completer<void>();

  @override
  Future<TopicComposerCapabilities> topicComposerCapabilities({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    capabilityStarted.complete();
    await capabilityGate.future;
    return super.topicComposerCapabilities(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
