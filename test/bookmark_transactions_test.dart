import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/bookmark_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _bookmark = Bookmark(
  id: 73,
  bookmarkableId: 12,
  bookmarkableType: 'Post',
);
const _post = Post(
  id: 12,
  postNumber: 2,
  username: 'sam',
  cooked: '<p>current body</p>',
);

final class _TopicData implements BookmarkTopicData {
  final reads = <Completer<BookmarkTopicSnapshot?>>[];
  int holds = 0;
  void Function()? onPostWriting;
  @override
  bool postWriting(int postId) {
    onPostWriting?.call();
    return holds > 0;
  }

  @override
  void Function() holdPostWrite(int postId, {bool notifyOnRelease = true}) {
    holds++;
    var released = false;
    return () {
      if (!released) {
        released = true;
        holds--;
      }
    };
  }

  @override
  Future<BookmarkTopicSnapshot?> readBookmarkMetadata(
    int topicId,
    String slug,
  ) {
    final response = Completer<BookmarkTopicSnapshot?>();
    reads.add(response);
    return response.future;
  }
}

final class _FeedApi extends FakeDiscourseApi {
  final response = Completer<BookmarkPayload>();
  int requests = 0;
  @override
  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) {
    requests++;
    return response.future;
  }
}

const _pluginTarget = BookmarkTargetType(
  owner: PluginId('test'),
  name: 'message',
  wireName: 'TestMessage',
  refreshLabel: 'message',
);
const _pluginBookmark = Bookmark(
  id: 91,
  bookmarkableId: 12,
  bookmarkableType: 'TestMessage',
);

final class _Strategy implements PluginBookmarkTargetStrategy {
  _Strategy({this.onReconcile});
  final void Function()? onReconcile;
  final puts = <(String, int, Bookmark)>[];
  final removes = <(String, int)>[];
  final repairs = <(String, int)>[];
  @override
  BookmarkTargetType get pluginBookmarkTarget => _pluginTarget;
  @override
  void putPluginBookmark(String siteUrl, int targetId, Bookmark bookmark) =>
      puts.add((siteUrl, targetId, bookmark));
  @override
  void removePluginBookmark(String siteUrl, int targetId) =>
      removes.add((siteUrl, targetId));
  @override
  void reconcilePluginBookmark(String siteUrl, int targetId) {
    repairs.add((siteUrl, targetId));
    onReconcile?.call();
  }
}

final class _PendingWriteApi extends FakeDiscourseApi {
  final ready = Completer<void>();
  @override
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) async {
    await ready.future;
    return super.createBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      targetType: targetType,
      targetId: targetId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
    );
  }

  @override
  Future<void> updateBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    String? name,
    DateTime? reminderAt,
    DateTime? originalReminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
    String? clientId,
  }) async {
    await ready.future;
    return super.updateBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      bookmarkId: bookmarkId,
      name: name,
      reminderAt: reminderAt,
      originalReminderAt: originalReminderAt,
      autoDeletePreference: autoDeletePreference,
    );
  }

  @override
  Future<bool?> deleteBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    required BookmarkTargetType targetType,
    String? clientId,
  }) async {
    await ready.future;
    return super.deleteBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      bookmarkId: bookmarkId,
      targetType: targetType,
    );
  }
}

