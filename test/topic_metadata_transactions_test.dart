import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_category_picker.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _row = Topic(id: 1, title: 'Original', slug: 'original', categoryId: 1);
const _tag = TopicTag(id: 7, name: 'design');

enum _Field { title, category, tags }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('category change retains an allowed existing tag', () async {
    final fixture = await _fixture();
    fixture.api.tagSearchResponse = (request) {
      final selected =
          request.url.queryParametersAll['selected_tag_ids[]'] ?? [];
      return _tagResults(
        selected.contains('7')
            ? []
            : [
                {'id': 7, 'name': 'design'},
              ],
      );
    };
    fixture.shell.store.update<TopicDetail>(
      _site,
      1,
      (detail) => detail.copyWith(tags: [_tag]),
    );
    final saving = _save(fixture.shell, _Field.category);
    await pumpEventQueue();
    expect(fixture.api.requests, hasLength(1));
    fixture.api.pending.single.complete(const TopicUpdate());
    expect(await saving, isNull);
    expect(fixture.api.requests.single['tags'], [_tag]);
    expect(fixture.shell.currentTopic?.tags, [_tag]);
  });

  test('category change stores the tags the site answers with', () async {
    final fixture = await _fixture();
    final saving = _save(fixture.shell, _Field.category);
    await pumpEventQueue();
    expect(fixture.api.requests.single['tags'], isEmpty);
    fixture.api.pending.single.complete(const TopicUpdate(tags: [_tag]));
    expect(await saving, isNull);
    expect(fixture.shell.currentTopic?.categoryId, 2);
    expect(fixture.shell.currentTopic?.tags, [_tag]);
    expect(fixture.shell.store.read<Topic>(_site, 1)?.tags, [_tag]);
  });

  test(
    'accepted category change recolors and republishes the topic route',
    () async {
      final fixture = await _fixture();
      final saving = _save(fixture.shell, _Field.category);
      await pumpEventQueue();
      var notifications = 0;
      fixture.shell.addListener(() => notifications++);
      fixture.api.pending.single.complete(const TopicUpdate());
      expect(await saving, isNull);
      expect(notifications, greaterThan(0));
      expect(fixture.shell.currentContent?.color, const Color(0xFF888888));
    },
  );

  for (final field in _Field.values) {
    test('$field reports an unexpected write error as unreachable', () async {
      final fixture = await _fixture();
      final saving = _save(fixture.shell, field);
      await pumpEventQueue();
      fixture.api.pending.single.completeError(StateError('Lost response'));
      expect(
        await saving,
        const WriteException(WriteFailure.unreachable).message,
      );
      _expectOriginal(fixture.shell);
    });
  }

  test(
    'category validation keeps eligible peers in each search context',
    () async {
      const mobile = TopicTag(id: 8, name: 'mobile');
      final queries = await _expectCategoryTags(
        selected: [_tag, mobile],
        expected: [_tag, mobile],
        response: (request) {
          final query = request.url.queryParameters;
          final selected =
              request.url.queryParametersAll['selected_tag_ids[]'] ?? [];
          final candidate = query['q'] == 'design' ? _tag : mobile;
          return _tagResults(
            selected.contains('${candidate.id}')
                ? []
                : [
                    {'id': candidate.id, 'name': candidate.name},
                  ],
          );
        },
      );
      expect(
        queries.map(
          (request) => request.url.queryParametersAll['selected_tag_ids[]'],
        ),
        [
          ['8'],
          ['7'],
        ],
      );
    },
  );

  for (final parentFirst in [true, false]) {
    test(
      'category validation retains a child with its parent, parent first $parentFirst',
      () async {
        const child = TopicTag(id: 8, name: 'mobile');
        final selected = parentFirst ? [_tag, child] : [child, _tag];
        await _expectCategoryTags(
          selected: selected,
          expected: selected,
          response: (request) {
            final parent = request.url.queryParameters['q'] == 'design';
            final peers =
                request.url.queryParametersAll['selected_tag_ids[]'] ?? [];
            return _tagResults([
              {
                'id': parent ? 7 : 8,
                'name': parent ? 'design' : 'mobile',
                'disabled': !parent && !peers.contains('7'),
              },
            ]);
          },
        );
      },
    );
  }

  test(
    'category validation removes a child whose required parent is absent',
    () async {
      const child = TopicTag(id: 8, name: 'mobile');
      await _expectCategoryTags(
        selected: [child],
        expected: [],
        response: (request) {
          final peers =
              request.url.queryParametersAll['selected_tag_ids[]'] ?? [];
          return _tagResults([
            {'id': 8, 'name': 'mobile', 'disabled': !peers.contains('7')},
          ]);
        },
      );
    },
  );

  test('category validation preserves one-per-topic peer exclusions', () async {
    const mobile = TopicTag(id: 8, name: 'mobile');
    await _expectCategoryTags(
      selected: [_tag, mobile],
      expected: [],
      response: (request) {
        final design = request.url.queryParameters['q'] == 'design';
        final peers =
            request.url.queryParametersAll['selected_tag_ids[]'] ?? [];
        return _tagResults([
          {
            'id': design ? 7 : 8,
            'name': design ? 'design' : 'mobile',
            'disabled': peers.contains(design ? '8' : '7'),
          },
        ]);
      },
    );
  });

  for (final restriction in ['disabled', 'forbidden', 'missing']) {
    test('category validation removes only the $restriction tag', () async {
      const mobile = TopicTag(id: 8, name: 'mobile');
      await _expectCategoryTags(
        selected: [_tag, mobile],
        expected: [mobile],
        response: (request) {
          final design = request.url.queryParameters['q'] == 'design';
          return _tagResults(
            design && restriction == 'missing'
                ? []
                : [
                    {
                      'id': design ? 7 : 8,
                      'name': design ? 'design' : 'mobile',
                      'disabled': design && restriction == 'disabled',
                    },
                  ],
            forbidden: design && restriction == 'forbidden',
          );
        },
      );
    });
  }

  test(
    'uncertain category eligibility retains the complete original selection',
    () async {
      const mobile = TopicTag(id: 8, name: 'mobile');
      await _expectCategoryTags(
        selected: [_tag, mobile],
        expected: [_tag, mobile],
        response: (request) {
          if (request.url.queryParameters['q'] == 'mobile') {
            throw http.ClientException('Lookup disconnected');
          }
          return _tagResults([
            {'id': 7, 'name': 'design', 'disabled': true},
          ]);
        },
      );
    },
  );

  test(
    'category validation matches name-only tags by their own name',
    () async {
      await _expectCategoryTags(
        selected: [const TopicTag(name: 'design')],
        expected: [const TopicTag(name: 'Design')],
        response: (_) => _tagResults([
          {'name': 'unrelated'},
          {'name': 'Design'},
        ]),
      );
    },
  );

  test('category validation matches a renamed tag by its id', () async {
    await _expectCategoryTags(
      selected: [_tag],
      expected: [const TopicTag(id: 7, name: 'interface')],
      response: (_) => _tagResults([
        {'id': 7, 'name': 'interface'},
      ]),
    );
  });

  testWidgets('category picker retains an allowed existing tag after saving', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_fixture))!;
    fixture.api.tagSearchResponse = (request) {
      final selected =
          request.url.queryParametersAll['selected_tag_ids[]'] ?? [];
      return _tagResults(
        selected.contains('7')
            ? []
            : [
                {'id': 7, 'name': 'design'},
              ],
      );
    };
    fixture.shell.store.update<TopicDetail>(
      _site,
      1,
      (detail) => detail.copyWith(tags: [_tag]),
    );
    await tester.pumpWidget(
      ShellScope(
        controller: fixture.shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Align(
            alignment: Alignment.topLeft,
            child: TopicCategoryMenuAnchor(
              siteUrl: _site,
              topicId: 1,
              categoryId: 1,
              enabled: true,
              builder: (context, open, saving, trigger) => DButton(
                onPressed: open,
                label: Text(saving ? 'Saving' : 'Edit category'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit category'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('topic-category-picker-option', 2))),
    );
    await tester.pumpAndSettle();
    expect(fixture.api.requests, hasLength(1));
    fixture.api.pending.single.complete(const TopicUpdate());
    await tester.pumpAndSettle();
    expect(fixture.api.requests.single['tags'], [_tag]);
    expect(fixture.shell.currentTopic?.categoryId, 2);
    expect(fixture.shell.currentTopic?.tags, [_tag]);
    expect(find.text('Edit category'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final field in _Field.values) {
    test(
      '$field rejects missing credentials without sending a write',
      () async {
        final fixture = await _fixture();
        fixture.auth.keys.clear();
        expect(
          await _save(fixture.shell, field),
          const WriteException(WriteFailure.forbidden).message,
        );
        expect(fixture.api.pending, isEmpty);
        _expectOriginal(fixture.shell);
      },
    );

    test(
      '$field cannot borrow credentials after account replacement',
      () async {
        final fixture = await _fixture();
        final held = fixture.auth.hold = Completer<String?>();
        final saving = _save(fixture.shell, field);
        await pumpEventQueue();
        fixture.shell.lifecycle.invalidate(_site);
        fixture.auth.keys[_site] = 'replacement-key';
        fixture.shell.lifecycle.capture(_site);
        held.complete('replacement-key');
        expect(await saving, _staleMessage(field));
        expect(fixture.api.pending, isEmpty);
        _expectOriginal(fixture.shell);
      },
    );

    test('$field stale response preserves a replacement transaction', () async {
      final fixture = await _fixture();
      final stale = _save(fixture.shell, field);
      await pumpEventQueue();
      expect(fixture.api.pending, hasLength(1));
      fixture.shell.lifecycle.invalidate(_site);
      fixture.auth.keys[_site] = 'replacement-key';
      final replacement = _save(fixture.shell, field);
      await pumpEventQueue();
      expect(fixture.api.pending, hasLength(2));
      expect(fixture.api.keys, ['key', 'replacement-key']);
      fixture.api.pending[0].complete(const TopicUpdate(title: 'Stale'));
      expect(await stale, _staleMessage(field));
      _expectOriginal(fixture.shell);
      fixture.api.pending[1].complete(const TopicUpdate(title: 'Normalized'));
      expect(await replacement, isNull);
      final detail = fixture.shell.currentTopic!;
      switch (field) {
        case _Field.title:
          expect(detail.title, 'Normalized');
        case _Field.category:
          expect(detail.categoryId, 2);
          expect(detail.title, _row.title);
        case _Field.tags:
          expect(detail.tags, [_tag]);
          expect(detail.title, _row.title);
      }
    });

    test('$field cannot publish after shell disposal', () async {
      final fixture = await _fixture();
      final saving = _save(fixture.shell, field);
      await pumpEventQueue();
      fixture.dispose();
      fixture.api.pending.single.complete(const TopicUpdate(title: 'Late'));
      expect(await saving, _staleMessage(field));
      _expectOriginal(fixture.shell);
    });

    test('$field preserves write failures without projecting fields', () async {
      final fixture = await _fixture();
      final saving = _save(fixture.shell, field);
      await pumpEventQueue();
      fixture.api.pending.single.completeError(
        const WriteException(WriteFailure.forbidden),
      );
      expect(
        await saving,
        const WriteException(WriteFailure.forbidden).message,
      );
      _expectOriginal(fixture.shell);
    });
  }

  for (final field in [_Field.title, _Field.category]) {
    test(
      '$field retains its opening conflict baseline across credential lookup',
      () async {
        final fixture = await _fixture();
        final held = fixture.auth.hold = Completer<String?>();
        final saving = _save(fixture.shell, field);
        await pumpEventQueue();
        fixture.shell.store.update<TopicDetail>(
          _site,
          1,
          (detail) => detail.copyWith(title: 'Refreshed', tags: [_tag]),
        );
        held.complete('key');
        await pumpEventQueue();
        final sent = fixture.api.requests.single;
        expect(sent['originalTitle'], 'Original');
        if (field == _Field.category) {
          expect(sent['title'], 'Original');
          expect(sent['originalTags'], isEmpty);
        }
        fixture.api.pending.single.complete(const TopicUpdate());
        expect(await saving, isNull);
      },
    );
  }

  test('sidebar tag command snapshots a caller-owned selection', () async {
    final fixture = await _fixture();
    final held = fixture.auth.hold = Completer<String?>();
    final selection = [_tag];
    final saving = fixture.shell.updateTopicTagsFromSidebar(
      siteUrl: _site,
      topicId: 1,
      tags: selection,
    );
    selection.clear();
    held.complete('key');
    await pumpEventQueue();
    expect(fixture.api.requests.single['tags'], [_tag]);
    fixture.api.pending.single.complete(const TopicUpdate());
    expect(await saving, isNull);
    expect(fixture.shell.currentTopic?.tags, [_tag]);
  });

  test(
    'category validation cannot send a mutation after account retirement',
    () async {
      final fixture = await _fixture();
      fixture.shell.store.update<TopicDetail>(
        _site,
        1,
        (detail) => detail.copyWith(tags: [_tag]),
      );
      final gate = fixture.api.tagSearch = Completer<TopicTagSearch>();
      final saving = _save(fixture.shell, _Field.category);
      await pumpEventQueue();
      expect(fixture.api.tagSearches, 1);
      fixture.shell.lifecycle.invalidate(_site);
      fixture.shell.lifecycle.capture(_site);
      gate.complete(const TopicTagSearch(tags: [_tag]));
      expect(await saving, _staleMessage(_Field.category));
      expect(fixture.api.pending, isEmpty);
      expect(fixture.shell.currentTopic?.categoryId, 1);
      expect(fixture.shell.currentTopic?.tags, [_tag]);
    },
  );

  test(
    'same-field writes settle in response order without a busy refusal',
    () async {
      final fixture = await _fixture();
      final first = fixture.shell.saveTopicTitle(
        siteUrl: _site,
        topicId: 1,
        title: 'First',
      );
      final second = fixture.shell.saveTopicTitle(
        siteUrl: _site,
        topicId: 1,
        title: 'Second',
      );
      await pumpEventQueue();
      expect(fixture.api.pending, hasLength(2));
      fixture.api.pending[1].complete(
        const TopicUpdate(title: 'Second stored'),
      );
      expect(await second, isNull);
      fixture.api.pending[0].complete(const TopicUpdate(title: 'First stored'));
      expect(await first, isNull);
      expect(fixture.shell.currentTopic?.title, 'First stored');
      expect(fixture.shell.currentContent?.title, 'First stored');
    },
  );

  for (final categoryLast in [false, true]) {
    test(
      'category and sidebar tags settle in response order, category last $categoryLast',
      () async {
        final fixture = await _fixture();
        final category = _save(fixture.shell, _Field.category);
        await pumpEventQueue();
        final tags = _save(fixture.shell, _Field.tags);
        await pumpEventQueue();
        expect(fixture.api.pending, hasLength(2));
        if (categoryLast) {
          fixture.api.pending[1].complete(const TopicUpdate());
          expect(await tags, isNull);
          fixture.api.pending[0].complete(const TopicUpdate(tags: []));
          expect(await category, isNull);
        } else {
          fixture.api.pending[0].complete(const TopicUpdate(tags: []));
          expect(await category, isNull);
          fixture.api.pending[1].complete(const TopicUpdate());
          expect(await tags, isNull);
        }
        expect(fixture.shell.currentTopic?.categoryId, 2);
        final expectedTags = categoryLast ? <TopicTag>[] : [_tag];
        expect(fixture.shell.currentTopic?.tags, expectedTags);
        expect(fixture.shell.store.read<Topic>(_site, 1)?.tags, expectedTags);
      },
    );
  }
}

String _staleMessage(_Field field) => switch (field) {
  _Field.title => appL10n.theForumChangedBeforeTheTitleSaved,
  _Field.category => appL10n.theForumChangedBeforeTheCategorySaved,
  _Field.tags => appL10n.theSiteChangedBeforeTagsWereSaved,
};

Future<String?> _save(ShellController shell, _Field field) => switch (field) {
  _Field.title => shell.saveTopicTitle(
    siteUrl: _site,
    topicId: 1,
    title: 'Renamed',
  ),
  _Field.category => shell.saveTopicCategory(
    siteUrl: _site,
    topicId: 1,
    categoryId: 2,
  ),
  _Field.tags => shell.updateTopicTagsFromSidebar(
    siteUrl: _site,
    topicId: 1,
    tags: [_tag],
  ),
};

void _expectOriginal(ShellController shell) {
  for (final (title, categoryId, tags) in [
    (
      shell.store.read<TopicDetail>(_site, 1)?.title,
      shell.store.read<TopicDetail>(_site, 1)?.categoryId,
      shell.store.read<TopicDetail>(_site, 1)?.tags,
    ),
    (
      shell.store.read<Topic>(_site, 1)?.title,
      shell.store.read<Topic>(_site, 1)?.categoryId,
      shell.store.read<Topic>(_site, 1)?.tags,
    ),
  ]) {
    expect(title, _row.title);
    expect(categoryId, 1);
    expect(tags, isEmpty);
  }
}

Future<
  ({
    ShellController shell,
    _MetadataApi api,
    _HeldAuthenticator auth,
    void Function() dispose,
  })
>
_fixture() async {
  final api = _MetadataApi();
  final auth = _HeldAuthenticator()..keys[_site] = 'key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.example',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'sam')),
    ]),
    api: api,
    authenticator: auth,
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  var disposed = false;
  void dispose() {
    if (disposed) return;
    disposed = true;
    shell.dispose();
  }

  addTearDown(() {
    dispose();
    for (final pending in api.pending) {
      if (!pending.isCompleted) pending.complete(const TopicUpdate());
    }
  });
  await shell.load();
  await shell.loadFeed('latest');
  await shell.loadTopic(1, _row.slug);
  shell.openTopicFromList(_row);
  return (shell: shell, api: api, auth: auth, dispose: dispose);
}

final class _HeldAuthenticator extends FakeAuthenticator {
  Completer<String?>? hold;

  @override
  Future<String?> apiKeyFor(String siteUrl) =>
      hold?.future ?? super.apiKeyFor(siteUrl);
}

final class _MetadataApi extends FakeDiscourseApi {
  _MetadataApi()
    : super(
        categoryList: const [
          TopicCategory(id: 2, name: 'Support', color: '888888'),
        ],
        categorySearches: const {
          '': [TopicCategory(id: 2, name: 'Support', color: '888888')],
        },
        feeds: const {
          '/latest.json': [_row],
        },
        topics: const {
          1: (
            detail: TopicDetail(
              id: 1,
              title: 'Original',
              stream: [],
              postsCount: 0,
              categoryId: 1,
              canEdit: true,
              canEditTags: true,
            ),
            posts: [],
          ),
        },
      );

  final pending = <Completer<TopicUpdate>>[];
  final keys = <String>[];
  final requests = <Map<String, Object?>>[];
  final tagQueries = <http.Request>[];
  Completer<TopicTagSearch>? tagSearch;
  int tagSearches = 0;
  http.Response Function(http.Request)? tagSearchResponse;

  Future<TopicUpdate> _write(String apiKey) {
    keys.add(apiKey);
    final result = Completer<TopicUpdate>();
    pending.add(result);
    return result.future;
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
  }) {
    requests.add({
      'title': title,
      'originalTitle': originalTitle,
      'tags': tags?.toList(),
      'originalTags': originalTags?.toList(),
      'categoryId': categoryId,
    });
    return _write(apiKey);
  }

  @override
  Future<void> updateTopicTags({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required Iterable<TopicTag> tags,
    String? clientId,
  }) async {
    requests.add({'tags': tags.toList()});
    await _write(apiKey);
  }

  @override
  Future<TopicTagSearch> searchTopicTags({
    required String siteUrl,
    required String apiKey,
    required String term,
    int? categoryId,
    Iterable<int> selectedTagIds = const [],
    int limit = 20,
    String? clientId,
  }) async {
    tagSearches++;
    if (tagSearch != null) return tagSearch!.future;
    final response = tagSearchResponse;
    if (response == null) return const TopicTagSearch(tags: [_tag]);
    final api = DiscourseApi(
      client: MockClient((request) async {
        tagQueries.add(request);
        return response(request);
      }),
    );
    try {
      return await api.searchTopicTags(
        siteUrl: siteUrl,
        apiKey: apiKey,
        term: term,
        categoryId: categoryId,
        selectedTagIds: selectedTagIds,
        limit: limit,
        clientId: clientId,
      );
    } finally {
      api.close();
    }
  }
}

