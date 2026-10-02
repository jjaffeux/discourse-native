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
const _filter = r'''[\/\?#\[\]@!\$&'\(\)\*\+,;=%\\`^\s|\{\}"<>]+''';

void main() {
  for (final (name, allowed) in [
    ('𐐀' * 16, true),
    ('𐐀' * 20, true),
    ('𐐀' * 21, false),
    ('a' * 20, true),
    ('a' * 21, false),
    ('e\u0301' * 10, true),
    ('e\u0301' * 11, false),
    ('invalid#tag', false),
  ]) {
    testWidgets(
      'Native header creates $name ($allowed) with server scalar length rules',
      (tester) async {
        final api = _TagsApi();
        final shell = await _fixture(api);
        await _pumpReader(tester, shell);
        await tester.longPress(
          find.byKey(const ValueKey(('topic-header-tag', 'community'))),
        );
        await tester.pumpAndSettle();
        final query = find.byKey(const ValueKey('topic-tag-picker-query'));
        expect(query, findsOneWidget);
        await tester.enterText(query, name);
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        final create = find.byKey(const ValueKey('topic-tag-picker-create'));
        expect(create, allowed ? findsOneWidget : findsNothing);
        if (allowed) {
          await tester.tap(create);
          await tester.pumpAndSettle();
        }
        if (defaultTargetPlatform == TargetPlatform.macOS) {
          if (query.evaluate().isNotEmpty) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          }
        } else {
          await tester.tap(find.byTooltip('Close').last);
        }
        await tester.pumpAndSettle();
        if (allowed) {
          final request = api.requests.single;
          expect(request.method, 'PUT');
          expect(request.url, Uri.parse('$_site/t/1/tags.json'));
          expect(request.headers['User-Api-Key'], 'key');
          expect(jsonDecode(request.body), {
            'tags': [
              _existing.toJson(),
              {'name': name},
            ],
          });
          expect(shell.currentTopic?.tags.map((tag) => tag.name), [
            _existing.name,
            name,
          ]);
        } else {
          expect(api.requests, isEmpty);
          expect(shell.currentTopic?.tags, [_existing]);
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }

  test(
    'capabilities count Unicode scalars at zero, finite and absent limits',
    () {
      for (final (limit, name, allowed) in [
        (0, '𐐀', false),
        (-1, '𐐀', false),
        (1, '𐐀', true),
        (1, '𐐀a', false),
        (1, 'e\u0301', false),
        (2, 'e\u0301', true),
        (2, '𐐀a', true),
        (null, '𐐀' * 100, true),
      ]) {
        final capabilities = TopicComposerCapabilities(
          canCreateTag: true,
          maxTagLength: limit,
        );
        expect(capabilities.canCreateTagNamed(name), allowed);
      }
      expect(
        const TopicComposerCapabilities(
          canCreateTag: true,
        ).canCreateTagNamed(''),
        isFalse,
      );
      expect(
        const TopicComposerCapabilities().canCreateTagNamed('𐐀'),
        isFalse,
      );
    },
  );
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
  _TagsApi()
    : super(
        feeds: const {
          '/latest.json': [_row],
        },
        topicTagSearches: const {
          '': TopicTagSearch(tags: [_existing]),
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
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );
  }

  late final DiscourseApi writes;
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
