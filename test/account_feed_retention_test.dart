import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/account_feed_window.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/bookmark_feed.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/draft_feed.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_activity_feed.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:discourse_native/src/shell/draft_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

UserActivityItem _activity(int id, {String excerpt = '', int? category}) =>
    UserActivityItem(
      actionType: 4,
      topicId: id,
      postNumber: 1,
      title: 'Topic $id',
      slug: 'topic-$id',
      username: 'reader',
      excerpt: excerpt,
      categoryId: category,
    );

UserDraft _draft(int id, {String body = '', int sequence = 1}) => UserDraft(
  key: 'topic_$id',
  sequence: sequence,
  data: ComposerDraft(reply: body),
);

const _instance = DiscourseInstance(
  url: 'https://one.example',
  title: 'One',
  user: DiscourseUser(username: 'reader'),
);

class _Keys implements SiteApiKeyReader {
  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'key';
}

class _Pages implements AccountActivityApi, DraftsApi {
  final activityOffsets = <(int, int)>[];
  final bookmarkPages = <int>[];
  final draftOffsets = <(int, int)>[];
  final drafts = [for (var i = 0; i < 360; i++) _draft(i)];
  bool failPrevious = false;
  bool shortenPrevious = false;
  Completer<UserActivityPage>? activityAnswer;

