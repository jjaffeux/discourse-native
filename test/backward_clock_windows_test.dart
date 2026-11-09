import 'dart:io';
import 'dart:typed_data';

import 'package:discourse_native/src/data/byte_cache.dart';
import 'package:discourse_native/src/data/byte_cache_store.dart';
import 'package:discourse_native/src/data/custom_sidebar_sections.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/foundation/elapsed_time.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_data.dart';
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:discourse_native/src/shell/composer/composer_identity_directory.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_prefetch_controller.dart';
import 'package:discourse_native/src/shell/update_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'plugins/gamification/gamification_fixture.dart';
import 'support/alert_fixtures.dart';
import 'support/fakes.dart';

const _site = 'https://forum.example';
const _reader = DiscourseUser(id: 7, username: 'reader');
const _channel = ChatChannel(
  id: 42,
  title: 'Room',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
);

final class _Clock {
  DateTime now = DateTime.utc(2026, 11, 9, 12);

  DateTime call() => now;
}

/// One window, already open at the clock's first reading. [open] answers a
/// probe that reports whether the gate has reopened or the entry has expired.
final class _Window {
  const _Window(this.site, this.open);

  final String site;
  final Future<Future<bool> Function()> Function(_Clock clock) open;
}

/// Whether [action] reached past the gate, seen as growth in [count].
Future<bool> _passes(
  Future<void> Function() action,
  int Function() count,
) async {
  final before = count();
  await action();
  await pumpEventQueue();
  return count() > before;
}

ChatController _chat(FakeDiscourseApi api, _Clock clock) {
  final chat = ChatController(
    api: api,
    requests: FakePluginRequestHost(
      credentials: FakeApiCredentialReader()..keys[_site] = 'key',
    ),
    store: Store(),
    currentUserFor: (_) => _reader,
    minimumWindowRefreshInterval: const Duration(minutes: 1),
    clock: clock.call,
  );
  addTearDown(chat.dispose);
  return chat;
}

final class _FailingSidebarApi extends FakeDiscourseApi {
  int reads = 0;

  @override
  Future<List<SidebarSection>> customSidebarSections({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    reads++;
    throw StateError('offline');
  }
}

final class _Bytes extends ByteCache<Uint8List> {
  _Bytes({required super.client, super.clock});

