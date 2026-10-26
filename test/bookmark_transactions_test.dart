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

final class _UnconfirmedDeleteApi extends FakeDiscourseApi {
  @override
  Future<bool?> deleteBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    required BookmarkTargetType targetType,
    String? clientId,
  }) async {
    deletedBookmarks.add(bookmarkId);
    return null;
  }
}

final class _PendingWriteApi extends FakeDiscourseApi {
  _PendingWriteApi({super.writeFailure});
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
      credentials: credentials,
      lifecycle: lifecycle,
      instanceAt: (_) => instance('meta.example', user: user),
      siteContextFor: (_) =>
          const BookmarkSiteContext(suggestWeekendsInDatePickers: true),
      pluginStrategies: strategies ?? () => const [],
      topicData: (_, _) => readerLoaded ? data : null,
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
  final credentials = FakeAuthenticator()..keys[_site] = 'key';
  final void Function()? onMenu;
  final void Function()? onChanged;
  DiscourseUser? user = const DiscourseUser(username: 'reader');
  bool readerLoaded = true;
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

  test(
    'reads dispatched before a bookmark write keep it; later reads own it',
    () {
      final f = _Fixture();
      final account = f.account;
      final dispatched = account.revision(7);
      final dispatchedEpoch = account.epoch;
      account.acceptBookmark(7, _bookmark, isPost: true);
      const readDetail = TopicDetail(
        id: 7,
        title: 'Read',
        stream: [12, 13],
        postsCount: 2,
      );
      const readRow = Topic(id: 7, title: 'Read', slug: 'topic');
      final readPost = _post.copyWith(cooked: '<p>read body</p>');

      final stalePost = account.postFromRead(7, dispatched, readPost);
      expect(stalePost.cooked, '<p>read body</p>');
      expect(stalePost.bookmark, _bookmark);
      final staleDetail = account.detailFromRead(dispatched, readDetail);
      expect(staleDetail.title, 'Read');
      expect(staleDetail.bookmarks, [_bookmark]);
      final staleRow = account.prepareRow(readRow, dispatchedEpoch);
      expect(staleRow.title, 'Read');
      expect(staleRow.bookmarked, isTrue);

      final fresh = account.revision(7);
      expect(account.postFromRead(7, fresh, readPost).bookmark, isNull);
      expect(account.detailFromRead(fresh, readDetail).bookmarks, isEmpty);
      expect(account.prepareRow(readRow, account.epoch).bookmarked, isFalse);
      expect(account.prepareRow(readRow, null).bookmarked, isFalse);
    },
  );

  test(
    'an unreachable plugin write retired in flight repairs nothing',
    () async {
      final strategy = _Strategy();
      final api = _PendingWriteApi(
        writeFailure: const WriteException(WriteFailure.unreachable),
      );
      final f = _Fixture(api: api, strategies: () => [strategy]);
      final pending = f.bookmarks
          .pluginTarget(_pluginTarget)
          .createBookmark(siteUrl: _site, targetId: 12);
      await pumpEventQueue();
      f.lifecycle.invalidate(_site);
      api.ready.complete();
      final result = await pending;
      expect(result.reconciled, isTrue);
      expect(strategy.repairs, isEmpty);
      expect(strategy.puts, isEmpty);
      expect(f.menu, 0);
      expect(f.list, 0);
    },
  );

  test('a saved create projects onto the post, topic and list row', () async {
    final f = _Fixture();
    final result = await f.create();
    expect(result.saved, isTrue);
    final saved = result.bookmark!;
    expect(saved.bookmarkableId, 12);
    expect(f.store.read<Post>(_site, 12)?.bookmark, saved);
    expect(f.store.read<TopicDetail>(_site, 7)?.bookmarks, [saved]);
    expect(f.store.read<Topic>(_site, 7)?.bookmarked, isTrue);
  });

  test(
    'deleting a post bookmark keeps the row bookmarked when the forum says so',
    () async {
      final f = _Fixture();
      f.account.acceptBookmark(7, _bookmark, isPost: true);
      final dispatchedEpoch = f.account.epoch;
      final result = await f.account.deleteBookmark(
        topicId: 7,
        bookmark: _bookmark,
      );
      expect(result.saved, isTrue);
      expect(f.api.deletedBookmarks, [73]);
      expect(f.store.read<Post>(_site, 12)?.bookmark, isNull);
      expect(f.store.read<TopicDetail>(_site, 7)?.bookmarks, isEmpty);
      expect(f.store.read<Topic>(_site, 7)?.bookmarked, isTrue);
      const staleRow = Topic(id: 7, title: 'Topic', slug: 'topic');
      expect(
        f.account.prepareRow(staleRow, dispatchedEpoch).bookmarked,
        isTrue,
      );
    },
  );

