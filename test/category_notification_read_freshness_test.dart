import 'dart:async';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(
  id: 7,
  username: 'reader',
  watchedCategoryIds: [],
  trackedCategoryIds: [],
  watchedFirstPostCategoryIds: [],
  mutedCategoryIds: [],
  indirectlyMutedCategoryIds: [],
);

TopicCategory _category({
  int id = 1,
  String name = 'Category',
  CategoryNotificationLevel level = CategoryNotificationLevel.normal,
}) => TopicCategory.fromJson({
  'id': id,
  'name': name,
  'slug': 'category-$id',
  'color': '123456',
  'notification_level': level.value,
});

Future<ShellController> _loadShell(_Api api, {Store? store}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    store: store,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    ownsApi: false,
  );
  addTearDown(shell.dispose);
  await shell.load();
  await pumpEventQueue();
  await shell.loadCategories(_site);
  return shell;
}

Future<List<TopicCategory>> _read(ShellController shell, String route) async {
  switch (route) {
    case 'list':
      await shell.loadCategories(_site, force: true);
    case 'page':
      await shell.loadMoreCategories(_site);
    case 'filter':
      return shell.searchFilterCategories(siteUrl: _site, term: 'held');
    case 'editor':
      return shell.searchTopicCategoriesForEditor(siteUrl: _site, term: 'held');
  }
  return [shell.categoryFor(1, siteUrl: _site)!];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  for (final route in ['list', 'page', 'filter', 'editor']) {
    test(
      '$route read preserves an accepted choice and merges metadata',
      () async {
        final api = _Api();
        final shell = await _loadShell(api);
        final held = api.holdRead(route);
        final reading = _read(shell, route);
        await api.readStarted.future;
        expect(
          await shell.updateCategoryNotificationLevel(
            _site,
            1,
            CategoryNotificationLevel.watching,
          ),
          isTrue,
        );
        held.complete([_category(name: 'Renamed')]);
        final results = await reading;
        expect(
          results.single.notificationLevel,
          CategoryNotificationLevel.watching,
        );
        expect(shell.categoryFor(1, siteUrl: _site)!.name, 'Renamed');
        expect(shell.currentInstance!.user!.watchedCategoryIds, [1]);
        expect(api.categoryNotificationLevelsUpdated, hasLength(1));
        expect(
          await shell.updateCategoryNotificationLevel(
            _site,
            1,
            CategoryNotificationLevel.normal,
          ),
          isTrue,
        );
        expect(api.categoryNotificationLevelsUpdated, hasLength(2));
      },
    );
  }

  for (final succeeds in [false, true]) {
    for (final returnsBeforeSettlement in [false, true]) {
      test(
        'read during pending write keeps settlement with success=$succeeds early=$returnsBeforeSettlement',
        () async {
          final api = _Api();
          final shell = await _loadShell(api);
          api.writeGate = Completer<void>();
          final writing = shell.updateCategoryNotificationLevel(
            _site,
            1,
            CategoryNotificationLevel.watching,
          );
          await pumpEventQueue();
          final held = api.holdRead('list');
          final reading = _read(shell, 'list');
          await api.readStarted.future;
          final stale = _category(
            name: 'Pending metadata',
            level: CategoryNotificationLevel.muted,
          );
          if (returnsBeforeSettlement) {
            held.complete([stale]);
            await reading;
            expect(
              shell.categoryFor(1, siteUrl: _site)!.notificationLevel,
              CategoryNotificationLevel.watching,
            );
          }
          if (!succeeds) api.categoryWriteFailure = StateError('Rejected');
          api.writeGate!.complete();
          expect(await writing, succeeds);
          if (!returnsBeforeSettlement) {
            held.complete([stale]);
            await reading;
          }
          expect(
            shell.categoryFor(1, siteUrl: _site)!.notificationLevel,
            succeeds
                ? CategoryNotificationLevel.watching
                : CategoryNotificationLevel.normal,
          );
          expect(
            shell.categoryFor(1, siteUrl: _site)!.name,
            'Pending metadata',
          );
          expect(
            shell.currentInstance!.user!.watchedCategoryIds,
            succeeds ? [1] : isEmpty,
          );
        },
      );
    }
  }

  test(
    'later fresh reads accept external levels independently per category',
    () async {
      final api = _Api();
      final shell = await _loadShell(api);
      final held = api.holdRead('list');
      final reading = _read(shell, 'list');
      await api.readStarted.future;
      await shell.updateCategoryNotificationLevel(
        _site,
        1,
        CategoryNotificationLevel.watching,
      );
      held.complete([
        _category(),
        _category(id: 2, level: CategoryNotificationLevel.tracking),
      ]);
      await reading;
      expect(
        shell.categoryFor(1, siteUrl: _site)!.notificationLevel,
        CategoryNotificationLevel.watching,
      );
      expect(
        shell.categoryFor(2, siteUrl: _site)!.notificationLevel,
        CategoryNotificationLevel.tracking,
      );
      api.response = [_category(level: CategoryNotificationLevel.muted)];
      await shell.loadCategories(_site, force: true);
      expect(
        shell.categoryFor(1, siteUrl: _site)!.notificationLevel,
        CategoryNotificationLevel.muted,
      );
    },
  );

  test(
    'coalesced category finds retain their original request authority',
    () async {
      final api = _Api();
      final shell = await _loadShell(api);
      final held = api.holdRead('find');
      final first = shell.loadTopic(41, 'first');
      await api.readStarted.future;
      final second = shell.loadTopic(42, 'second');
      await pumpEventQueue();
      expect(api.findRequests, 1);
      api.response = [_category(id: 10)];
      await shell.searchTopicCategoriesForEditor(siteUrl: _site, term: 'seed');
      expect(
        await shell.updateCategoryNotificationLevel(
          _site,
          10,
          CategoryNotificationLevel.watching,
        ),
        isTrue,
      );
      held.complete([_category(id: 10, name: 'Found metadata')]);
      await Future.wait([first, second]);
      expect(
        shell.categoryFor(10, siteUrl: _site)!.notificationLevel,
        CategoryNotificationLevel.watching,
      );
      expect(shell.categoryFor(10, siteUrl: _site)!.name, 'Found metadata');
    },
  );

  test(
    'opening a cached category keeps its accepted notification choice',
    () async {
      final api = _Api();
      final shell = await _loadShell(api);
      final cached = shell.categoryFor(1, siteUrl: _site)!;
      await shell.updateCategoryNotificationLevel(
        _site,
        1,
        CategoryNotificationLevel.watching,
      );
      shell.openCategory(cached, siteUrl: _site);
      expect(shell.currentContent!.categoryId, 1);
      expect(
        shell.categoryFor(1, siteUrl: _site)!.notificationLevel,
        CategoryNotificationLevel.watching,
      );
    },
  );

  test(
    'an evicted category retains accepted authority when an old read returns',
    () async {
      final api = _Api();
      final store = Store(maxEntries: 10);
      final shell = await _loadShell(api, store: store);
      final held = api.holdRead('list');
      final reading = _read(shell, 'list');
      await api.readStarted.future;
      await shell.updateCategoryNotificationLevel(
        _site,
        1,
        CategoryNotificationLevel.watching,
      );
      for (var id = 100; id < 120; id++) {
        store.put(_site, _category(id: id));
      }
      expect(shell.categoryFor(1, siteUrl: _site), isNull);
      held.complete([_category(name: 'Returned after eviction')]);
      await reading;
      expect(
        shell.categoryFor(1, siteUrl: _site)!.notificationLevel,
        CategoryNotificationLevel.watching,
      );
    },
  );

  test('retired search cannot publish to a replacement account', () async {
    final api = _Api();
    final shell = await _loadShell(api);
    final held = api.holdRead('filter');
    final reading = _read(shell, 'filter');
    await api.readStarted.future;
    final replacement = shell
        .instanceFor(_site)!
        .copyWith(user: const DiscourseUser(id: 8, username: 'replacement'));
    shell.lifecycle.invalidate(_site);
    shell.clearAccountSessionState(_site);
    shell.applyAccountSessionInstance(
      replacement,
      AccountSessionPhase.connecting,
    );
    api.response = [
      _category(name: 'Replacement', level: CategoryNotificationLevel.tracking),
    ];
    await shell.loadCategories(_site);
    held.complete([_category(name: 'Retired')]);
    expect(await reading, isEmpty);
    expect(shell.categoryFor(1, siteUrl: _site)!.name, 'Replacement');
    expect(
      shell.categoryFor(1, siteUrl: _site)!.notificationLevel,
      CategoryNotificationLevel.tracking,
    );
  });
}

