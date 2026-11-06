import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_filter_controller.dart';
import 'package:discourse_native/src/shell/topic_filter_input.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _tag = SidebarTag(id: 7, name: 'known-tag', slug: 'known-tag');
const _tagOption = TopicFilterOption(name: 'tag:', type: 'tag');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('known tags remain selectable behind an obsolete lookup', (
    tester,
  ) async {
    final api = _TagApi();
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      ownsApi: false,
    );
    addTearDown(shell.dispose);
    await shell.load();
    await shell.loadCategories(_site);
    final submitted = <String>[];
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: TopicFilterInput(
                siteUrl: _site,
                initialQuery: '',
                options: const [_tagOption],
                categories: const [],
                onSubmitted: (query) async => submitted.add(query),
                tokenized: true,
                embedded: true,
                onlyKey: 'tag',
                focusOnOpen: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final old = Completer<List<TopicFilterLookupValue>>();
    api.pending['old'] = old;
    final field = find.byKey(const ValueKey('topic-filter-input'));
    await tester.enterText(field, 'absent');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.enterText(field, 'old');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, _tag.name);
    await tester.pump();
    final row = find.descendant(
      of: find.byType(DCommandList<String>),
      matching: find.text(_tag.name, findRichText: true),
    );
    expect(row, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('topic-filter-token-remove-0')),
      findsOneWidget,
    );
    expect(old.isCompleted, isFalse);
    old.complete(const []);
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
  });

  testWidgets('ready tag suggestions do not wait for tag groups', (
    tester,
  ) async {
    final groups = Completer<List<TopicFilterLookupValue>>();
    final controller = TopicFilterController(
      initialQuery: 'tag:known',
      submitQuery: (_) async {},
      engine: TopicFilterSuggestions(
        options: const [
          _tagOption,
          TopicFilterOption(name: 'tag_group:', type: 'tag_group'),
        ],
        categories: const [],
        categoryLookup: (_) async => const [],
        tags: (_) async => const [TopicFilterLookupValue(name: 'known-tag')],
        tagGroups: (_) => groups.future,
        users: (_) async => const [],
        groups: (_) async => const [],
        allOptions: true,
        menuField: 'tags',
      ),
    );
    addTearDown(controller.dispose);
    final pending = controller.openSuggestions();
    await tester.pump();
    expect(
      controller.suggestions.map((item) => item.displayName),
      contains('known-tag'),
    );
    expect(await controller.ensureFreshSuggestions(), isTrue);
    expect(groups.isCompleted, isFalse);
    groups.complete(const [TopicFilterLookupValue(name: 'Known group')]);
    await pending;
    expect(
      controller.suggestions.map((item) => item.displayName),
      containsAll(['known-tag', 'Known group']),
    );
  });

  testWidgets('empty group results retain local tags while tag search waits', (
    tester,
  ) async {
    final remote = Completer<List<TopicFilterLookupValue>>();
    final controller = TopicFilterController(
      initialQuery: 'tag:known',
      submitQuery: (_) async {},
      engine: TopicFilterSuggestions(
        options: const [
          _tagOption,
          TopicFilterOption(name: 'tag_group:', type: 'tag_group'),
        ],
        categories: const [],
        categoryLookup: (_) async => const [],
        knownTags: const [TopicFilterLookupValue(name: 'known-tag')],
        tags: (_) => remote.future,
        tagGroups: (_) async => const [],
        users: (_) async => const [],
        groups: (_) async => const [],
        allOptions: true,
        menuField: 'tags',
      ),
    );
    addTearDown(controller.dispose);
    final pending = controller.refreshSuggestions();
    await tester.pump();
    expect(controller.selected?.displayName, 'known-tag');
    expect(await controller.ensureFreshSuggestions(), isTrue);
    expect(remote.isCompleted, isFalse);
    remote.complete(const []);
    await pending;
    expect(controller.selected?.displayName, 'known-tag');
  });

  testWidgets('failed tag-group enrichment keeps ready tags', (tester) async {
    final remote = Completer<List<TopicFilterLookupValue>>();
    final controller = TopicFilterController(
      initialQuery: 'tag:known',
      submitQuery: (_) async {},
      engine: TopicFilterSuggestions(
        options: const [
          _tagOption,
          TopicFilterOption(name: 'tag_group:', type: 'tag_group'),
        ],
        categories: const [],
        categoryLookup: (_) async => const [],
        tags: (_) async => const [TopicFilterLookupValue(name: 'known-tag')],
        tagGroups: (_) => remote.future,
        users: (_) async => const [],
        groups: (_) async => const [],
        allOptions: true,
        menuField: 'tags',
      ),
    );
    addTearDown(controller.dispose);
    final pending = controller.refreshSuggestions();
    await tester.pump();
    expect(controller.selected?.displayName, 'known-tag');
    remote.completeError(StateError('offline'));
    await pending;
    expect(controller.selected?.displayName, 'known-tag');
    expect(await controller.ensureFreshSuggestions(), isTrue);
  });

  testWidgets('ready tags survive the parent suggestions-ready rebuild', (
    tester,
  ) async {
    final groups = Completer<List<TopicFilterLookupValue>>();
    final shell = _PartialTagShell(groups.future);
    addTearDown(shell.dispose);
    var ready = false;
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 400,
                height: 500,
                child: TopicFilterInput(
                  siteUrl: _site,
                  initialQuery: '',
                  options: const [
                    _tagOption,
                    TopicFilterOption(name: 'tag_group:', type: 'tag_group'),
                  ],
                  categories: const [],
                  onSubmitted: (_) async {},
                  tokenized: true,
                  embedded: true,
                  onlyKey: 'tag',
                  focusOnOpen: false,
                  onSuggestionsReady: () {
                    if (!ready) setState(() => ready = true);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(ready, isTrue);
    expect(find.text('ready-tag', findRichText: true), findsOneWidget);
    expect(groups.isCompleted, isFalse);
    groups.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('ready-tag', findRichText: true), findsOneWidget);
  });

  testWidgets('tag enrichment preserves the highlighted local choice', (
    tester,
  ) async {
    final remote = Completer<List<TopicFilterLookupValue>>();
    final groups = Completer<List<TopicFilterLookupValue>>();
    final controller = TopicFilterController(
      initialQuery: 'tag:',
      submitQuery: (_) async {},
      engine: TopicFilterSuggestions(
        options: const [
          _tagOption,
          TopicFilterOption(name: 'tag_group:', type: 'tag_group'),
        ],
        categories: const [],
        categoryLookup: (_) async => const [],
        knownTags: const [
          TopicFilterLookupValue(name: 'alpha', description: '1'),
          TopicFilterLookupValue(name: 'beta', description: '2'),
        ],
        tags: (_) => remote.future,
        tagGroups: (_) => groups.future,
        users: (_) async => const [],
        groups: (_) async => const [],
        allOptions: true,
        menuField: 'tags',
      ),
    );
    addTearDown(controller.dispose);
    final pending = controller.refreshSuggestions();
    controller.select(1);
    expect(controller.selected?.displayName, 'alpha');
    groups.complete(const [TopicFilterLookupValue(name: 'Group')]);
    await tester.pump();
    expect(controller.selected?.displayName, 'alpha');
    remote.complete(const [
      TopicFilterLookupValue(name: 'gamma', description: '100'),
    ]);
    await pending;
    expect(controller.suggestions.first.displayName, 'gamma');
    expect(controller.selected?.displayName, 'alpha');
  });

  testWidgets('obsolete partial tag results cannot replace the current query', (
    tester,
  ) async {
    final old = Completer<List<TopicFilterLookupValue>>();
    final groups = Completer<List<TopicFilterLookupValue>>();
    final controller = TopicFilterController(
      initialQuery: 'tag:old',
      submitQuery: (_) async {},
      engine: TopicFilterSuggestions(
        options: const [
          _tagOption,
          TopicFilterOption(name: 'tag_group:', type: 'tag_group'),
        ],
        categories: const [],
        categoryLookup: (_) async => const [],
        knownTags: const [TopicFilterLookupValue(name: 'current')],
        tags: (term) => term == 'old' ? old.future : Future.value(const []),
        tagGroups: (term) =>
            term == 'old' ? groups.future : Future.value(const []),
        users: (_) async => const [],
        groups: (_) async => const [],
        allOptions: true,
        menuField: 'tags',
      ),
    );
    addTearDown(controller.dispose);
    final first = controller.refreshSuggestions();
    controller.text.text = 'tag:current';
    controller.inputChanged(controller.text.text);
    final current = controller.refreshSuggestions();
    old.complete(const [TopicFilterLookupValue(name: 'old')]);
    await tester.pump();
    expect(controller.selected?.displayName, 'current');
    groups.complete(const [TopicFilterLookupValue(name: 'Old group')]);
    await first;
    await current;
    expect(controller.suggestions.map((item) => item.displayName), ['current']);
  });

  testWidgets('server-advertised tag shortcuts do not wait for scoped search', (
    tester,
  ) async {
    final remote = Completer<List<TopicFilterLookupValue>>();
    final controller = TopicFilterController(
      initialQuery: 'tag:',
      submitQuery: (_) async {},
      engine: TopicFilterSuggestions(
        options: const [
          _tagOption,
          TopicFilterOption(name: 'in:tagged'),
        ],
        categories: const [],
        categoryLookup: (_) async => const [],
        tags: (_) => remote.future,
        tagGroups: (_) async => const [],
        users: (_) async => const [],
        groups: (_) async => const [],
        allOptions: true,
        menuField: 'tags',
      ),
    );
    addTearDown(controller.dispose);
    final pending = controller.refreshSuggestions();
    expect(controller.selected?.name, 'in:tagged');
    expect(await controller.ensureFreshSuggestions(), isTrue);
    expect(remote.isCompleted, isFalse);
    remote.complete(const []);
    await pending;
  });
}

class _TagApi extends FakeDiscourseApi {
  _TagApi() : super(categorySiteTopTags: const [_tag]);
  final pending = <String, Completer<List<TopicFilterLookupValue>>>{};
  @override
  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int? categoryId,
    int limit = 5,
    String? apiKey,
    String? clientId,
  }) => pending[term]?.future ?? Future.value(const []);
}

class _PartialTagShell extends ShellController {
  _PartialTagShell(this.pendingGroups)
    : super(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
      );
  final Future<List<TopicFilterLookupValue>> pendingGroups;
  @override
  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int? categoryId,
  }) async => const [TopicFilterLookupValue(name: 'ready-tag')];
  @override
  Future<List<TopicFilterLookupValue>> searchFilterTagGroups({
    required String siteUrl,
    required String term,
  }) => pendingGroups;
}