final class _Fixture {
  _Fixture({
    this.onMenu,
    this.onChanged,
    FakeDiscourseApi? api,
    Iterable<PluginBookmarkTargetStrategy> Function()? strategies,
  }) : api = api ?? FakeDiscourseApi() {
    bookmarks = BookmarkTransactions(
      api: this.api,
      store: store,
      credentials: FakeAuthenticator()..keys[_site] = 'key',
      lifecycle: lifecycle,
      instanceAt: (_) => instance(
        'meta.example',
      ).copyWith(user: const DiscourseUser(username: 'reader')),
      siteContextFor: (_) =>
          const BookmarkSiteContext(suggestWeekendsInDatePickers: true),
      pluginStrategies: strategies ?? () => const [],
      topicData: (_, _) => data,
      checklistWriting: (_, _) => false,
      topicSlug: (_, _) => 'topic',
      changes: changes,
      changed: () {
        onChanged?.call();
        changes.notifyListeners();
      },
      refreshMenu: (_) async {
        menu++;
        onMenu?.call();
      },
      refreshList: (_) async {
        list++;
      },
    );
    store.put(_site, _post);
    store.put(
      _site,
      const TopicDetail(id: 7, title: 'Topic', stream: [12, 13], postsCount: 2),
    );
    store.put(_site, const Topic(id: 7, title: 'Topic', slug: 'topic'));
    addTearDown(() {
      bookmarks.dispose();
      changes.dispose();
      for (final read in data.reads) {
        if (!read.isCompleted) read.complete(null);
      }
    });
  }
  final FakeDiscourseApi api;
  final store = Store();
  final lifecycle = SiteLifecycle();
  final changes = ChangeNotifier();
  final data = _TopicData();
  final void Function()? onMenu;
  final void Function()? onChanged;
  int menu = 0;
  int list = 0;
  late final BookmarkTransactions bookmarks;
  BookmarkAccountSession get account => bookmarks.forSite(_site);
  Future<BookmarkWriteResult> create() => account.createBookmark(
    topicId: 7,
    targetType: BookmarkTargetType.post,
    targetId: 12,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bookmark updates forward the stored reminder independently of the draft',
    () async {
      final f = _Fixture();
      final original = DateTime.utc(2000, 1, 1);
      final bookmark = _bookmark.copyWith(
        reminderAt: original,
        autoDeletePreference: BookmarkAutoDeletePreference.never,
      );
      for (final reminder in [original, null, DateTime.utc(2030, 1, 1)]) {
        final result = await f.account.updateBookmark(
          topicId: 7,
          bookmark: bookmark,
          name: 'Updated note',
          reminderAt: reminder,
          autoDeletePreference: BookmarkAutoDeletePreference.onOwnerReply,
        );
        expect(result.saved, isTrue);
        expect(f.api.updatedBookmarkOriginalReminders.last, original);
        expect(f.api.updatedBookmarks.last.reminderAt, reminder);
      }
      expect(f.api.updatedBookmarks, hasLength(3));
    },
  );

  test(
    'a forced bookmark replay cannot dispatch for a replacement account',
    () async {
      final api = _FeedApi();
      final lifecycle = SiteLifecycle();
      final activity = AccountActivityController(
        api: api,
        credentials: FakeAuthenticator()..keys[_site] = 'key',
        lifecycle: lifecycle,
      );
      addTearDown(activity.dispose);
      final forum = instance(
        'meta.example',
      ).copyWith(user: const DiscourseUser(username: 'reader'));
      final first = activity.loadBookmarks(forum);
      await pumpEventQueue();
      expect(api.requests, 1);
      final forced = activity.loadBookmarks(forum, force: true);
      var retired = false;
      activity.bookmarksListenable.addListener(() {
        if (retired || !activity.bookmarksFor(_site).loaded) return;
        retired = true;
        scheduleMicrotask(() => lifecycle.invalidate(_site));
      });
      api.response.complete((
        reminders: const <DiscourseNotification>[],
        bookmarks: const <Bookmark>[],
      ));
      await Future.wait([first, forced]);
      expect(retired, isTrue);
      expect(api.requests, 1);
    },
  );