final class _Api extends FakeDiscourseApi {
  _Api()
    : super(
        topics: {
          41: topicPayload(id: 41, title: 'First', categoryId: 10),
          42: topicPayload(id: 42, title: 'Second', categoryId: 10),
        },
      ) {
    accounts['api-key'] = _user;
  }

  List<TopicCategory> response = [_category(), _category(id: 2)];
  String? heldRoute;
  Completer<List<TopicCategory>>? held;
  Completer<void> readStarted = Completer<void>();
  int findRequests = 0;
  Completer<void>? writeGate;
  Object? categoryWriteFailure;

  Completer<List<TopicCategory>> holdRead(String route) {
    heldRoute = route;
    readStarted = Completer<void>();
    return held = Completer<List<TopicCategory>>();
  }

  Future<List<TopicCategory>> read(String route) {
    if (route != heldRoute) return Future.value(response);
    heldRoute = null;
    readStarted.complete();
    return held!.future;
  }

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => CategoryLoadResult(
    await read(page == 1 ? 'list' : 'page'),
    rootCategoryIds: [1, 2],
  );

  @override
  Future<List<TopicCategory>> searchCategories({
    required String siteUrl,
    required String term,
    required String apiKey,
    bool includeUncategorized = true,
    bool includeAncestors = false,
    String? clientId,
  }) => read(includeAncestors ? 'filter' : 'editor');

  @override
  Future<List<int>?> updateCategoryNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int categoryId,
    required CategoryNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    await writeGate?.future;
    if (categoryWriteFailure case final error?) throw error;
    return super.updateCategoryNotificationLevel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      categoryId: categoryId,
      notificationLevel: notificationLevel,
      clientId: clientId,
    );
  }

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) {
    findRequests++;
    return read('find');
  }
}