  test(
    'a create without a choice uses the reader\'s auto-delete preference',
    () async {
      final f = _Fixture()
        ..user = const DiscourseUser(
          username: 'reader',
          bookmarkAutoDeletePreference:
              BookmarkAutoDeletePreference.onOwnerReply,
        );
      final result = await f.create();
      expect(
        result.bookmark?.autoDeletePreference,
        BookmarkAutoDeletePreference.onOwnerReply,
      );
      expect(
        f.api.createdBookmarks.single.autoDeletePreference,
        BookmarkAutoDeletePreference.onOwnerReply,
      );
      await f.account.createBookmark(
        topicId: 7,
        targetType: BookmarkTargetType.topic,
        targetId: 7,
        autoDeletePreference: BookmarkAutoDeletePreference.never,
      );
      expect(
        f.api.createdBookmarks.last.autoDeletePreference,
        BookmarkAutoDeletePreference.never,
      );
    },
  );

  test('a signed-out forum refuses a create before sending it', () async {
    final f = _Fixture()..user = null;
    final result = await f.create();
    expect(result.reconciled, isFalse);
    expect(result.message, 'Reconnect to this forum to bookmark it.');
    expect(f.api.createdBookmarks, isEmpty);
    expect(f.data.holds, 0);
  });

  for (final operation in ['create', 'update', 'delete']) {
    test(
      'retirement while publishing a $operation reports it as forum-only',
      () async {
        final f = _Fixture();
        if (operation != 'create') {
          f.account.acceptBookmark(7, _bookmark, isPost: true);
        }
        var retired = false;
        f.store.ref<Post>(_site, 12).addListener(() {
          if (retired) return;
          retired = true;
          f.lifecycle.invalidate(_site);
        });
        final result = await switch (operation) {
          'create' => f.create(),
          'update' => f.account.updateBookmark(
            topicId: 7,
            bookmark: _bookmark,
            name: 'renamed',
            autoDeletePreference: BookmarkAutoDeletePreference.never,
          ),
          _ => f.account.deleteBookmark(topicId: 7, bookmark: _bookmark),
        };
        expect(retired, isTrue);
        expect(result.reconciled, isTrue);
        expect(result.message, switch (operation) {
          'create' => 'The bookmark was saved on the forum.',
          'update' => 'The bookmark was updated on the forum.',
          _ => 'The bookmark was deleted on the forum.',
        });
        expect(f.data.reads, isEmpty);
        expect(f.menu, 0);
        expect(f.list, 0);
      },
    );
  }

  test('core bookmark writes refuse a topic id that is not positive', () async {
    final f = _Fixture();
    for (final topicId in [0, -1]) {
      final result = await f.account.createBookmark(
        topicId: topicId,
        targetType: BookmarkTargetType.post,
        targetId: 12,
      );
      expect(result.reconciled, isFalse);
      expect(
        result.message,
        'This bookmark target requires its owning context.',
      );
    }
    expect(f.api.createdBookmarks, isEmpty);
    expect(f.data.holds, 0);
  });

  test('a delete the forum answers without topic state is re-read', () async {
    final f = _Fixture(api: _UnconfirmedDeleteApi());
    f.account.acceptBookmark(7, _bookmark, isPost: true);
    final result = await f.account.deleteBookmark(
      topicId: 7,
      bookmark: _bookmark,
    );
    expect(result.reconciled, isTrue);
    expect(f.data.reads, hasLength(1));
    expect(f.store.read<Post>(_site, 12)?.bookmark, _bookmark);
    expect(f.store.read<Topic>(_site, 7)?.bookmarked, isTrue);
  });

  test('a post bookmark without a loaded reader is refused unsent', () async {
    final f = _Fixture()..readerLoaded = false;
    final result = await f.create();
    expect(result.reconciled, isFalse);
    expect(
      result.message,
      'Another action on this bookmark is still finishing.',
    );
    expect(f.api.createdBookmarks, isEmpty);
    expect(
      f.account.bookmarkWriteInFlight(
        topicId: 7,
        targetType: BookmarkTargetType.post,
        targetId: 12,
      ),
      isFalse,
    );
  });

  test('an uncertain topic clear is re-read instead of applied', () async {
    final f = _Fixture(
      api: FakeDiscourseApi(
        writeFailure: const WriteException(WriteFailure.unreachable),
      ),
    );
    f.account.acceptBookmark(7, _bookmark, isPost: true);
    final result = await f.account.deleteAllTopicBookmarks(topicId: 7);
    expect(result.reconciled, isTrue);
    expect(f.data.reads, hasLength(1));
    expect(f.menu, 1);
    expect(f.list, 1);
    expect(f.store.read<Post>(_site, 12)?.bookmark, _bookmark);
    expect(f.data.holds, 0);
  });

