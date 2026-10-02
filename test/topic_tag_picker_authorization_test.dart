import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _existing = TopicTag(id: 1, name: 'community');
const _row = Topic(id: 1, title: 'Tag this topic', slug: 'tag-this-topic');
const _filter = r"[\s]+";

void main() {
  for (final (outcome, phase, action) in [
    ('forbidden', 'debounce', 'keyboard'),
    ('forbidden', 'lookup', 'button'),
    ('forbidden', 'settled', 'keyboard'),
    ('explanation', 'settled', 'button'),
    ('failed', 'settled', 'keyboard'),
    ('valid', 'settled', 'button'),
    ('valid', 'settled', 'keyboard'),
  ]) {
    testWidgets(
      'Native header create $action respects $outcome $phase lookup',
      (tester) async {
        final api = _TagsApi(outcome: outcome);
        final shell = await _fixture(api);
        await _pumpReader(tester, shell);
        await _open(tester);
        final query = find.byKey(const ValueKey('topic-tag-picker-query'));
        final create = find.byKey(const ValueKey('topic-tag-picker-create'));
        await tester.enterText(query, 'new-tag');
        await tester.pump();
        if (phase != 'debounce') {
          await tester.pump(const Duration(milliseconds: 300));
        }
        if (phase == 'settled') {
          api.release.complete();
          await _settle(tester);
        }
        if (action == 'keyboard') {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        } else if (create.evaluate().isNotEmpty) {
          await tester.tap(create);
        }
        await _settle(tester);
        if (!api.release.isCompleted) {
          expect(shell.currentTopic?.tags, [_existing]);
          expect(api.requests, isEmpty);
          api.release.complete();
          await _settle(tester);
        }
        await _close(tester);
        final allowed = outcome == 'valid';
        expect(api.requests, hasLength(allowed ? 1 : 0));
        expect(
          shell.currentTopic?.tags.map((tag) => tag.name),
          allowed ? ['community', 'new-tag'] : ['community'],
        );
        if (allowed) {
          expect(jsonDecode(api.requests.single.body), {
            'tags': [
              _existing.toJson(),
              {'name': 'new-tag'},
            ],
          });
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      }),
    );
  }

  for (final target in ['option', 'create']) {
    testWidgets(
      'Native header rejects a stale $target tap before repaint',
      (tester) async {
        final api = _TagsApi();
        final shell = await _fixture(api);
        await _pumpReader(tester, shell);
        await _open(tester);
        final query = find.byKey(const ValueKey('topic-tag-picker-query'));
        if (target == 'create') {
          await tester.enterText(query, 'old-tag');
          await tester.pump(const Duration(milliseconds: 300));
          await _settle(tester);
        }
        final stale = target == 'create'
            ? find.byKey(const ValueKey('topic-tag-picker-create'))
            : find.byKey(const ValueKey(('topic-tag-picker-option', 'design')));
        expect(stale, findsOneWidget);
        await tester.enterText(query, 'new-tag');
        await tester.tap(stale);
        await _settle(tester);
        expect(api.requests, isEmpty);
        expect(shell.currentTopic?.tags, [_existing]);
        expect(query, findsOneWidget);
        api.release.complete();
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('topic-tag-picker-create')));
        await _settle(tester);
        await _close(tester);
        expect(jsonDecode(api.requests.single.body), {
          'tags': [
            _existing.toJson(),
            {'name': 'new-tag'},
          ],
        });
        expect(shell.currentTopic?.tags.map((tag) => tag.name), [
          'community',
          'new-tag',
        ]);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      }),
    );
  }
}

Future<void> _open(WidgetTester tester) async {
  await tester.longPress(
    find.byKey(const ValueKey(('topic-header-tag', 'community'))),
  );
  await _settle(tester);
}

Future<void> _close(WidgetTester tester) async {
  if (find.byKey(const ValueKey('topic-tag-picker-query')).evaluate().isEmpty) {
    return;
  }
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  } else {
    await tester.tap(find.byTooltip('Close').last);
  }
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => pumpEventQueue());
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() => pumpEventQueue());
  await tester.pump(const Duration(milliseconds: 300));
}

Future<ShellController> _fixture(_TagsApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(
        user: const DiscourseUser(id: 7, username: 'sam'),
        config: const SiteConfig(taggingEnabled: true),
      ),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() {
    shell.dispose();
    if (!api.release.isCompleted) api.release.complete();
    api.writes.close();
  });
  await shell.load();
  await shell.loadFeed('latest');
  await shell.loadTopic(_row.id, _row.slug);
  shell.openTopicFromList(_row);
  return shell;
}

Future<void> _pumpReader(WidgetTester tester, ShellController shell) async {
  final desktop = defaultTargetPlatform == TargetPlatform.macOS;
  tester.view.physicalSize = desktop
      ? const Size(1100, 800)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
        builder: (context, child) => DToaster(child: child!),
        home: Scaffold(
          body: MainContent(
            layout: desktop ? ShellLayout.expanded : ShellLayout.compact,
            registry: PluginRegistry.empty,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _TagsApi extends FakeDiscourseApi {
  _TagsApi({this.outcome = 'valid'})
    : super(
        feeds: const {
          '/latest.json': [_row],
        },

        topics: const {
          1: (
            detail: TopicDetail(
              id: 1,
              title: 'Tag this topic',
              stream: [101],
              postsCount: 1,
              tags: [_existing],
              canEdit: true,
              canEditTags: true,
            ),
            posts: [
              Post(
                id: 101,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>Body</p>',
              ),
            ],
          ),
        },
      ) {
    writes = DiscourseApi(
      client: MockClient((request) async {
        if (request.url.path == '/site.json') {
          return http.Response(
            jsonEncode({
              'can_tag_topics': true,
              'can_create_tag': true,
              'max_tag_length': 20,
              'tags_filter_regexp': _filter,
            }),
            200,
          );
        }
        if (request.url.path == '/tags/filter/search.json') {
          final term = request.url.queryParameters['q'];
          if (term == 'new-tag') {
            await release.future;
            if (outcome == 'failed') return http.Response('{}', 500);
            return http.Response(
              jsonEncode({
                'results': <Object?>[],
                if (outcome == 'forbidden') 'forbidden': true,
                if (outcome == 'explanation')
                  'forbidden_message': 'Tags are unavailable here.',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'results': term == 'old-tag'
                  ? <Object?>[]
                  : [
                      {'id': 2, 'name': 'design'},
                    ],
            }),
            200,
          );
        }
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );
  }

  final String outcome;
  final release = Completer<void>();
  late final DiscourseApi writes;

  @override
  Future<TopicTagSearch> searchTopicTags({
    required String siteUrl,
    required String apiKey,
    required String term,
    int? categoryId,
    Iterable<int> selectedTagIds = const [],
    int limit = SiteConfig.defaultMaxTagSearchResults,
    String? clientId,
  }) => writes.searchTopicTags(
    siteUrl: siteUrl,
    apiKey: apiKey,
    term: term,
    categoryId: categoryId,
    selectedTagIds: selectedTagIds,
    limit: limit,
    clientId: clientId,
  );
  final requests = <http.Request>[];

  @override
  Future<TopicComposerCapabilities> topicComposerCapabilities({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) => writes.topicComposerCapabilities(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<void> updateTopicTags({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required Iterable<TopicTag> tags,
    String? clientId,
  }) => writes.updateTopicTags(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    tags: tags,
    clientId: clientId,
  );
}