  @override
  Uint8List? decode(http.Response response) => response.bodyBytes;
}

final _windows = <_Window>[
  _Window('the updater recheck', (clock) async {
    final opened = clock.now;
    final lastChecked = DateTime.now();
    return () async {
      // The updater reads the real clock, so a saved check moved ahead of it
      // is the same state as the clock having moved behind the saved check.
      final updater = FakeUpdater(isSupported: true);
      final controller = UpdateController(
        updater: updater,
        store: FakeUpdateStore(
          lastChecked: lastChecked.add(opened.difference(clock.now)),
        ),
      );
      addTearDown(controller.dispose);
      await controller.load();
      return updater.checkCount > 0;
    };
  }),
  _Window('the chat window refresh throttle', (clock) async {
    final api = FakeDiscourseApi(
      chatChannelsById: const {42: _channel},
      chatMessagesByKey: {
        FakeDiscourseApi.chatMessagesKey(42): const (
          messages: <ChatMessage>[],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
      },
    );
    final chat = _chat(api, clock);
    await chat.openChannel(_site, 42);
    return () => _passes(
      () => chat.openChannel(_site, 42),
      () => api.chatMessagesRequested.length,
    );
  }),
  _Window('the chat resync after an absence', (clock) async {
    final api = FakeDiscourseApi(
      chatChannelsBySite: const {
        _site: ChatChannels(public: [_channel]),
      },
    );
    final chat = _chat(api, clock);
    await chat.loadChannels(_site);
    chat.setForeground(false);
    return () async {
      final resynced = await _passes(
        () async => chat.setForeground(true),
        () => api.chatChannelsRequested.length,
      );
      chat.setForeground(false);
      return resynced;
    };
  }),
  _Window('the account totals cooldown', (clock) async {
    final account = instance('forum.example').copyWith(user: _reader);
    final api = FakeDiscourseApi(
      totals: const NotificationTotals(unreadNotifications: 1),
    );
    final controller = AccountActivityController(
      api: api,
      credentials: FakeApiCredentialReader()..keys[account.url] = 'key',
      lifecycle: SiteLifecycle(),
      minimumRefreshInterval: const Duration(minutes: 5),
      clock: clock.call,
    );
    addTearDown(controller.dispose);
    await controller.refresh(account);
    return () =>
        _passes(() => controller.refresh(account), () => api.totalsCalls);
  }),
  _Window('the custom sidebar retry cooldown', (clock) async {
    const account = DiscourseInstance(
      url: _site,
      title: 'Forum',
      user: _reader,
    );
    final api = _FailingSidebarApi();
    final owner = CustomSidebarSections(
      api: api,
      credentials: FakeApiCredentialReader()..keys[_site] = 'key',
      lifecycle: SiteLifecycle(),
      instanceFor: (_) => account,
      selectedSite: () => _site,
      onChanged: () {},
      clock: clock.call,
    );
    addTearDown(owner.dispose);
    await owner.ensure(_site);
    return () => _passes(() => owner.ensure(_site), () => api.reads);
  }),
  _Window('a prefetched topic', (clock) async {
    final session = Object();
    final controller = TopicPrefetchController(clock: clock.call);
    addTearDown(controller.clear);
    var loads = 0;
    Future<void> hover() async => controller.hover(
      (siteUrl: _site, session: session, topicId: 1, postNumber: null),
      isCurrent: () => true,
      intent: TopicPrefetchIntent.trajectory,
      load: (_) async {
        loads++;
        return PrefetchedTopic(topicPayload(id: 1), 0, 0, 0, 0);
      },
    );
    await hover();
    await pumpEventQueue();
    return () => _passes(hover, () => loads);
  }),
  _Window('a recent hashtag answer', (clock) async {
    final api = FakeDiscourseApi();
    final directory = ComposerIdentityDirectory(
      credentials: FakeApiCredentialReader()..keys[_site] = 'key',
      lifecycle: SiteLifecycle(),
      search: api,
      lookups: api,
      isConnected: (_) => true,
      emoji: (
        enabled: (_) => false,
        ensureCatalog: (_) async => null,
        ensureSearchAliases: (_) async => null,
        search: (_, _, {limit = 0}) => const [],
        urlFor: (_, name) => name,
        ensurePreferences: (_) async {},
        skinTone: (_) => EmojiSkinTone.neutral,
      ),
      pluginHashtagPresentation: (_) => null,
      pluginHashtagTypes: () => const [],
      onChanged: (_, _) {},
      clock: clock.call,
    );
    addTearDown(directory.dispose);
    Future<void> search() =>
        directory.searchHashtags(siteUrl: _site, term: 'sail');
    await search();
    return () => _passes(search, () => api.hashtagSearchesRequested.length);
  }),
  _Window('the composer draft max wait', (clock) async {
    var saves = 0;
    final composer = ComposerController(
      const ReplyComposerTarget(
        privateMessageTopic: false,
        siteUrl: _site,
        topicId: 7,
        slug: 'a-topic',
        topicTitle: 'A topic',
      ),
      now: clock.call,
      onSaveDraft: (_) async {
        saves++;
        return 1;
      },
    );
    addTearDown(composer.dispose);
    composer.text.text = 'first';
    await composer.flushDraft();
    var typed = 0;
    return () => _passes(() async {
      composer.text.text = 'typed ${++typed}';
    }, () => saves);
  }),
  _Window('the topic tracking resync after an absence', (clock) async {
    final account = instance('forum.example').copyWith(user: _reader);
    final api = FakeDiscourseApi(user: _reader);
    final shell = ShellController(
      instanceStore: FakeInstanceStore([account]),
      api: api,
      authenticator: FakeAuthenticator()..keys[account.url] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
      clock: clock.call,
    );
    addTearDown(shell.dispose);
    await shell.load();
    await pumpEventQueue();
    shell.setForeground(false);
    return () async {
      final resynced = await _passes(
        () async => shell.setForeground(true),
        () => api.topicTrackingRequests.length,
      );
      shell.setForeground(false);
      return resynced;
    };
  }),
  _Window('a failed image retry cooldown', (clock) async {
    const url = 'https://cdn.example/image.png';
    var requests = 0;
    final cache = _Bytes(
      client: MockClient((_) async {
        requests++;
        return http.Response('', 503);
      }),
      clock: clock.call,
    );
    await cache.load(url);
    return () => _passes(() => cache.load(url), () => requests);
  }),
  _Window('a cached file last-used record', (clock) async {
    const url = 'https://cdn.example/image.png';
    final directory = await Directory.systemTemp.createTemp(
      'discourse-native-backward-clock-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileByteCacheStore(directory, clock: clock.call);
    await store.write(
      url,
      Uint8List.fromList([1]),
      expiresAt: clock.now.add(const Duration(days: 30)),
    );
    final file = await directory
        .list()
        .where((entry) => entry.path.endsWith('.bin'))
        .cast<File>()
        .single;
    final recorded = clock.now;
    await file.setLastModified(recorded);
    bool touched() => !file.lastModifiedSync().isAtSameMomentAs(recorded);
    return () async {
      await store.read(url);
      // The record is written after the read has answered.
      final budget = clock.now.isBefore(recorded)
          ? const Duration(seconds: 5)
          : const Duration(milliseconds: 50);
      final waited = Stopwatch()..start();
      while (!touched() && waited.elapsed < budget) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return touched();
    };
  }),
  _Window('a cached leaderboard', (clock) async {
    final fixture = GamificationFixture(clock: clock.call);
    addTearDown(fixture.dispose);
    // The controller retains a snapshot when its last reader lets go.
    Future<void> visit() async {
      final handle = fixture.controller.acquire(
        gameSite,
        const GamificationQuery(),
      );
      await pumpEventQueue();
      handle.release();
    }

    await visit();
    return () => _passes(visit, () => fixture.transport.reads.length);
  }),
  _Window('the silenced alert marker', (clock) async {
    final alert = PrometheusAlert.decode(
      alertJson(status: 'firing')
        ..['last_suppressed_at'] = clock.now.toIso8601String(),
    )!;
    return () async => !alert.wasRecentlySilenced(clock.now);
  }),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('elapsedSince', () {
    final now = DateTime.utc(2026, 11, 9, 12);

    test('is the plain difference while the clock moves forward', () {
      expect(elapsedSince(now, now: now), Duration.zero);
      expect(
        elapsedSince(now.subtract(const Duration(minutes: 3)), now: now),
        const Duration(minutes: 3),
      );
    });

    test('is longer than any window once the clock has moved behind it', () {
      final age = elapsedSince(
        now.add(const Duration(microseconds: 1)),
        now: now,
      );
      expect(age, greaterThan(const Duration(days: 36500000)));
    });
  });

  group('a wall clock moved backward', () {
    for (final window in _windows) {
      test('reopens ${window.site}', () async {
        final clock = _Clock();
        final reopened = await window.open(clock);

        expect(await reopened(), isFalse, reason: 'still inside its window');

        clock.now = clock.now.subtract(const Duration(hours: 1));

        expect(await reopened(), isTrue, reason: 'its start now lies ahead');
      });
    }
  });
}