  @override
  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    activityOffsets.add((offset, limit));
    if (activityAnswer case final answer?) return answer.future;
    if (failPrevious) throw StateError('offline');
    if (shortenPrevious && offset > 0) {
      return UserActivityPage(items: [_activity(offset)], rawItemCount: 1);
    }
    return UserActivityPage(
      items: [
        for (var i = offset; i < (offset + limit).clamp(0, 360); i++)
          _activity(i),
      ],
      rawItemCount: (360 - offset).clamp(0, limit),
    );
  }

  @override
  Future<BookmarkListPage> bookmarkListPage({
    required String siteUrl,
    required String apiKey,
    required String username,
    int page = 0,
    String? clientId,
  }) async {
    bookmarkPages.add(page);
    if (failPrevious) throw StateError('offline');
    return BookmarkListPage(
      bookmarks: [
        for (var i = page * 30; i < ((page + 1) * 30).clamp(0, 360); i++)
          Bookmark(id: i),
      ],
      hasMore: page < 11 && !(shortenPrevious && page > 0),
    );
  }

  @override
  Future<UserDraftPage> userDrafts({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    draftOffsets.add((offset, limit));
    if (failPrevious) throw StateError('offline');
    final page = drafts
        .skip(offset)
        .take(shortenPrevious && offset > 0 ? 1 : limit)
        .toList();
    return UserDraftPage(drafts: page, rawItemCount: page.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'account controllers restore previous pages, retry direction and forget ownership',
    () async {
      final api = _Pages();
      final controller = AccountActivityController(
        api: api,
        credentials: _Keys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);
      for (var i = 0; i < 12; i++) {
        await controller.loadUserActivity(_instance, loadMore: i > 0);
        await controller.loadBookmarkList(_instance, loadMore: i > 0);
      }
      expect(controller.userActivityFor(_instance.url).firstOffset, 60);
      expect(controller.bookmarkListFor(_instance.url).firstPage, 2);
      api.failPrevious = true;
      await controller.loadUserActivity(_instance, loadPrevious: true);
      await controller.loadBookmarkList(_instance, loadPrevious: true);
      expect(controller.userActivityFor(_instance.url).retryPrevious, isTrue);
      expect(controller.bookmarkListFor(_instance.url).retryPrevious, isTrue);
      api.failPrevious = false;
      await controller.loadUserActivity(_instance, loadPrevious: true);
      await controller.loadBookmarkList(_instance, loadPrevious: true);
      expect(api.activityOffsets.last, (30, 30));
      expect(api.bookmarkPages.last, 1);
      expect(controller.userActivityFor(_instance.url).items.first.topicId, 30);
      expect(controller.bookmarkListFor(_instance.url).bookmarks.first.id, 30);
      expect(controller.bookmarkListFor(_instance.url).hasMore, isTrue);
      api.activityAnswer = Completer<UserActivityPage>();
      final stale = controller.loadUserActivity(_instance, loadPrevious: true);
      await pumpEventQueue();
      controller.forget(_instance.url);
      api.activityAnswer!.complete(
        UserActivityPage(items: [_activity(1)], rawItemCount: 1),
      );
      await stale;
      expect(controller.userActivityFor(_instance.url).loaded, isFalse);
      expect(controller.userActivityFor(_instance.url).items, isEmpty);
    },
  );

  test(
    'draft controller restores pages and refreshes an uncertain deleted prefix',
    () async {
      final api = _Pages();
      final controller = DraftListController(
        api: api,
        credentials: _Keys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);
      for (var i = 0; i < 12; i++) {
        await controller.load(_instance);
      }
      expect(controller.feedFor(_instance.url).firstOffset, 60);
      api.failPrevious = true;
      await controller.load(_instance, loadPrevious: true);
      expect(controller.feedFor(_instance.url).retryPrevious, isTrue);
      api.failPrevious = false;
      await controller.load(_instance, loadPrevious: true);
      expect(api.draftOffsets.last, (30, 30));
      expect(controller.feedFor(_instance.url).drafts.first.key, 'topic_30');
      api.drafts.removeWhere((draft) => draft.key == 'topic_4');
      controller.recordDeleted(_instance.url, 'topic_4', knownToExist: true);
      expect(controller.feedFor(_instance.url).requiresRefresh, isTrue);
      await controller.load(_instance);
      expect(api.draftOffsets.last, (0, 30));
      expect(controller.feedFor(_instance.url).hasPrevious, isFalse);
      expect(controller.feedFor(_instance.url).requiresRefresh, isFalse);
      expect(
        controller.feedFor(_instance.url).drafts.map((row) => row.key),
        isNot(contains('topic_4')),
      );
    },
  );

  test(
    'previous draft requests stop at a deletion-shifted partial boundary',
    () async {
      final api = _Pages();
      final controller = DraftListController(
        api: api,
        credentials: _Keys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);
      for (var i = 0; i < 10; i++) {
        await controller.load(_instance);
      }
      api.drafts.removeWhere((draft) => draft.key == 'topic_5');
      controller.recordDeleted(_instance.url, 'topic_5', knownToExist: true);
      await controller.load(_instance);
      expect(controller.feedFor(_instance.url).firstOffset, 29);
      await controller.load(_instance, loadPrevious: true);
      expect(api.draftOffsets.last, (0, 29));
      expect(controller.feedFor(_instance.url).firstOffset, 0);
      expect(controller.feedFor(_instance.url).drafts.first.key, 'topic_0');
      expect(
        controller
            .feedFor(_instance.url)
            .drafts
            .where((row) => row.key == 'topic_29'),
        hasLength(1),
      );
      expect(
        controller.feedFor(_instance.url).drafts.map((row) => row.key),
        isNot(contains('topic_5')),
      );
    },
  );

  test(
    'short previous responses reconcile the source before joining shifted ranges',
    () async {
      final api = _Pages();
      final account = AccountActivityController(
        api: api,
        credentials: _Keys(),
        lifecycle: SiteLifecycle(),
      );
      final drafts = DraftListController(
        api: api,
        credentials: _Keys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(account.dispose);
      addTearDown(drafts.dispose);
      for (var i = 0; i < 12; i++) {
        await account.loadUserActivity(_instance, loadMore: i > 0);
        await account.loadBookmarkList(_instance, loadMore: i > 0);
        await drafts.load(_instance);
      }
      api.shortenPrevious = true;
      await account.loadUserActivity(_instance, loadPrevious: true);
      await account.loadBookmarkList(_instance, loadPrevious: true);
      await drafts.load(_instance, loadPrevious: true);
      await pumpEventQueue();
      expect(api.activityOffsets.sublist(12), [(30, 30), (0, 30)]);
      expect(api.bookmarkPages.sublist(12), [1, 0]);
      expect(api.draftOffsets.sublist(12), [(30, 30), (0, 30)]);
      expect(account.userActivityFor(_instance.url).hasPrevious, isFalse);
      expect(account.bookmarkListFor(_instance.url).hasPrevious, isFalse);
      expect(drafts.feedFor(_instance.url).hasPrevious, isFalse);
    },
  );

  test('empty retained windows still expose navigation to evicted rows', () {
    var activity = const UserActivityFeed();
    var bookmarks = const BookmarkListFeed();
    var drafts = const DraftFeed();
    for (var i = 0; i < 11; i++) {
      activity = activity.withPage(
        UserActivityPage(
          items: i == 0 ? [_activity(1)] : [],
          rawItemCount: i < 10 ? 30 : 0,
        ),
        limit: 30,
        replace: false,
      );
      bookmarks = bookmarks.withPage(
        BookmarkListPage(
          bookmarks: i == 0 ? [const Bookmark(id: 1)] : [],
          hasMore: i < 10,
        ),
        replace: false,
      );
      drafts = drafts.withPage(
        UserDraftPage(
          drafts: i == 0 ? [_draft(1)] : [],
          rawItemCount: i < 10 ? 30 : 0,
        ),
        limit: 30,
        reportedCount: null,
      );
    }
    expect(activity.items, isEmpty);
    expect(bookmarks.bookmarks, isEmpty);
    expect(drafts.drafts, isEmpty);
    expect(activity.isEmpty, isFalse);
    expect(bookmarks.isEmpty, isFalse);
    expect(drafts.isEmpty, isFalse);
    expect(activity.hasPrevious, isTrue);
    expect(bookmarks.hasPrevious, isTrue);
    expect(drafts.hasPrevious, isTrue);
  });

  test('all 3600 activity rows remain reachable through a bounded window', () {
    var feed = const UserActivityFeed();
    for (var page = 0; page < 120; page++) {
      feed = feed.withPage(
        UserActivityPage(
          items: [
            for (var i = page * 30; i < (page + 1) * 30; i++) _activity(i),
          ],
          rawItemCount: 30,
        ),
        limit: 30,
        replace: page == 0,
      );
      expect(feed.items.length, lessThanOrEqualTo(300));
      expect(feed.retainedPageCount, lessThanOrEqualTo(10));
    }
    expect(feed.firstOffset, 3300);
    expect(feed.nextOffset, 3600);
    final restored = <int>{for (final item in feed.items) item.topicId};
    while (feed.hasPrevious) {
      final offset = feed.previousOffset(30);
      feed = feed.withPage(
        UserActivityPage(
          items: [for (var i = offset; i < feed.firstOffset; i++) _activity(i)],
          rawItemCount: feed.firstOffset - offset,
        ),
        limit: 30,
        replace: false,
        prepend: true,
        requestOffset: offset,
      );
      restored.addAll(feed.items.map((item) => item.topicId));
      expect(feed.items.length, lessThanOrEqualTo(300));
    }
    expect(restored, {for (var i = 0; i < 3600; i++) i});
    expect(feed.nextOffset, 300);
    expect(feed.hasMore, isTrue);
    while (feed.nextOffset < 3600) {
      final offset = feed.nextOffset;
      feed = feed.withPage(
        UserActivityPage(
          items: [for (var i = offset; i < offset + 30; i++) _activity(i)],
          rawItemCount: 30,
        ),
        limit: 30,
        replace: false,
      );
    }
    expect(feed.items.last.topicId, 3599);
  });

  test('bookmarks restore evicted pages and preserve terminal direction', () {
    var feed = const BookmarkListFeed();
    for (var page = 0; page < 120; page++) {
      feed = feed.withPage(
        BookmarkListPage(
          bookmarks: [
            for (var i = page * 30; i < (page + 1) * 30; i++) Bookmark(id: i),
          ],
          hasMore: page < 119,
        ),
        replace: page == 0,
      );
      expect(feed.bookmarks.length, lessThanOrEqualTo(300));
    }
    expect(feed.hasMore, isFalse);
    final restored = <int>{for (final item in feed.bookmarks) item.id};
    while (feed.hasPrevious) {
      final page = feed.previousPage;
      feed = feed.withPage(
        BookmarkListPage(
          bookmarks: [
            for (var i = page * 30; i < (page + 1) * 30; i++) Bookmark(id: i),
          ],
          hasMore: true,
        ),
        replace: false,
        prepend: true,
        requestPage: page,
      );
      restored.addAll(feed.bookmarks.map((item) => item.id));
    }
    expect(restored.length, 3600);
    expect(feed.nextPage, 10);
    expect(feed.hasMore, isTrue);
  });

  test(
    'drafts bound full bodies and never report the retained length as total',
    () {
      var feed = const DraftFeed();
      for (var page = 0; page < 120; page++) {
        feed = feed.withPage(
          UserDraftPage(
            drafts: [
              for (var i = page * 30; i < (page + 1) * 30; i++) _draft(i),
            ],
            rawItemCount: 30,
          ),
          limit: 30,
          reportedCount: null,
        );
        expect(feed.drafts.length, lessThanOrEqualTo(300));
      }
      expect(feed.totalCount, isNull);
      final restored = <String>{for (final draft in feed.drafts) draft.key};
      while (feed.hasPrevious) {
        final offset = feed.previousOffset(30);
        feed = feed.withPage(
          UserDraftPage(
            drafts: [for (var i = offset; i < feed.firstOffset; i++) _draft(i)],
            rawItemCount: feed.firstOffset - offset,
          ),
          limit: 30,
          reportedCount: null,
          prepend: true,
          requestOffset: offset,
        );
        restored.addAll(feed.drafts.map((draft) => draft.key));
      }
      expect(restored.length, 3600);
      expect(feed.nextOffset, 300);
      final largeBody = 'x' * 150000;
      for (var page = 0; page < 5; page++) {
        feed = feed.withPage(
          UserDraftPage(
            drafts: [
              for (var i = 0; i < 10; i++)
                _draft(4000 + page * 10 + i, body: largeBody),
            ],
            rawItemCount: 10,
          ),
          limit: 10,
          reportedCount: null,
        );
        expect(feed.retainedPageCount, 1);
        expect(feed.drafts, hasLength(10));
        expect(
          feed.estimatedRetainedBytes,
          greaterThan(AccountFeedWindow.maximumEstimatedBytes),
        );
      }
      expect(feed.hasPrevious, isTrue);
    },
  );

  test(
    'bytes evict whole pages before the row limit and preserve refresh failure',
    () {
      var feed = const UserActivityFeed();
      for (var page = 0; page < 8; page++) {
        feed = feed.withPage(
          UserActivityPage(
            items: [
              for (var i = 0; i < 10; i++)
                _activity(page * 10 + i, excerpt: 'x' * 50000),
            ],
            rawItemCount: 10,
          ),
          limit: 10,
          replace: false,
        );
        expect(
          feed.estimatedRetainedBytes,
          lessThanOrEqualTo(AccountFeedWindow.maximumEstimatedBytes),
        );
      }
      expect(feed.items.length, lessThan(80));
      final failed = feed
          .loadingPage(replace: true)
          .withError('offline', retryFromStart: true);
      expect(failed.items, feed.items);
      expect(failed.firstOffset, feed.firstOffset);
      expect(failed.nextOffset, feed.nextOffset);
      expect(failed.retryFromStart, isTrue);
      final refreshed = failed.withPage(
        UserActivityPage(items: [_activity(999)], rawItemCount: 1),
        limit: 30,
        replace: true,
      );
      expect(refreshed.hasPrevious, isFalse);
      expect(refreshed.items.single.topicId, 999);
    },
  );

  test('category strings participate in the retained activity budget', () {
    var feed = const UserActivityFeed();
    for (var i = 0; i < 3; i++) {
      feed = feed.withPage(
        UserActivityPage(
          items: [_activity(i, category: i)],
          rawItemCount: 1,
          categories: [
            TopicCategory(
              id: i,
              name: '$i',
              color: 'ffffff',
              topicTemplate: 'x' * 1100000,
            ),
          ],
        ),
        limit: 1,
        replace: false,
      );
      expect(feed.retainedPageCount, 1);
      expect(feed.categoriesById.keys, [i]);
      expect(
        feed.estimatedRetainedBytes,
        lessThan(AccountFeedWindow.maximumEstimatedBytes),
      );
    }
  });

  test('overlap survives eviction with latest payload and existing order', () {
    var feed = const UserActivityFeed();
    for (var i = 0; i < 10; i++) {
      feed = feed.withPage(
        UserActivityPage(items: [_activity(i)], rawItemCount: 1),
        limit: 1,
        replace: false,
      );
    }
    feed = feed.withPage(
      UserActivityPage(
        items: [
          _activity(0, excerpt: 'new'),
          _activity(10),
        ],
        rawItemCount: 2,
      ),
      limit: 2,
      replace: false,
    );
    expect(feed.items.map((row) => row.topicId), [
      for (var i = 1; i < 10; i++) i,
      0,
      10,
    ]);
    expect(feed.items.firstWhere((row) => row.topicId == 0).excerpt, 'new');
    expect(feed.nextOffset, 12);
    feed = feed.withPage(
      UserActivityPage(
        items: [
          _activity(5, excerpt: 'updated'),
          _activity(11),
        ],
        rawItemCount: 2,
      ),
      limit: 2,
      replace: false,
    );
    expect(
      feed.items.map((row) => row.topicId).where((id) => id == 5),
      hasLength(1),
    );
    expect(feed.items.firstWhere((row) => row.topicId == 5).excerpt, 'updated');
  });

  test(
    'raw invalid slots bound empty packets and categories follow retained rows',
    () {
      var feed = const UserActivityFeed();
      for (var i = 0; i < 120; i++) {
        feed = feed.withPage(
          UserActivityPage(
            items: i.isEven ? [_activity(i, category: i)] : [],
            rawItemCount: 30,
            categories: [TopicCategory(id: i, name: '$i', color: 'ffffff')],
          ),
          limit: 30,
          replace: false,
        );
      }
      expect(feed.nextOffset, 3600);
      expect(feed.firstOffset, 3300);
      expect(feed.retainedPageCount, 10);
      expect(
        feed.categoriesById.keys.toSet(),
        feed.items.map((item) => item.categoryId).toSet(),
      );
    },
  );

  test(
    'draft deletion shifts raw cursors and partial previous page has no gap',
    () {
      var feed = const DraftFeed();
      for (var i = 0; i < 11; i++) {
        feed = feed.withPage(
          UserDraftPage(
            drafts: [for (var j = i * 30; j < (i + 1) * 30; j++) _draft(j)],
            rawItemCount: 30,
          ),
          limit: 30,
          reportedCount: null,
        );
      }
      feed = feed.without('topic_35', knownToExist: true);
      expect(feed.firstOffset, 30);
      expect(feed.nextOffset, 329);
      feed = feed.withPage(
        UserDraftPage(
          drafts: [for (var i = 0; i < 30; i++) _draft(i)],
          rawItemCount: 30,
        ),
        limit: 30,
        reportedCount: null,
        prepend: true,
        requestOffset: 0,
      );
      expect(feed.nextOffset, 299);
      feed = feed.withPage(
        UserDraftPage(
          drafts: [for (var i = 300; i < 330; i++) _draft(i)],
          rawItemCount: 30,
        ),
        limit: 30,
        reportedCount: null,
      );
      expect(feed.nextOffset, 329);
      expect(feed.drafts.last.key, 'topic_329');
      final invalidated = feed.without('topic_2', knownToExist: true);
      expect(invalidated.requiresRefresh, isTrue);
    },
  );

  test(
    'draft overlaps retain the highest sequence while raw slots advance',
    () {
      var feed = const DraftFeed().withPage(
        UserDraftPage(
          drafts: [_draft(1, sequence: 5, body: 'new')],
          rawItemCount: 30,
        ),
        limit: 30,
        reportedCount: null,
      );
      feed = feed.withPage(
        UserDraftPage(
          drafts: [
            _draft(1, sequence: 4, body: 'old'),
            _draft(2),
          ],
          rawItemCount: 30,
        ),
        limit: 30,
        reportedCount: null,
      );
      expect(feed.nextOffset, 60);
      expect(feed.drafts.first.data!.reply, 'new');
      feed = feed.loadingMore(prepend: true).withError('offline');
      expect(feed.retryPrevious, isTrue);
      expect(feed.nextOffset, 60);
    },
  );
}
