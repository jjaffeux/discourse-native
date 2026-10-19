import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugin_api/global_search.dart';
import 'package:discourse_native/src/shell/global_search_api.dart';
import 'package:discourse_native/src/shell/global_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://example.test';
const _pluginScope = GlobalSearchScope.plugin(
  owner: 'progressive',
  name: 'matches',
  label: 'Matches',
);

void main() {
  for (final retireAccount in [false, true]) {
    testWidgets(
      'a progress listener can ${retireAccount ? 'retire its account' : 'replace its query'} reentrantly',
      (tester) async {
        final api = _DeferredApi();
        final lifecycle = SiteLifecycle();
        final search =
            GlobalSearchController(
              api: api,
              credentials: FakeApiCredentialReader(),
              lifecycle: lifecycle,
              debounceDuration: const Duration(milliseconds: 1),
            )..configure(
              siteUrl: _site,
              capabilities: const GlobalSearchCapabilities(),
            );
        addTearDown(search.dispose);
        var replaced = false;
        search.addListener(() {
          if (replaced || search.results.isEmpty) return;
          replaced = true;
          if (retireAccount) {
            lifecycle.invalidate(_site);
            search.configure(
              siteUrl: _site,
              capabilities: const GlobalSearchCapabilities(),
            );
          }
          search.setQuery('replacement');
        });
        search.setQuery('first');
        await tester.pump(const Duration(milliseconds: 10));
        final first = api.calls.single;
        first.progress!(_pluginPage().sections);
        expect(search.query, 'replacement');
        expect(search.results, isEmpty);
        first.progress!(_pluginPage().sections);
        first.pending.complete(_pluginPage());
        await tester.pump(const Duration(milliseconds: 10));
        expect(search.query, 'replacement');
        expect(search.results, isEmpty);
        final next = api.calls.last;
        expect(identical(first, next), isFalse);
        next.pending.complete(
          GlobalSearchPage(
            sections: [
              GlobalSearchSection(
                scope: GlobalSearchScope.forum,
                results: [_row('current', 'Current')],
              ),
            ],
          ),
        );
        await tester.pump();
        expect(search.results.single.id, 'current');
      },
    );
  }

  test(
    'completed sources publish while context is pending; failures stay local',
    () async {
      final fixture = _Fixture();
      final updates = <List<GlobalSearchSection>>[];
      var finished = false;
      final pending = fixture.search(updates.add).then((page) {
        finished = true;
        return page;
      });
      expect(
        fixture.transport.pending.keys,
        containsAll(['context', 'messages', 'general']),
      );
      fixture.plugin.pending.complete(_pluginPage());
      await _flush();
      expect(updates, hasLength(1));
      expect(updates.single.last.results.single.id, 'plugin:1');
      expect(finished, isFalse);
      final first = updates.single;
      fixture.transport.pending['general']!.complete(_body());
      await _flush();
      expect(updates.last.first.topicId, isNull);
      fixture.transport.pending['context']!.complete(_contextBody());
      await _flush();
      expect(updates.last.first.topicId, 7);
      expect(updates.last.first.results.map((row) => row.id), [
        'in-topic:forum:1',
        'in-topic:forum:3',
      ]);
      fixture.transport.pending['messages']!.completeError(
        TimeoutException('private search text'),
      );
      final page = await pending;
      expect(updates, hasLength(3));
      expect(page.sections.first.topicId, 7);
      expect(
        page.sections.where((section) => section.error != null).single.error,
        contains('timed out'),
      );
      expect(page.sections.last.results.single.id, 'plugin:1');
      expect(first, hasLength(1));
      expect(
        () => first.add(
          const GlobalSearchSection(scope: GlobalSearchScope.forum),
        ),
        throwsUnsupportedError,
      );
      expect(() => first.single.results.clear(), throwsUnsupportedError);
    },
  );

  test(
    'all completion orders use fixed precedence, filtering and immutable source slots',
    () async {
      Object? expected;
      for (final order in _permutations([
        'context',
        'messages',
        'general',
        'plugin',
      ])) {
        final fixture = _Fixture();
        final updates = <List<GlobalSearchSection>>[];
        final pending = fixture.search(updates.add);
        final contributedRows = [
          _row('forum:1', 'Plugin winner'),
          _row('extra', 'Extra'),
        ];
        final pluginPage = GlobalSearchPage(
          sections: [
            GlobalSearchSection(
              scope: GlobalSearchScope.forum,
              results: contributedRows,
              hasMore: true,
              error: 'first error',
            ),
            GlobalSearchSection(
              scope: GlobalSearchScope.forum,
              results: [_row('forum:1', 'Last winner')],
              error: 'last error',
            ),
            const GlobalSearchSection(
              scope: GlobalSearchScope.tags,
              results: [
                GlobalSearchResult(
                  id: 'hidden',
                  scope: GlobalSearchScope.tags,
                  title: 'Hidden',
                  path: '/tag/hidden',
                ),
              ],
            ),
            ..._pluginPage().sections,
          ],
        );
        for (final source in order) {
          if (source == 'plugin') {
            fixture.plugin.pending.complete(pluginPage);
          } else {
            fixture.transport.pending[source]!.complete(switch (source) {
              'context' => _contextBody(),
              'general' => _body(),
              _ => <String, dynamic>{},
            });
          }
          await _flush();
          if (source == 'plugin') {
            contributedRows.add(_row('late-mutation', 'Must stay absent'));
          }
        }
        final page = await pending;
        final actual = _describe(page.sections);
        expected ??= actual;
        expect(actual, expected, reason: order.join(', '));
        expect(updates, hasLength(3));
        expect(
          page.sections.any(
            (section) => section.scope == GlobalSearchScope.tags,
          ),
          isFalse,
        );
        final forum = page.sections.singleWhere(
          (section) =>
              section.scope == GlobalSearchScope.forum &&
              section.topicId == null,
        );
        expect(forum.results.map((row) => row.id), ['forum:1', 'extra']);
        expect(forum.results.first.title, 'Last winner');
        expect(forum.error, 'last error');
        expect(forum.hasMore, isTrue);
        expect(page.results.any((row) => row.id == 'late-mutation'), isFalse);
        expect(() => page.sections.clear(), throwsUnsupportedError);
        expect(() => forum.results.clear(), throwsUnsupportedError);
      }
    },
  );

  test(
    'throwing progress consumer drains every source and preserves its error',
    () async {
      final fixture = _Fixture();
      final failure = StateError('consumer failed');
      var calls = 0;
      var completed = false;
      final pending = fixture.search((_) {
        calls++;
        throw failure;
      });
      final checked = expectLater(
        pending,
        throwsA(same(failure)),
      ).then((_) => completed = true);
      fixture.plugin.pending.complete(_pluginPage());
      await _flush();
      expect(calls, 1);
      expect(completed, isFalse);
      fixture.transport.pending['general']!.complete(_body());
      fixture.transport.pending['messages']!.complete({});
      await _flush();
      expect(calls, 1);
      expect(completed, isFalse);
      fixture.transport.pending['context']!.complete(_contextBody());
      await checked;
      expect(completed, isTrue);
    },
  );

  test('abort suppresses progress while all started work drains', () async {
    final fixture = _Fixture();
    final abort = Completer<void>();
    final updates = <List<GlobalSearchSection>>[];
    var completed = false;
    final pending = fixture.search(updates.add, abort: abort.future).then((
      page,
    ) {
      completed = true;
      return page;
    });
    abort.complete();
    fixture.plugin.pending.complete(_pluginPage());
    await _flush();
    expect(updates, isEmpty);
    expect(completed, isFalse);
    fixture.completeCore();
    await pending;
    expect(updates, isEmpty);
  });

  testWidgets('production controller exposes usable sections while loading', (
    tester,
  ) async {
    final fixture = _Fixture();
    final search = GlobalSearchController(
      api: fixture.api,
      credentials: FakeApiCredentialReader()..keys[_site] = 'key',
      lifecycle: SiteLifecycle(),
      debounceDuration: const Duration(milliseconds: 1),
    )..configure(siteUrl: _site, capabilities: fixture.capabilities);
    addTearDown(search.dispose);
    search.setPageContext(topicId: 7);
    search.setQuery('needle');
    await tester.pump(const Duration(milliseconds: 10));
    fixture.plugin.pending.complete(_pluginPage());
    await tester.pump();
    expect(search.phase, GlobalSearchPhase.loading);
    expect(search.results.single.id, 'plugin:1');
    expect(search.hasMore, isFalse);
    fixture.completeCore();
    await tester.pump();
    expect(search.phase, GlobalSearchPhase.results);
    expect(search.sections.first.topicId, 7);
    expect(search.results.any((row) => row.id == 'plugin:1'), isTrue);
  });

  for (final retirement in ['query', 'account', 'site', 'dispose']) {
    testWidgets(
      'late progress and final results cannot publish after $retirement changes',
      (tester) async {
        final api = _DeferredApi();
        final lifecycle = SiteLifecycle();
        final search =
            GlobalSearchController(
              api: api,
              credentials: FakeApiCredentialReader()..keys[_site] = 'key',
              lifecycle: lifecycle,
              debounceDuration: const Duration(milliseconds: 1),
            )..configure(
              siteUrl: _site,
              capabilities: const GlobalSearchCapabilities(),
            );
        var notifications = 0;
        search.addListener(() => notifications++);
        search.setQuery('first');
        await tester.pump(const Duration(milliseconds: 10));
        final first = api.calls.single;
        first.progress!(_pluginPage().sections);
        expect(search.results.single.id, 'plugin:1');
        expect(search.phase, GlobalSearchPhase.loading);
        switch (retirement) {
          case 'query':
            search.setQuery('replacement');
          case 'account':
            lifecycle.invalidate(_site);
          case 'site':
            search.configure(
              siteUrl: 'https://other.test',
              capabilities: const GlobalSearchCapabilities(),
            );
          case 'dispose':
            search.dispose();
        }
        final before = _describe(search.sections);
        final notificationCount = notifications;
        first.progress!([
          GlobalSearchSection(
            scope: GlobalSearchScope.forum,
            results: [_row('stale', 'Stale')],
          ),
        ]);
        first.pending.complete(
          GlobalSearchPage(
            sections: [
              GlobalSearchSection(
                scope: GlobalSearchScope.forum,
                results: [_row('stale-final', 'Stale final')],
              ),
            ],
          ),
        );
        await tester.pump();
        expect(_describe(search.sections), before);
        expect(notifications, notificationCount);
        if (retirement != 'dispose') search.dispose();
        await tester.pump(const Duration(milliseconds: 10));
      },
    );
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

List<Object?> _describe(List<GlobalSearchSection> sections) => [
  for (final section in sections)
    [
      section.scope.keyName,
      section.topicId,
      section.topicTitle,
      section.error,
      section.hasMore,
      for (final row in section.results) [row.id, row.title, row.path],
    ],
];

Iterable<List<String>> _permutations(List<String> values) sync* {
  if (values.isEmpty) {
    yield [];
    return;
  }
  for (final value in values) {
    for (final tail in _permutations(
      values.where((item) => item != value).toList(),
    )) {
      yield [value, ...tail];
    }
  }
}

GlobalSearchResult _row(String id, String title) => GlobalSearchResult(
  id: id,
  scope: GlobalSearchScope.forum,
  title: title,
  path: '/t/topic/7',
);
GlobalSearchPage _pluginPage() => const GlobalSearchPage(
  sections: [
    GlobalSearchSection(
      scope: _pluginScope,
      results: [
        GlobalSearchResult(
          id: 'plugin:1',
          scope: _pluginScope,
          title: 'Plugin match',
          path: '/plugin/1',
        ),
      ],
    ),
  ],
);

Map<String, dynamic> _body() => {
  'posts': [
    {'id': 1, 'topic_id': 7, 'post_number': 1, 'blurb': 'Needle'},
  ],
  'topics': [
    {'id': 7, 'title': 'General match', 'slug': 'topic'},
  ],
};
Map<String, dynamic> _contextBody() => {
  'posts': [
    {
      'id': 3,
      'topic_id': 7,
      'post_number': 3,
      'username': 'mira',
      'blurb': 'Third',
    },
    {
      'id': 1,
      'topic_id': 7,
      'post_number': 1,
      'username': 'mira',
      'blurb': 'First',
    },
    {
      'id': 9,
      'topic_id': 9,
      'post_number': 1,
      'username': 'mira',
      'blurb': 'Other topic',
    },
  ],
  'topics': [
    {'id': 7, 'title': 'Context match', 'slug': 'topic'},
    {'id': 9, 'title': 'Other topic', 'slug': 'other'},
  ],
};

class _Fixture {
  final transport = _Transport();
  final plugin = _Contribution();
  late final api = GlobalSearchApi(transport: transport);
  late final capabilities = GlobalSearchCapabilities(
    authenticated: true,
    tagging: false,
    userDirectory: false,
    contributions: [plugin],
    enabledContributions: {plugin.owner},
  );
  Future<GlobalSearchPage> search(
    void Function(List<GlobalSearchSection>) onProgress, {
    Future<void>? abort,
  }) => api.search(
    siteUrl: _site,
    apiKey: 'key',
    request: GlobalSearchRequest(
      scope: GlobalSearchScope.all,
      query: 'needle',
      capabilities: capabilities,
      contextTopicId: 7,
      contextTopicTitle: 'Current topic',
    ),
    abortTrigger: abort,
    onProgress: onProgress,
  );
  void completeCore() {
    transport.pending['context']!.complete(_contextBody());
    transport.pending['messages']!.complete({});
    transport.pending['general']!.complete(_body());
  }
}

class _Contribution extends GlobalSearchContribution {
  _Contribution() : super('progressive');
  final pending = Completer<GlobalSearchPage>();
  @override
  List<GlobalSearchScope> get scopes => const [_pluginScope];
  @override
  bool available(
    Map<String, dynamic> settings,
    Map<String, dynamic> user,
    bool authenticated,
  ) => true;
  @override
  Future<GlobalSearchPage> search(
    GlobalSearchReadContext context,
    GlobalSearchRequest request,
  ) => pending.future;
}

class _Transport extends FakeDiscourseApi {
  final pending = <String, Completer<Map<String, dynamic>>>{};
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    final uri = Uri.parse(path);
    if (uri.path != '/search/query.json') return Future.value({});
    final source = uri.queryParameters.containsKey('search_context[id]')
        ? 'context'
        : uri.queryParameters['type_filter'] == 'private_messages'
        ? 'messages'
        : 'general';
    final completer = Completer<Map<String, dynamic>>();
    pending[source] = completer;
    return completer.future;
  }
}

class _DeferredApi extends GlobalSearchApi {
  _DeferredApi() : super(transport: FakeDiscourseApi());
  final calls =
      <
        ({
          void Function(List<GlobalSearchSection>)? progress,
          Completer<GlobalSearchPage> pending,
        })
      >[];
  @override
  Future<GlobalSearchCapabilities> capabilities({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchCapabilities base,
  }) async => base;
  @override
  Future<GlobalSearchPage> search({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchRequest request,
    Future<void>? abortTrigger,
    void Function(List<GlobalSearchSection>)? onProgress,
  }) {
    final pending = Completer<GlobalSearchPage>();
    calls.add((progress: onProgress, pending: pending));
    return pending.future;
  }
}