  test(
    'metadata repair retains a newer body and rejects an older bookmark read',
    () async {
      final f = _Fixture();
      final account = f.account;
      final first = account.refreshBookmarks(7, 'topic');
      final second = account.refreshBookmarks(7, 'topic');
      f.store.put(_site, _post.copyWith(cooked: '<p>new body</p>'));
      f.data.reads[1].complete(
        const BookmarkTopicSnapshot(
          bookmarks: [_bookmark],
          posts: {12: _bookmark},
        ),
      );
      await second;
      f.data.reads[0].complete(
        const BookmarkTopicSnapshot(bookmarks: [], posts: {12: null}),
      );
      await first;
      expect(f.store.read<Post>(_site, 12)?.cooked, '<p>new body</p>');
      expect(f.store.read<Post>(_site, 12)?.bookmark, _bookmark);
      expect(f.store.read<TopicDetail>(_site, 7)?.bookmarks, [_bookmark]);
      expect(f.store.read<Topic>(_site, 7)?.bookmarked, isTrue);
    },
  );

  test(
    'a newer revision accepted during repair owns the remaining projections',
    () async {
      final f = _Fixture();
      final account = f.account;
      var replaced = false;
      f.store.ref<Post>(_site, 12).addListener(() {
        if (replaced) return;
        replaced = true;
        account.acceptBookmark(
          7,
          _bookmark.copyWith(name: 'newer'),
          isPost: true,
        );
      });
      final reading = account.refreshBookmarks(7, 'topic');
      f.data.reads.single.complete(
        const BookmarkTopicSnapshot(
          bookmarks: [_bookmark],
          posts: {12: _bookmark},
        ),
      );
      await reading;
      expect(f.store.read<Post>(_site, 12)?.bookmark?.name, 'newer');
      expect(
        f.store.read<TopicDetail>(_site, 7)?.bookmarks.single.name,
        'newer',
      );
    },
  );

  test(
    'retirement during the first repair publication protects successor records',
    () async {
      final f = _Fixture();
      f.store.put(
        _site,
        const Post(
          id: 13,
          postNumber: 3,
          username: 'sam',
          cooked: '<p>successor</p>',
        ),
      );
      final account = f.account;
      var replaced = false;
      f.store.ref<Post>(_site, 12).addListener(() {
        if (replaced) return;
        replaced = true;
        f.lifecycle.invalidate(_site);
        f.store.put(
          _site,
          const TopicDetail(
            id: 7,
            title: 'Successor',
            stream: [13],
            postsCount: 1,
          ),
        );
      });
      final reading = account.refreshBookmarks(7, 'topic');
      f.data.reads.single.complete(
        const BookmarkTopicSnapshot(
          bookmarks: [_bookmark],
          posts: {12: _bookmark, 13: _bookmark},
        ),
      );
      await reading;
      expect(f.store.read<Post>(_site, 13)?.bookmark, isNull);
      expect(f.store.read<TopicDetail>(_site, 7)?.title, 'Successor');
      expect(f.store.read<TopicDetail>(_site, 7)?.bookmarks, isEmpty);
      expect(account.isCurrent, isFalse);
    },
  );

  test(
    'account replacement during menu refresh suppresses the loaded-list refresh',
    () async {
      late final _Fixture f;
      f = _Fixture(onMenu: () => f.lifecycle.invalidate(_site));
      await f.create();
      expect(f.menu, 1);
      expect(f.list, 0);
    },
  );

  test(
    'retirement during admission sends no write and releases its original hold',
    () async {
      late final _Fixture f;
      f = _Fixture(onChanged: () => f.lifecycle.invalidate(_site));
      final result = await f.create();
      expect(result.reconciled, isTrue);
      expect(f.api.createdBookmarks, isEmpty);
      expect(f.data.holds, 0);
    },
  );

  test(
    'retirement during the post busy probe still releases the admitted hold',
    () async {
      final f = _Fixture();
      f.data.onPostWriting = () => f.lifecycle.invalidate(_site);
      final result = await f.create();
      expect(result.reconciled, isTrue);
      expect(f.api.createdBookmarks, isEmpty);
      expect(f.data.holds, 0);
    },
  );

