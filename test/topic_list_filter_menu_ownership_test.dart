import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _otherSite = 'https://other.discourse.org';
const _user = DiscourseUser(id: 7, username: 'sam');
const _parent = TopicCategory(
  id: 1,
  name: 'Original category',
  slug: 'original',
  color: '123456',
);
const _child = TopicCategory(
  id: 2,
  parentCategoryId: 1,
  name: 'Original child',
  slug: 'original-child',
  color: '123456',
);
const _otherParent = TopicCategory(
  id: 1,
  name: 'Replacement category',
  slug: 'replacement',
  color: '123456',
);
const _otherChild = TopicCategory(
  id: 2,
  parentCategoryId: 1,
  name: 'Replacement child',
  slug: 'replacement-child',
  color: '123456',
);
const _tag = SidebarTag(id: 3, name: 'Original tag', slug: 'original-tag');

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    for (final menu in ['category', 'subcategory', 'tag']) {
      testWidgets(
        'MainContent $menu menu refuses a replaced feed on $platform',
        (tester) async {
          final fixture = await _fixture(tester, platform: platform);
          final shell = fixture.shell;
          if (menu == 'subcategory') shell.selectTopicListCategory(_parent);
          await tester.pumpAndSettle();
          final navigation = tester.element(find.byType(TopicListNavigation));
          await _open(tester, menu);

          await shell.selectTopicListMode(TopicListMode.topYearly);
          await tester.pumpAndSettle();
          // The real inbox workspace retains this navigation within a tab.
          expect(tester.element(find.byType(TopicListNavigation)), navigation);
          final replacement = shell.topicListContent;
          expect(fixture.observer.pops, 0);
          expect(find.byType(DComboboxContent), findsNothing);
          expect(shell.topicListContent, replacement);
          expect(tester.takeException(), isNull);
          expect(fixture.observer.pops, 0);

          await _open(tester, menu);
          await _choose(tester, menu);
          expect(shell.currentTopicListMode, TopicListMode.topYearly);
          if (menu == 'tag') {
            expect(shell.topicListContent?.tagNames, [_tag.name]);
          } else {
            expect(
              shell.topicListContent?.categoryId,
              menu == 'category' ? 1 : 2,
            );
          }
          expect(fixture.observer.pops, 0);
        },
      );
    }
  }

  for (final menu in ['category', 'subcategory', 'tag']) {
    testWidgets(
      '$menu result refuses a forum switch before the next frame, including colliding IDs',
      (tester) async {
        final fixture = await _fixture(tester);
        final shell = fixture.shell;
        if (menu == 'subcategory') {
          shell.selectInstance(1);
          shell.selectTopicListCategory(_otherParent);
          shell.selectInstance(0);
          shell.selectTopicListCategory(_parent);
          await tester.pumpAndSettle();
        }
        await _open(tester, menu);
        shell.selectInstance(1);
        final replacement = shell.topicListContent;
        // Deliver the old route's result before Flutter rebuilds its anchor.
        await _choose(tester, menu);
        expect(shell.currentInstance?.url, _otherSite);
        expect(shell.topicListContent, replacement);
        expect(tester.takeException(), isNull);

        await _open(tester, menu);
        await _choose(tester, menu, otherForum: true);
        if (menu == 'tag') {
          expect(shell.topicListContent?.tagNames, [_tag.name]);
        } else {
          expect(
            shell.topicListContent?.categoryId,
            menu == 'category' ? 1 : 2,
          );
          expect(
            shell.topicListContent?.feedPath,
            menu == 'category'
                ? '/c/replacement/1.json'
                : '/c/replacement/replacement-child/2.json',
          );
        }
      },
    );
  }

  for (final inline in [false, true]) {
    for (final change in ['tab', 'tags', 'round trip']) {
      testWidgets('tag selection retires after $change (inline: $inline)', (
        tester,
      ) async {
        final fixture = await _fixture(tester, inline: inline);
        final shell = fixture.shell;
        if (change != 'tab') shell.selectTopicListTags(['kept']);
        await tester.pumpAndSettle();
        final openingFeed = shell.topicListContent;
        await _open(tester, 'tag');
        switch (change) {
          case 'tab':
            shell.createTab();
            expect(shell.topicListContent, openingFeed);
          case 'tags':
            shell.selectTopicListTags(['replacement']);
          case 'round trip':
            await shell.selectTopicListMode(TopicListMode.topYearly);
            await tester.pumpAndSettle();
            await shell.selectTopicListMode(TopicListMode.latest);
            expect(shell.topicListContent, openingFeed);
        }
        await tester.pumpAndSettle();
        final replacement = shell.topicListContent;
        final searches = fixture.api.searches.length;
        expect(find.byType(DComboboxContent), findsNothing);
        await tester.pump(const Duration(milliseconds: 300));
        expect(fixture.api.searches, hasLength(searches));
        expect(shell.topicListContent, replacement);

        await _open(tester, 'tag');
        await _choose(tester, 'tag');
        expect(
          shell.topicListContent?.tagNames,
          containsAll([_tag.name, ...replacement!.tagNames]),
        );
      });
    }
  }

  testWidgets('ordinary multi-tag choices survive unrelated notifications', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    fixture.shell.selectTopicListTags(['kept']);
    await tester.pumpAndSettle();
    await _open(tester, 'tag');
    fixture.shell.openAppSettingsModal();
    await tester.pump();
    fixture.shell.closeAppSettingsModal();
    await tester.pump();
    await _choose(tester, 'tag');
    expect(fixture.shell.topicListContent?.tagNames, ['Original tag', 'kept']);

    await _open(tester, 'tag');
    await _choose(tester, 'tag');
    expect(fixture.shell.topicListContent?.tagNames, ['kept']);
    await _open(tester, 'tag');
    await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter-all')));
    await tester.pumpAndSettle();
    expect(fixture.shell.topicListContent?.tagNames, isEmpty);
  });

  for (final change in ['feed', 'tab', 'forum', 'account', 'reconnect']) {
    testWidgets('tag search and results retire after $change replacement', (
      tester,
    ) async {
      final fixture = await _fixture(tester);
      final shell = fixture.shell;
      final api = fixture.api;
      await _open(tester, 'tag');
      api.searches.clear();
      final pending = Completer<List<TopicFilterLookupValue>>();
      api.pending['old'] = pending;
      await _query(tester, 'old');
      expect(api.searches, [
        (siteUrl: _site, term: 'old', apiKey: 'original-key'),
      ]);

      switch (change) {
        case 'feed':
          await shell.selectTopicListMode(TopicListMode.topYearly);
        case 'tab':
          shell.createTab();
        case 'forum':
          shell.selectInstance(1);
        case 'account':
          api.reader = const DiscourseUser(id: 8, username: 'replacement');
          await shell.connectCurrentInstance();
        case 'reconnect':
          await shell.connectCurrentInstance();
      }
      await tester.pump();
      pending.complete(const [TopicFilterLookupValue(name: 'Old result')]);
      await tester.pumpAndSettle();
      expect(find.text('Old result'), findsNothing);
      expect(fixture.observer.pops, 0);

      expect(find.byType(DComboboxContent), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-list-tag-filter-query')),
        findsNothing,
      );
      expect(api.searches, hasLength(1));

      await _open(tester, 'tag');
      await _query(tester, 'new');
      await tester.pumpAndSettle();
      expect(api.searches.last, (
        siteUrl: change == 'forum' ? _otherSite : _site,
        term: 'new',
        apiKey: change == 'account' || change == 'reconnect'
            ? 'api-key'
            : 'original-key',
      ));
      await tester.tap(find.text('New result'));
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.tagNames, ['New result']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('retiring a menu does not pop a route above it', (tester) async {
    final fixture = await _fixture(tester);
    await _open(tester, 'category');
    unawaited(
      fixture.navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covering route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await fixture.shell.selectTopicListMode(TopicListMode.topYearly);
    await tester.pumpAndSettle();
    expect(find.text('Covering route'), findsOneWidget);
    expect(fixture.observer.pops, 0);
    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(DComboboxContent), findsNothing);
    expect(fixture.shell.topicListContent?.categoryId, isNull);
    expect(fixture.observer.pops, 1);
  });
}

Future<void> _open(WidgetTester tester, String menu) async {
  await tester.tap(find.byKey(ValueKey('topic-list-$menu-filter')));
  await tester.pumpAndSettle();
}

Future<void> _choose(
  WidgetTester tester,
  String menu, {
  bool otherForum = false,
}) async {
  final label = switch (menu) {
    'category' => otherForum ? _otherParent.name : _parent.name,
    'subcategory' => otherForum ? _otherChild.name : _child.name,
    _ => _tag.name,
  };
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _query(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('topic-list-tag-filter-query')),
    text,
  );
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<_Fixture> _fixture(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  bool inline = false,
}) async {
  final api = _FilterApi();
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
      instance('other.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()
      ..keys[_site] = 'original-key'
      ..keys[_otherSite] = 'original-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: true,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  addTearDown(shell.dispose);
  await shell.load();
  await shell.loadCategories(_site);
  await shell.loadCategories(_otherSite);
  final fixture = _Fixture(shell, api);
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        navigatorKey: fixture.navigator,
        navigatorObservers: [fixture.observer],
        theme: AppTheme.light.copyWith(platform: platform),
        home: Scaffold(
          body: inline
              ? const TopicListNavigation(child: SizedBox.expand())
              : const MainContent(layout: ShellLayout.expanded),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

class _Fixture {
  _Fixture(this.shell, this.api);

  final ShellController shell;
  final _FilterApi api;
  final navigator = GlobalKey<NavigatorState>();
  final observer = _RouteObserver();
}

class _RouteObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

class _FilterApi extends FakeDiscourseApi {
  _FilterApi() : super(user: _user, feeds: const {'/latest.json': []});

  DiscourseUser reader = _user;
  final searches = <({String siteUrl, String term, String? apiKey})>[];
  final pending = <String, Completer<List<TopicFilterLookupValue>>>{};

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => reader;

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => CategoryLoadResult(
    siteUrl == _site ? [_parent, _child] : [_otherParent, _otherChild],
    complete: true,
    siteTopTags: const [_tag],
  );

  @override
  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int limit = 5,
    String? apiKey,
    String? clientId,
  }) async {
    searches.add((siteUrl: siteUrl, term: term, apiKey: apiKey));
    if (pending[term] case final gate?) return gate.future;
    return term == 'new'
        ? const [TopicFilterLookupValue(name: 'New result')]
        : const [];
  }
}
