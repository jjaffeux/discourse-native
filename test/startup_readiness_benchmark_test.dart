import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/destination_bookmarks_store.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/recent_destinations_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/data/topic_sidebar_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/destination_bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_library.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/site_basic_info.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Brightness, Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/site_appearance_fixtures.dart';

const _enabled = bool.fromEnvironment('STARTUP_BENCHMARK');
const _side = String.fromEnvironment(
  'STARTUP_BENCHMARK_SIDE',
  defaultValue: 'unset',
);
const _revision = String.fromEnvironment(
  'STARTUP_BENCHMARK_REVISION',
  defaultValue: 'unset',
);
const _warmups = int.fromEnvironment(
  'STARTUP_BENCHMARK_WARMUPS',
  defaultValue: 2,
);
const _recordedIterations = int.fromEnvironment(
  'STARTUP_BENCHMARK_ITERATIONS',
  defaultValue: 9,
);
const _onlyForums = int.fromEnvironment('STARTUP_BENCHMARK_FORUMS');
const _iterationOffset = int.fromEnvironment(
  'STARTUP_BENCHMARK_ITERATION_OFFSET',
);
const _account = 'user:reader';
const _feedPath = '/latest.json';
const _feedId = 'latest';
const _rowCount = 20;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'saved forum startup controller benchmark',
    () async {
      debugPrintSynchronously(
        jsonEncode({
          'kind': 'startup_controller_benchmark_metadata',
          'side': _side,
          'revision': _revision,
          'scope':
              'debug Flutter controller CPU and persisted preference read counts',
          'excludes':
              'process launch, native storage latency, network, widget layout and first frame',
          'physical_startup_claim': false,
          'timer_start': 'immediately before ShellController.load',
          'ready_end': 'synchronous shell ready listener',
          'feed_end': 'selected restored feed loaded with resident topic rows',
          'warmups_per_size': _warmups,
          'recorded_iterations_per_size': _recordedIterations,
          'workload_filter': _onlyForums,
          'iteration_offset': _iterationOffset,
          'custom_dual_palette_themes': 12,
          'tabs_per_forum': 3,
          'back_history_entries_per_tab': 8,
          'forward_history_entries_per_tab': 2,
        }),
      );
      expect(_warmups, greaterThanOrEqualTo(0));
      expect(_recordedIterations, greaterThan(0));
      expect(_onlyForums, isIn([0, 1, 10, 30]));
      for (final size in [1, 10, 30]) {
        if (_onlyForums != 0 && _onlyForums != size) continue;
        final fixture = await _Fixture.create(size);
        for (
          var iteration = -_warmups;
          iteration < _recordedIterations;
          iteration++
        ) {
          try {
            final sample = await _measure(fixture);
            debugPrintSynchronously(
              jsonEncode({
                'kind': 'startup_controller_sample',
                'side': _side,
                'revision': _revision,
                'forums': size,
                'phase': iteration < 0 ? 'warmup' : 'recorded',
                'iteration': iteration < 0
                    ? iteration + _warmups
                    : iteration + _iterationOffset,
                'stored_utf8_bytes': fixture.storedBytes,
                'theme_library_utf8_bytes': fixture.libraryBytes,
                'failures': 0,
                ...sample,
              }),
            );
          } catch (error) {
            debugPrintSynchronously(
              jsonEncode({
                'kind': 'startup_controller_sample_failure',
                'side': _side,
                'revision': _revision,
                'forums': size,
                'iteration': iteration,
                'failures': 1,
                'error': error.toString(),
              }),
            );
            rethrow;
          }
        }
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<Map<String, Object?>> _measure(_Fixture fixture) async {
  SharedPreferences.setMockInitialValues(fixture.preferences);
  final counted = _CountingPreferences(const _PreferenceStrings(), {
    for (final value in fixture.preferences.values.whereType<String>())
      value: utf8.encode(value).length,
  });
  final api = FakeDiscourseApi(
    feeds: {_feedPath: fixture.rows},
    basicInfos: {
      for (final instance in fixture.instances)
        instance.url: SiteBasicInfo(
          title: instance.title,
          description: instance.description,
        ),
    },
    totals: const NotificationTotals(),
  );
  final shell = ShellController(
    instanceStore: InstanceStore(),
    forumTabs: ForumTabStore(),
    recentDestinations: RecentDestinationsStore(),
    destinationBookmarks: DestinationBookmarksStore(),
    appSettingsStore: AppSettingsStore(),
    forumSettingsStore: ForumSettingsStore(persistence: counted),
    api: api,
    authenticator: FakeAuthenticator.signedIn(fixture.instances, site: api),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  final stopwatch = Stopwatch();
  final feedDone = Completer<void>();
  Map<String, Object?>? atReady;
  Map<String, Object?>? atFeed;
  void observe() {
    if (!shell.loaded) return;
    atReady ??= {
      'ready_us': stopwatch.elapsedMicroseconds,
      'preference_reads_at_ready': counted.snapshot(),
    };
    final feed = shell.currentFeed;
    if (atFeed == null && feed?.loaded == true && feed?.loading == false) {
      atFeed = {
        'selected_feed_usable_us': stopwatch.elapsedMicroseconds,
        'preference_reads_at_feed': counted.snapshot(),
      };
      feedDone.complete();
    }
  }

  shell.addListener(observe);
  shell.topicFeeds.addListener(observe);
  try {
    stopwatch.start();
    await shell.load().timeout(const Duration(seconds: 10));
    final loadCompleteUs = stopwatch.elapsedMicroseconds;
    observe();
    await feedDone.future.timeout(const Duration(seconds: 10));
    stopwatch.stop();

    expect(shell.loaded, isTrue);
    expect(shell.currentInstance?.url, fixture.selectedSite);
    expect(shell.instanceIndex, fixture.instances.length - 1);
    expect(shell.currentContent?.id, _feedId);
    expect(shell.currentFeedId, _feedId);
    expect(shell.currentFeed?.error, isNull);
    expect(shell.currentFeed?.loading, isFalse);
    expect(
      shell.currentFeed?.topicIds,
      fixture.rows.map((row) => row.id).toList(),
    );
    expect(shell.currentFeed?.rowCount, _rowCount);
    expect(api.feedPaths, [_feedPath]);
    expect(shell.currentInstance?.appearance, isNotNull);
    expect(api.appearancesRequested, isEmpty);
    expect(shell.forumSettings.shared.font, ForumFont.lora);
    expect(
      shell.forumSettings.themesFor(fixture.selectedSite).customThemes.length,
      12,
    );
    expect(
      shell.forumSettings.themesFor(fixture.selectedSite).customId,
      fixture.selectedTheme,
    );
    expect(
      shell.topicSidebar.collapsedFor(fixture.selectedSite),
      (fixture.instances.length - 1).isEven,
    );
    for (final instance in fixture.instances) {
      final workspace = shell.workspaceFor(instance.url);
      expect(workspace?.accountIdentity, _account);
      expect(workspace?.tabs.length, 3);
      expect(workspace?.tabs.first.backHistory.length, 8);
      expect(workspace?.tabs.first.forwardHistory.length, 2);
    }
    expect(
      shell.recentDestinations.topicsFor(fixture.selectedSite, _account).length,
      5,
    );
    expect(
      shell.destinationBookmarks
          .entriesFor(fixture.selectedSite, _account)
          .length,
      3,
    );
    expect(atReady, isNotNull);
    expect(atFeed, isNotNull);
    return {
      ...atReady!,
      'load_complete_us': loadCompleteUs,
      ...atFeed!,
      'selected_feed_rows': shell.currentFeed!.rowCount,
      'selected_site': fixture.selectedSite,
      'restored_workspaces': fixture.instances.length,
      'restored_tabs': fixture.instances.length * 3,
      'feed_requests': api.feedPaths.length,
    };
  } finally {
    stopwatch.stop();
    shell.removeListener(observe);
    shell.topicFeeds.removeListener(observe);
    await shell.flushForExit();
    shell.dispose();
    await shell.cooking.dispose();
    await pumpEventQueue();
  }
}

final class _Fixture {
  const _Fixture(this.instances, this.preferences, this.rows);

  final List<DiscourseInstance> instances;
  final Map<String, Object> preferences;
  final List<Topic> rows;
  String get selectedSite => instances.last.url;
  String get selectedTheme => 'custom-benchmark-${(instances.length - 1) % 12}';
  int get libraryBytes => utf8
      .encode(preferences[ForumSettingsStore.themeLibraryKey]! as String)
      .length;
  int get storedBytes => preferences.values.whereType<String>().fold(
    0,
    (total, value) => total + utf8.encode(value).length,
  );

  static Future<_Fixture> create(int size) async {
    SharedPreferences.setMockInitialValues({});
    final instances = [
      for (var index = 0; index < size; index++)
        DiscourseInstance(
          url: 'https://forum-$index.example',
          title: 'Community $index',
          description:
              'A saved community for technical discussions, announcements and support.',
          iconUrl:
              'https://forum-$index.example/uploads/default/original/1X/community.png',
          apiVersion: 4,
          user: const DiscourseUser(
            id: 7,
            username: 'reader',
            name: 'Saved Reader',
          ),
          notificationTotals: const NotificationTotals(),
          appearance: siteAppearance(alternateAccent: const Color(0xff99bbff)),
        ),
    ];
    final list = ContentRoute.topicList(TopicListMode.latest);
    ContentRoute topic(int id) => ContentRoute.topic(
      topicId: id,
      slug: 'saved-discussion-$id',
      title: 'Saved discussion $id',
      postNumber: id % 24 + 1,
    );
    final workspaces = [
      for (var index = 0; index < instances.length; index++)
        ForumWorkspace(
          siteUrl: instances[index].url,
          accountIdentity: _account,
          activeTabId: 'saved-$index-0',
          mainTabId: 'saved-$index-0',
          tabs: [
            for (var tab = 0; tab < 3; tab++)
              ForumTab(
                id: 'saved-$index-$tab',
                rootDestinationId: tab == 1 ? 'unread' : _feedId,
                contentStack: [
                  tab == 0
                      ? list
                      : ContentRoute.topicList(
                          tab == 1
                              ? TopicListMode.unread
                              : TopicListMode.topWeekly,
                        ),
                ],
                backHistory: [
                  for (var entry = 0; entry < 8; entry++)
                    ForumTabLocation(
                      rootDestinationId: _feedId,
                      contentStack: [
                        list,
                        topic(10000 + index * 100 + tab * 10 + entry),
                      ],
                    ),
                ],
                forwardHistory: [
                  for (var entry = 0; entry < 2; entry++)
                    ForumTabLocation(
                      rootDestinationId: _feedId,
                      contentStack: [
                        list,
                        topic(20000 + index * 100 + tab * 10 + entry),
                      ],
                    ),
                ],
                anchors: const {
                  _feedId: ForumTabAnchor(
                    kind: 'topic',
                    itemId: 1000,
                    offset: 12,
                  ),
                },
              ),
          ],
        ),
    ];
    await InstanceStore().save(instances);
    await ForumTabStore().save(workspaces, selectedSiteUrl: instances.last.url);
    final recent = RecentDestinationsStore();
    await recent.load();
    final bookmarks = DestinationBookmarksStore();
    await bookmarks.load();
    for (var index = 0; index < instances.length; index++) {
      final site = instances[index].url;
      for (var visit = 0; visit < 5; visit++) {
        recent.remember(site, _account, topic(30000 + index * 100 + visit));
      }
      for (final mode in [
        TopicListMode.latest,
        TopicListMode.unread,
        TopicListMode.topWeekly,
      ]) {
        await bookmarks.set(
          site,
          _account,
          DestinationBookmark.fromRoute(ContentRoute.topicList(mode))!,
          bookmarked: true,
        );
      }
    }
    await recent.save();
    final themes = [
      for (var index = 0; index < 12; index++) _customTheme(index),
    ];
    final library = ForumThemeLibrary(
      themes: themes,
      forums: {
        for (var index = 0; index < instances.length; index++)
          instances[index].url: ForumThemePreferences(
            source: ForumThemeSource.custom,
            customId: themes[index % themes.length].id,
            customThemes: themes,
          ),
      },
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      ForumSettingsStore.themeLibraryKey,
      jsonEncode(library.toJson()),
    );
    await preferences.setString(
      ForumSettingsStore.appearanceKey,
      jsonEncode(
        const SharedAppearance(
          font: ForumFont.lora,
          interfaceFont: ForumFont.openSans,
        ).toJson(),
      ),
    );
    await preferences.setString(
      AppSettingsStore.themeModeKey,
      AppThemeMode.system.name,
    );
    for (var index = 0; index < instances.length; index++) {
      final site = instances[index].url;
      await preferences.setString(
        ForumSettingsStore.themeModeKey(site),
        AppThemeMode.values[index % AppThemeMode.values.length].name,
      );
      await preferences.setBool(
        SharedPreferencesTopicSidebarPersistence.keys.of(site),
        index.isEven,
      );
    }
    final saved = {
      for (final key in preferences.getKeys()) key: preferences.get(key)!,
    };
    return _Fixture(instances, saved, [
      for (var row = 0; row < _rowCount; row++)
        Topic(
          id: 1000 + row,
          title: 'Selected forum discussion $row',
          slug: 'discussion-$row',
          postsCount: row + 2,
          views: 70 + row,
          likeCount: row % 7,
        ),
    ]);
  }
}

ForumTheme _customTheme(int index) {
  ForumTheme palette(Brightness brightness) => ForumTheme(
    id: 'custom-benchmark-$index',
    name: 'Personal palette $index',
    brightness: brightness,
    primary: brightness == Brightness.light
        ? const Color(0xff202020)
        : const Color(0xffeeeeee),
    secondary: brightness == Brightness.light
        ? const Color(0xfffafafa)
        : const Color(0xff181a1f),
    tertiary: Color(0xff3366aa + index * 71),
    quaternary: const Color(0xffdd7711),
    danger: const Color(0xffcc2233),
    success: const Color(0xff228844),
    love: const Color(0xffee4477),
    darkerSidebars: index.isEven,
    tint: index / 24,
  );
  final light = palette(Brightness.light);
  return ForumTheme.fromJson({
    ...light.toJson(),
    'alternate': palette(Brightness.dark).toJson(),
  }, id: light.id);
}

final class _CountingPreferences
    implements ScalarPreferencePersistence<String> {
  _CountingPreferences(this.delegate, this._utf8Lengths);

  final ScalarPreferencePersistence<String> delegate;
  final _reads = <String, int>{};
  final _bytes = <String, int>{};
  final Map<String, int> _utf8Lengths;
  int _writes = 0;

  @override
  Future<String?> read(String key) async {
    final value = await delegate.read(key);
    _reads.update(key, (count) => count + 1, ifAbsent: () => 1);
    final bytes = value == null
        ? 0
        : _utf8Lengths.putIfAbsent(value, () => utf8.encode(value).length);
    _bytes.update(key, (count) => count + bytes, ifAbsent: () => bytes);
    return value;
  }

  @override
  Future<bool> write(String key, String value) {
    _writes++;
    return delegate.write(key, value);
  }

  Map<String, Object> snapshot() => {
    'library_reads': _reads[ForumSettingsStore.themeLibraryKey] ?? 0,
    'library_utf8_bytes': _bytes[ForumSettingsStore.themeLibraryKey] ?? 0,
    'all_counted_reads': _reads.values.fold<int>(
      0,
      (total, count) => total + count,
    ),
    'counted_writes': _writes,
    'reads_by_key': {..._reads},
  };
}

final class _PreferenceStrings
    extends SharedPreferencesScalarPreferencePersistence<String> {
  const _PreferenceStrings();

  @override
  String? readValue(SharedPreferences preferences, String key) =>
      preferences.getString(key);

  @override
  Future<bool> writeValue(
    SharedPreferences preferences,
    String key,
    String value,
  ) => preferences.setString(key, value);
}