  test('clearing a topic waits for a pending post bookmark write', () async {
    final api = _PendingWriteApi();
    final f = _Fixture(api: api);
    f.account.acceptBookmark(7, _bookmark, isPost: true);
    final pending = f.account.updateBookmark(
      topicId: 7,
      bookmark: _bookmark,
      name: 'renamed',
      autoDeletePreference: BookmarkAutoDeletePreference.never,
    );
    await pumpEventQueue();
    final cleared = await f.account.deleteAllTopicBookmarks(topicId: 7);
    expect(cleared.reconciled, isFalse);
    expect(cleared.message, 'Another bookmark action is still finishing.');
    api.ready.complete();
    expect((await pending).saved, isTrue);
    expect(f.store.read<Post>(_site, 12)?.bookmark?.name, 'renamed');
    expect(f.store.read<Topic>(_site, 7)?.bookmarked, isTrue);
  });

  test(
    'saved reminders are UTC instants and an update clears an omitted note',
    () async {
      final f = _Fixture();
      final local = DateTime(2030, 1, 2, 9, 30);
      final created = await f.account.createBookmark(
        topicId: 7,
        targetType: BookmarkTargetType.post,
        targetId: 12,
        name: 'note',
        reminderAt: local,
      );
      expect(created.bookmark!.reminderAt!.isUtc, isTrue);
      expect(created.bookmark!.reminderAt, local.toUtc());
      expect(created.bookmark!.name, 'note');
      final updated = await f.account.updateBookmark(
        topicId: 7,
        bookmark: created.bookmark!,
        reminderAt: local,
        autoDeletePreference: BookmarkAutoDeletePreference.never,
      );
      expect(updated.bookmark!.reminderAt!.isUtc, isTrue);
      expect(updated.bookmark!.reminderAt, local.toUtc());
      expect(updated.bookmark!.name, isNull);
      expect(f.store.read<Post>(_site, 12)?.bookmark?.name, isNull);
      final cleared = await f.account.clearBookmarkReminder(
        topicId: 7,
        bookmark: updated.bookmark!,
      );
      expect(cleared.bookmark!.reminderAt, isNull);
      expect(f.store.read<Post>(_site, 12)?.bookmark?.reminderAt, isNull);
    },
  );

  test('a lease only resolves the account session it was captured for', () {
    final f = _Fixture();
    final account = f.account;
    expect(f.bookmarks.forLease(_site, f.lifecycle.capture(_site)), account);
    expect(
      f.bookmarks.forLease(_site, f.lifecycle.capture('https://other.example')),
      isNull,
    );
  });

  test(
    'a forgotten account publishes nothing from an in-flight write',
    () async {
      final strategy = _Strategy();
      final api = _PendingWriteApi();
      final f = _Fixture(api: api, strategies: () => [strategy]);
      final account = f.account;
      final post = f.create();
      final plugin = f.bookmarks
          .pluginTarget(_pluginTarget)
          .createBookmark(siteUrl: _site, targetId: 12);
      await pumpEventQueue();
      f.bookmarks.forget(_site);
      expect(account.isCurrent, isFalse);
      api.ready.complete();
      for (final result in [await post, await plugin]) {
        expect(result.reconciled, isTrue);
        expect(result.message, 'The bookmark was saved on the forum.');
      }
      expect(api.createdBookmarks, hasLength(2));
      expect(strategy.puts, isEmpty);
      expect(strategy.repairs, isEmpty);
      expect(f.store.read<Post>(_site, 12)?.bookmark, isNull);
      expect(f.data.reads, isEmpty);
      expect(f.data.holds, 0);
      expect(f.bookmarks.forSite(_site), isNot(same(account)));
    },
  );

  test('a forum without a stored key refuses a create as forbidden', () async {
    final f = _Fixture();
    f.credentials.keys.remove(_site);
    final result = await f.create();
    expect(result.reconciled, isFalse);
    expect(
      result.message,
      const WriteException(WriteFailure.forbidden).message,
    );
    expect(f.api.createdBookmarks, isEmpty);
    expect(f.data.reads, isEmpty);
    expect(f.data.holds, 0);
  });

  test('plugin bookmark admission names why a target is refused', () async {
    final strategy = _Strategy();
    var strategies = <PluginBookmarkTargetStrategy>[strategy];
    final f = _Fixture(strategies: () => strategies);
    final scoped = await f.account.createBookmark(
      topicId: 7,
      targetType: _pluginTarget,
      targetId: 12,
    );
    expect(scoped.message, 'This bookmark target requires its owning context.');
    strategies = [];
    final missing = await f.bookmarks
        .pluginTarget(_pluginTarget)
        .createBookmark(siteUrl: _site, targetId: 12);
    expect(missing.reconciled, isFalse);
    expect(
      missing.message,
      'This bookmark target is not available in this build.',
    );
    expect(f.api.createdBookmarks, isEmpty);
    expect(strategy.puts, isEmpty);
  });

  test('a topic clear retired before its credential sends nothing', () async {
    late final _Fixture f;
    f = _Fixture(onChanged: () => f.lifecycle.invalidate(_site));
    final result = await f.account.deleteAllTopicBookmarks(topicId: 7);
    expect(result.reconciled, isTrue);
    expect(
      result.message,
      'The forum changed before the bookmarks were deleted.',
    );
    expect(f.data.reads, isEmpty);
  });
}