http.Response _tagResults(
  List<Map<String, Object?>> tags, {
  bool forbidden = false,
}) => http.Response(
  jsonEncode({'results': tags, 'forbidden': forbidden}),
  200,
  headers: {'content-type': 'application/json'},
);

Future<List<http.Request>> _expectCategoryTags({
  required List<TopicTag> selected,
  required List<TopicTag> expected,
  required http.Response Function(http.Request) response,
}) async {
  final fixture = await _fixture();
  fixture.api.tagSearchResponse = response;
  fixture.shell.store.update<TopicDetail>(
    _site,
    1,
    (detail) => detail.copyWith(tags: selected),
  );
  final saving = _save(fixture.shell, _Field.category);
  await pumpEventQueue();
  expect(fixture.api.requests, hasLength(1));
  fixture.api.pending.single.complete(const TopicUpdate());
  expect(await saving, isNull);
  expect(
    fixture.shell.currentTopic?.tags.map((tag) => tag.name),
    expected.map((tag) => tag.name),
  );
  expect(fixture.api.requests.single['originalTags'], selected);
  expect(fixture.api.requests.single['tags'], expected);
  expect(fixture.shell.currentTopic?.categoryId, 2);
  expect(fixture.shell.currentTopic?.tags, expected);
  expect(fixture.shell.store.read<Topic>(_site, 1)?.tags, expected);
  for (final query in fixture.api.tagQueries) {
    expect(query.url.path, '/tags/filter/search.json');
    expect(query.url.queryParameters['categoryId'], '2');
  }
  return fixture.api.tagQueries;
}