  for (final operation in ['create', 'update', 'delete']) {
    test(
      'pending plugin $operation retains its target and busy hold',
      () async {
        final original = _Strategy();
        final replacement = _Strategy();
        var strategies = <PluginBookmarkTargetStrategy>[original];
        final api = _PendingWriteApi();
        final f = _Fixture(api: api, strategies: () => strategies);
        final host = f.bookmarks.pluginTarget(_pluginTarget);
        final pending = switch (operation) {
          'create' => host.createBookmark(siteUrl: _site, targetId: 12),
          'update' => host.updateBookmark(
            siteUrl: _site,
            bookmark: _pluginBookmark,
            name: 'changed',
            autoDeletePreference: BookmarkAutoDeletePreference.never,
          ),
          _ => host.deleteBookmark(siteUrl: _site, bookmark: _pluginBookmark),
        };
        await pumpEventQueue();
        expect(
          host.bookmarkWriteInFlight(siteUrl: _site, targetId: 12),
          isTrue,
        );
        final duplicate = await host.createBookmark(
          siteUrl: _site,
          targetId: 12,
        );
        expect(duplicate.saved, isFalse);
        expect(
          duplicate.message,
          'Another action on this bookmark is still finishing.',
        );
        strategies = [replacement];
        api.ready.complete();
        final result = await pending;
        expect(result.saved, isTrue);
        expect(original.repairs, [(_site, 12)]);
        expect(
          original.removes,
          operation == 'delete' ? [(_site, 12)] : isEmpty,
        );
        expect(original.puts, operation == 'delete' ? isEmpty : hasLength(1));
        if (original.puts.isNotEmpty) {
          expect(original.puts.single.$1, _site);
          expect(original.puts.single.$2, 12);
          expect(original.puts.single.$3.bookmarkableType, 'TestMessage');
        }
        expect(replacement.puts, isEmpty);
        expect(replacement.removes, isEmpty);
        expect(replacement.repairs, isEmpty);
        expect(f.data.reads, isEmpty);
        expect(
          host.bookmarkWriteInFlight(siteUrl: _site, targetId: 12),
          isFalse,
        );
      },
    );
  }

  test('plugin repair retirement suppresses menu and list refresh', () async {
    late final _Fixture f;
    final strategy = _Strategy(
      onReconcile: () => f.lifecycle.invalidate(_site),
    );
    f = _Fixture(strategies: () => [strategy]);
    final result = await f.bookmarks
        .pluginTarget(_pluginTarget)
        .createBookmark(siteUrl: _site, targetId: 12);
    expect(result.saved, isTrue);
    expect(strategy.repairs, [(_site, 12)]);
    expect(f.menu, 0);
    expect(f.list, 0);
  });

  for (final delete in [false, true]) {
    test(
      'retirement during post ${delete ? 'delete' : 'update'} releases its hold',
      () async {
        late final _Fixture f;
        f = _Fixture(onChanged: () => f.lifecycle.invalidate(_site));
        final result = await (delete
            ? f.account.deleteBookmark(topicId: 7, bookmark: _bookmark)
            : f.account.updateBookmark(
                topicId: 7,
                bookmark: _bookmark,
                autoDeletePreference: BookmarkAutoDeletePreference.never,
              ));
        expect(result.reconciled, isTrue);
        expect(f.api.updatedBookmarks, isEmpty);
        expect(f.api.deletedBookmarks, isEmpty);
        expect(f.data.holds, 0);
      },
    );
  }

  test(
    'an uncertain create schedules a read without issuing another create',
    () async {
      final f = _Fixture(
        api: FakeDiscourseApi(
          writeFailure: const WriteException(WriteFailure.unreachable),
        ),
      );
      final result = await f.create();
      expect(result.reconciled, isTrue);
      expect(f.data.reads, hasLength(1));
      expect(f.menu, 1);
      expect(f.list, 1);
      expect(f.store.read<Post>(_site, 12)?.bookmark, isNull);
    },
  );
}
