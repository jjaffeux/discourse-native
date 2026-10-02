import 'dart:async';
import 'dart:convert';

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
import 'package:discourse_native/src/shell/topic_inbox_header.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _categoryA = TopicCategory(id: 21, name: 'Design', color: '9464B8');
const _categoryB = TopicCategory(id: 22, name: 'Support', color: '0088CC');
const _tag = TopicTag(id: 1, name: 'community');
const _renamed = 'A clearer topic title';
const _row = Topic(
  id: 1,
  title: 'Original title',
  slug: 'original-title',
  categoryId: 21,
  tags: [_tag],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('title-only save sends only title and its conflict baseline', () async {
    final server = _TopicServer();
    final shell = await _fixture(server);

    expect(
      await shell.saveTopicTitle(
        siteUrl: _siteUrl,
        topicId: _row.id,
        title: '  $_renamed  ',
      ),
      isNull,
    );

    final sent = server.requests.single;
    expect(sent.method, 'PUT');
    expect(sent.url.path, '/t/1.json');
    expect(jsonDecode(sent.body), {
      'title': _renamed,
      'original_title': _row.title,
    });
    expect(server.topic, {
      'title': _renamed,
      'category_id': _categoryA.id,
      'tags': [_tag.toJson()],
    });
    expect(shell.currentTopic?.categoryId, _categoryA.id);
    expect(shell.currentTopic?.tags, [_tag]);
  });

  test('title-only save still rejects an outdated title baseline', () async {
    final server = _TopicServer();
    final shell = await _fixture(server);
    server.topic['title'] = 'Another writer renamed this';

    expect(
      await shell.saveTopicTitle(
        siteUrl: _siteUrl,
        topicId: _row.id,
        title: _renamed,
      ),
      'Edit conflict',
    );
    expect(server.topic['title'], 'Another writer renamed this');
    expect(shell.currentTopic?.title, _row.title);
    expect(shell.currentContent?.title, _row.title);
  });

  test('a cached topic opened from a link takes the title it holds', () async {
    final server = _TopicServer();
    final api = _TopicApi(server);
    final shell = await _fixture(server, api: api);
    shell.closeTopic();
    expect(shell.currentContent?.topicId, isNull);

    // A link without a slug is titled 'Topic' until the topic is known.
    expect(shell.openTopicUrl('$_siteUrl/t/${_row.id}'), isTrue);
    await pumpEventQueue();

    expect(api.topicsOpened, [_row.id]);
    expect(shell.currentContent?.title, _row.title);
  });

  test('a topic edit is checked against the stored title while the route '
      'still has its link placeholder', () async {
    final server = _TopicServer();
    final api = _TopicApi(server);
    final shell = await _fixture(server, api: api);
    shell.closeTopic();
    final hold = api.readHold = Completer<void>();
    final reading = shell.loadTopic(_row.id, _row.slug, force: true);
    // The open joins the read already out, which has yet to retitle it.
    expect(shell.openTopicUrl('$_siteUrl/t/${_row.id}'), isTrue);
    await pumpEventQueue();
    expect(shell.currentContent?.title, 'Topic');

    shell.openEdit(_editable(shell));
    final composer = shell.visibleComposer!;
    expect(
      (composer.title.text, composer.originalTitle),
      (_row.title, _row.title),
    );
    composer.setCategory(_categoryB.id);
    await shell.submitComposer();

    expect(
      jsonDecode(server.requests.single.body),
      containsPair('original_title', _row.title),
    );
    expect(server.topic['category_id'], _categoryB.id);
    expect(shell.visibleComposer, isNull);

    hold.complete();
    await reading;
    expect(shell.currentContent?.title, _row.title);
  });

  test('a renamed title is stored as the site cleaned it and is the next '
      'save baseline', () async {
    final server = _TopicServer(cleanTitle: _prettify);
    final shell = await _fixture(server);
    const cleaned = 'A clearer topic title!';

    expect(
      await shell.saveTopicTitle(
        siteUrl: _siteUrl,
        topicId: _row.id,
        title: 'a clearer topic title!!!',
      ),
      isNull,
    );
    final row = shell.store.read<Topic>(_siteUrl, _row.id)!;
    expect(
      (shell.currentTopic?.title, row.title, shell.currentContent?.title),
      (cleaned, cleaned, cleaned),
    );

    expect(
      await shell.saveTopicTitle(
        siteUrl: _siteUrl,
        topicId: _row.id,
        title: _renamed,
      ),
      isNull,
    );
    expect(jsonDecode(server.requests.last.body), {
      'title': _renamed,
      'original_title': cleaned,
    });
    expect(server.topic['title'], _renamed);
  });

  test('a topic edit stores the title as the site cleaned it and edits '
      'from it next', () async {
    final server = _TopicServer(cleanTitle: _prettify);
    final shell = await _fixture(server);
    const cleaned = 'A clearer topic title!';

    shell.openEdit(_editable(shell));
    shell.visibleComposer!.title.text = 'a clearer topic title!!!';
    await shell.submitComposer();
    expect(shell.visibleComposer, isNull);
    final row = shell.store.read<Topic>(_siteUrl, _row.id)!;
    expect(
      (shell.currentTopic?.title, row.title, shell.currentContent?.title),
      (cleaned, cleaned, cleaned),
    );

    shell.openEdit(_editable(shell));
    final composer = shell.visibleComposer!;
    expect(composer.originalTitle, cleaned);
    composer.setCategory(_categoryB.id);
    await shell.submitComposer();

    expect(
      jsonDecode(server.requests.last.body),
      containsPair('original_title', cleaned),
    );
    expect(server.topic['category_id'], _categoryB.id);
    expect(shell.visibleComposer, isNull);
  });

  testWidgets('pending category response preserves a completed header rename', (
    tester,
  ) async {
    final gate = Completer<void>();
    final server = _TopicServer(categoryResponseGate: gate);
    final shell = await _fixture(server);
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: const Scaffold(
            body: MainContent(
              layout: ShellLayout.expanded,
              registry: PluginRegistry.empty,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final savingCategory = shell.saveTopicCategory(
      siteUrl: _siteUrl,
      topicId: _row.id,
      categoryId: _categoryB.id,
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(server.requests, hasLength(1));
    expect(
      jsonDecode(server.requests.single.body),
      containsPair('category_id', _categoryB.id),
    );
    expect(server.topic['category_id'], _categoryB.id);
    expect(shell.currentTopic?.categoryId, _categoryA.id);
    expect(gate.isCompleted, isFalse);

    final field = find.byKey(const ValueKey('topic-header-title-field'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, _renamed);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(server.requests, hasLength(2));
    expect(server.topic['title'], _renamed);
    expect(shell.currentTopic?.title, _renamed);
    expect(shell.currentContent?.title, _renamed);

    gate.complete();
    expect(await tester.runAsync(() => savingCategory), isNull);
    await tester.pumpAndSettle();

    expect(shell.currentTopic?.title, _renamed);
    expect(shell.currentTopic?.categoryId, _categoryB.id);
    final row = shell.store.read<Topic>(_siteUrl, _row.id)!;
    expect((row.title, row.categoryId), (_renamed, _categoryB.id));
    expect(
      (shell.currentContent?.title, shell.currentContent?.color),
      (_renamed, Color(_categoryB.colorValue)),
    );
    expect(tester.takeException(), isNull);
  });

  for (final removeTag in [false, true]) {
    testWidgets(
      'pending header rename preserves the completed category change with tag removal $removeTag',
      (tester) async {
        final gate = Completer<void>();
        final server = _TopicServer(renameGate: gate);
        final shell = await _fixture(server);
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
              home: const Scaffold(
                body: MainContent(
                  layout: ShellLayout.expanded,
                  registry: PluginRegistry.empty,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TopicInboxHeader), findsOneWidget);
        expect(find.byType(TopicView), findsOneWidget);
        final reader = tester.state(find.byType(TopicView));
        final header = tester.element(find.byType(TopicInboxHeader));
        final field = find.byKey(const ValueKey('topic-header-title-field'));
        expect(
          tester.getTopLeft(field).dx,
          tester.getTopLeft(find.byTooltip('Edit topic category')).dx,
        );
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, _renamed);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        // Keep the title request pending while the other fields are edited.
        expect(server.requests, hasLength(1));
        expect(server.topic['title'], _row.title);

        await tester.tap(find.byTooltip('Edit topic category'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.byKey(const ValueKey(('topic-category-picker-option', 22))),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(server.requests, hasLength(2));
        expect(server.topic['category_id'], _categoryB.id);
        expect(shell.currentTopic?.categoryId, _categoryB.id);
        expect(shell.currentContent?.color, Color(_categoryB.colorValue));

        if (removeTag) {
          // The reader header edits tags from a long press on a tag chip.
          await tester.longPress(
            find.byKey(const ValueKey(('topic-header-tag', 'community'))),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          for (
            var frame = 0;
            frame < 10 &&
                find
                    .byKey(
                      const ValueKey(('topic-tag-picker-option', 'community')),
                    )
                    .evaluate()
                    .isEmpty;
            frame++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(
            find.byKey(
              const ValueKey(('topic-tag-picker-option', 'community')),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }
        final tags = removeTag ? <TopicTag>[] : [_tag];
        expect(server.topic['tags'], tags.map((tag) => tag.toJson()).toList());
        expect(shell.currentTopic?.tags, tags);
        expect(gate.isCompleted, isFalse);

        gate.complete();
        await tester.pumpAndSettle();

        final row = shell.store.read<Topic>(_siteUrl, _row.id)!;
        expect(
          {
            'server': server.topic,
            'detail': [
              shell.currentTopic?.title,
              shell.currentTopic?.categoryId,
              shell.currentTopic?.tags,
            ],
            'row': [row.title, row.categoryId, row.tags],
            'route': (shell.currentContent?.title, shell.currentContent?.color),
          },
          {
            'server': {
              'title': _renamed,
              'category_id': _categoryB.id,
              'tags': tags.map((tag) => tag.toJson()).toList(),
            },
            'detail': [_renamed, _categoryB.id, tags],
            'row': [_renamed, _categoryB.id, tags],
            'route': (_renamed, Color(_categoryB.colorValue)),
          },
        );
        expect(tester.state(find.byType(TopicView)), same(reader));
        expect(tester.element(find.byType(TopicInboxHeader)), same(header));
        expect(find.text('Edit conflict'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

/// The opening post, editable and with the body the edit composer starts from.
Post _editable(ShellController shell) =>
    shell.store.read<Post>(_siteUrl, 101)!.copyWith(canEdit: true, raw: 'Body');

/// What `title_prettify` makes of the titles these tests type.
String _prettify(String title) => title
    .replaceAll(RegExp('!+'), '!')
    .replaceFirstMapped(RegExp('^[a-z]'), (match) => match[0]!.toUpperCase());

Future<ShellController> _fixture(_TopicServer server, {_TopicApi? api}) async {
  final topics = api ?? _TopicApi(server);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(
        user: const DiscourseUser(
          id: 7,
          username: 'sam',
          unifiedNewEnabled: true,
        ),
        config: const SiteConfig(taggingEnabled: true),
      ),
    ]),
    api: topics,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() {
    shell.dispose();
    topics.writes.close();
    for (final gate in [server.renameGate, server.categoryResponseGate]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
  });
  await shell.load();
  await shell.loadFeed('latest');
  await shell.loadTopic(_row.id, _row.slug);
  shell.openTopicFromList(_row);
  return shell;
}

final class _TopicApi extends FakeDiscourseApi {
  _TopicApi(_TopicServer server)
    : writes = DiscourseApi(client: MockClient(server.handle)),
      super(
        feeds: const {
          '/latest.json': [_row],
        },
        categoryList: const [_categoryA, _categoryB],
        categorySearches: const {
          '': [_categoryA, _categoryB],
        },
        composerCapabilities: const TopicComposerCapabilities(
          canTagTopics: true,
        ),
        topicTagSearches: const {
          '': TopicTagSearch(tags: [_tag]),
          'community': TopicTagSearch(tags: [_tag]),
        },
        topics: const {
          1: (
            detail: TopicDetail(
              id: 1,
              title: 'Original title',
              stream: [101],
              postsCount: 1,
              categoryId: 21,
              tags: [_tag],
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
      );

  final DiscourseApi writes;

  /// While set, topic reads wait for it.
  Completer<void>? readHold;

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async {
    await readHold?.future;
    return super.topic(
      siteUrl: siteUrl,
      slug: slug,
      id: id,
      postNumber: postNumber,
      summary: summary,
      apiKey: apiKey,
      clientId: clientId,
      abortTrigger: abortTrigger,
    );
  }

  @override
  Future<TopicUpdate> updateTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required String title,
    required String originalTitle,
    Iterable<TopicTag>? tags,
    Iterable<TopicTag>? originalTags,
    int? categoryId,
    String? clientId,
  }) => writes.updateTopic(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    title: title,
    originalTitle: originalTitle,
    tags: tags,
    originalTags: originalTags,
    categoryId: categoryId,
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

final class _TopicServer {
  _TopicServer({this.renameGate, this.categoryResponseGate, this.cleanTitle});

  final Completer<void>? renameGate;
  final Completer<void>? categoryResponseGate;

  /// `TextCleaner.clean_title`, which the site applies as it stores a title.
  final String Function(String title)? cleanTitle;
  final requests = <http.Request>[];
  final topic = <String, dynamic>{
    'title': _row.title,
    'category_id': _categoryA.id,
    'tags': [_tag.toJson()],
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    expect(request.method, 'PUT');
    expect(request.url.path, isIn(['/t/1.json', '/t/1/tags.json']));
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (body['title'] == _renamed) await renameGate?.future;

    // TopicsController#update checks title and nonempty original tag IDs,
    // then applies fields present in the request without a category baseline.
    final originalTitle = body['original_title'] as String?;
    final originalTags = _tagIds(body['original_tags']);
    if ((originalTitle != null &&
            originalTitle.isNotEmpty &&
            originalTitle != topic['title']) ||
        (originalTags.isNotEmpty &&
            !listEquals(originalTags, _tagIds(topic['tags'])))) {
      return http.Response(
        jsonEncode({
          'errors': ['Edit conflict'],
        }),
        409,
      );
    }
    for (final field in ['title', 'category_id', 'tags']) {
      if (body.containsKey(field)) topic[field] = body[field];
    }
    if (cleanTitle case final clean? when body.containsKey('title')) {
      topic['title'] = clean(topic['title'] as String);
    }
    // TopicsController#update answers with the stored topic, and with its
    // tags when the request carried tags.
    final response = http.Response(
      jsonEncode({
        'basic_topic': {
          'id': _row.id,
          'title': topic['title'],
          'fancy_title': topic['title'],
          'slug': _row.slug,
          'posts_count': 1,
        },
        if (body.containsKey('tags')) 'tags': topic['tags'],
      }),
      200,
    );
    // Apply the category before a later title request, but deliver its answer
    // afterward. The captured response still carries the original title.
    if (body.containsKey('category_id')) await categoryResponseGate?.future;
    return response;
  }

  List<int> _tagIds(Object? value) => [
    for (final tag in (value as List<dynamic>?) ?? const [])
      (tag as Map<String, dynamic>)['id'] as int,
  ]..sort();
}
