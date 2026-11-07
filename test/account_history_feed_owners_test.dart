import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/shell/account_history_feed_owners.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  for (final bookmarks in [true, false]) {
    final label = bookmarks ? 'bookmarks' : 'activity';
    for (final probe in [
      'retained rows',
      'default reload',
      'pending successor',
    ]) {
      test('$label $probe on bare account retirement', () async {
        final api = _HistoryApi();
        final lifecycle = SiteLifecycle();
        final credentials = FakeApiCredentialReader()
          ..keys[_siteUrl] = 'old-key';
        final bookmarkOwner = BookmarkListOwner(
          api: api,
          credentials: credentials,
          lifecycle: lifecycle,
          changed: () {},
        );
        final activityOwner = UserActivityOwner(
          api: api,
          credentials: credentials,
          lifecycle: lifecycle,
          changed: () {},
        );
        addTearDown(bookmarkOwner.dispose);
        addTearDown(activityOwner.dispose);
        final site = instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'sam'));
        Future<void> load() =>
            bookmarks ? bookmarkOwner.load(site) : activityOwner.load(site);
        final old = load();
        await api.started.future;
        if (probe != 'pending successor') {
          api.complete(0);
          await old;
        }
        lifecycle.invalidate(_siteUrl);
        if (probe == 'retained rows') {
          expect(
            bookmarks
                ? bookmarkOwner.feedFor(_siteUrl).bookmarks
                : activityOwner.feedFor(_siteUrl).items,
            isEmpty,
          );
        } else {
          credentials.keys[_siteUrl] = 'new-key';
          final successor = load();
          if (probe == 'pending successor') {
            expect(identical(successor, old), isFalse);
          }
          await pumpEventQueue();
          expect(api._calls, 2);
          expect(api.keys, ['old-key', 'new-key']);
          api.complete(1);
          await successor;
          if (probe == 'pending successor') {
            api.complete(0);
            await old;
          }
        }
      });
    }
  }

  for (final bookmarks in [true, false]) {
    final name = bookmarks ? 'bookmark list' : 'user activity';
    test(
      '$name loads headlessly and publishes aspect before aggregate',
      () async {
        final api = _HistoryApi();
        final lifecycle = SiteLifecycle();
        final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
        final events = <String>[];
        final bookmarkOwner = BookmarkListOwner(
          api: api,
          credentials: credentials,
          lifecycle: lifecycle,
          changed: () => events.add('bookmark aggregate'),
        );
        final activityOwner = UserActivityOwner(
          api: api,
          credentials: credentials,
          lifecycle: lifecycle,
          changed: () => events.add('activity aggregate'),
        );
        addTearDown(bookmarkOwner.dispose);
        addTearDown(activityOwner.dispose);
        bookmarkOwner.addListener(() => events.add('bookmark aspect'));
        activityOwner.addListener(() => events.add('activity aspect'));
        final site = instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'sam'));
        final pending = bookmarks
            ? bookmarkOwner.load(site)
            : activityOwner.load(site);
        expect(
          events,
          bookmarks
              ? ['bookmark aspect', 'bookmark aggregate']
              : ['activity aspect', 'activity aggregate'],
        );
        await api.started.future;
        api.complete(0);
        await pending;
        expect(
          events,
          bookmarks
              ? [
                  'bookmark aspect',
                  'bookmark aggregate',
                  'bookmark aspect',
                  'bookmark aggregate',
                ]
              : [
                  'activity aspect',
                  'activity aggregate',
                  'activity aspect',
                  'activity aggregate',
                ],
        );
        expect(bookmarkOwner.feedFor(_siteUrl).loaded, bookmarks);
        expect(activityOwner.feedFor(_siteUrl).loaded, !bookmarks);

        Future<void> load({bool loadMore = false}) => bookmarks
            ? bookmarkOwner.load(site, loadMore: loadMore)
            : activityOwner.load(site, loadMore: loadMore);
        unawaited(load());
        unawaited(load(loadMore: true));
        expect(
          events,
          hasLength(4),
          reason: 'A loaded list without further pages has nothing to fetch.',
        );
      },
    );

    test('$name retirement isolates a same-URL successor', () async {
      final api = _HistoryApi();
      final lifecycle = SiteLifecycle();
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      var changes = 0;
      final bookmarkOwner = BookmarkListOwner(
        api: api,
        credentials: credentials,
        lifecycle: lifecycle,
        changed: () => changes++,
      );
      final activityOwner = UserActivityOwner(
        api: api,
        credentials: credentials,
        lifecycle: lifecycle,
        changed: () => changes++,
      );
      addTearDown(bookmarkOwner.dispose);
      addTearDown(activityOwner.dispose);
      final site = instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'sam'));
      Future<void> load() =>
          bookmarks ? bookmarkOwner.load(site) : activityOwner.load(site);
      bool loaded() => bookmarks
          ? bookmarkOwner.feedFor(_siteUrl).loaded
          : activityOwner.feedFor(_siteUrl).loaded;
      final stale = load();
      await api.started.future;
      lifecycle.invalidate(_siteUrl);
      expect(
        bookmarks
            ? bookmarkOwner.retire(_siteUrl)
            : activityOwner.retire(_siteUrl),
        isFalse,
      );
      expect(
        changes,
        2,
        reason: 'Lease retirement already published withdrawal.',
      );
      final fresh = load();
      await api.secondStarted.future;
      api.complete(0);
      await stale;
      expect(loaded(), isFalse);
      expect(load(), same(fresh));
      api.complete(1);
      await fresh;
      expect(loaded(), isTrue);
      expect(changes, 4);
    });

    for (final trigger in ['aspect', 'aggregate', 'earlier observer']) {
      test('$name $trigger can admit successor before old failure', () async {
        final api = _HistoryApi();
        final lifecycle = SiteLifecycle();
        final credentials = FakeApiCredentialReader()
          ..keys[_siteUrl] = 'old-key';
        final opening = lifecycle.capture(_siteUrl);
        final site = instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'sam'));
        late BookmarkListOwner bookmarkOwner;
        late UserActivityOwner activityOwner;
        Future<void> load() =>
            bookmarks ? bookmarkOwner.load(site) : activityOwner.load(site);
        var admitted = false;
        Future<void>? successor;
        void admit() {
          if (opening.isCurrent || admitted) return;
          admitted = true;
          credentials.keys[_siteUrl] = 'new-key';
          successor = load();
        }

        var changes = 0;
        void changed() {
          changes++;
          if (trigger == 'aggregate') admit();
        }

        if (trigger == 'earlier observer') opening.onRetire(admit);
        bookmarkOwner = BookmarkListOwner(
          api: api,
          credentials: credentials,
          lifecycle: lifecycle,
          changed: changed,
        );
        activityOwner = UserActivityOwner(
          api: api,
          credentials: credentials,
          lifecycle: lifecycle,
          changed: changed,
        );
        addTearDown(bookmarkOwner.dispose);
        addTearDown(activityOwner.dispose);
        if (trigger == 'aspect') {
          (bookmarks ? bookmarkOwner : activityOwner).addListener(admit);
        }
        final old = load();
        var oldSettled = false;
        unawaited(old.then((_) => oldSettled = true));
        await api.started.future;
        lifecycle.invalidate(_siteUrl);
        await api.secondStarted.future;
        expect(
          oldSettled,
          isFalse,
          reason: 'Retirement does not finish physical IO.',
        );
        expect(api.keys, ['old-key', 'new-key']);
        expect(
          bookmarks
              ? bookmarkOwner.feedFor(_siteUrl).loading
              : activityOwner.feedFor(_siteUrl).loading,
          isTrue,
        );
        api.complete(1);
        await successor;
        expect(
          bookmarks
              ? bookmarkOwner.feedFor(_siteUrl).loaded
              : activityOwner.feedFor(_siteUrl).loaded,
          isTrue,
        );
        final acceptedChanges = changes;
        api.fail(0);
        await old;
        expect(changes, acceptedChanges);
        expect(
          bookmarks
              ? bookmarkOwner.feedFor(_siteUrl).loaded
              : activityOwner.feedFor(_siteUrl).loaded,
          isTrue,
        );
      });
    }

    test('$name explicit retirement remains silent and idempotent', () async {
      final api = _HistoryApi();
      final lifecycle = SiteLifecycle();
      var changes = 0;
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      final bookmarkOwner = BookmarkListOwner(
        api: api,
        credentials: credentials,
        lifecycle: lifecycle,
        changed: () => changes++,
      );
      final activityOwner = UserActivityOwner(
        api: api,
        credentials: credentials,
        lifecycle: lifecycle,
        changed: () => changes++,
      );
      addTearDown(bookmarkOwner.dispose);
      addTearDown(activityOwner.dispose);
      final site = instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'sam'));
      final old = bookmarks
          ? bookmarkOwner.load(site)
          : activityOwner.load(site);
      await api.started.future;
      expect(
        bookmarks
            ? bookmarkOwner.retire(_siteUrl)
            : activityOwner.retire(_siteUrl),
        isTrue,
      );
      expect(changes, 1);
      lifecycle.invalidate(_siteUrl);
      expect(changes, 1, reason: 'Explicit retirement detached its observer.');
      expect(
        bookmarks
            ? bookmarkOwner.retire(_siteUrl)
            : activityOwner.retire(_siteUrl),
        isFalse,
      );
      api.complete(0);
      await old;
      expect(changes, 1);
    });

    test('$name disposal refuses a pending result', () async {
      final api = _HistoryApi();
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      var changes = 0;
      final bookmarkOwner = BookmarkListOwner(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        changed: () => changes++,
      );
      final activityOwner = UserActivityOwner(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        changed: () => changes++,
      );
      final site = instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'sam'));
      final pending = bookmarks
          ? bookmarkOwner.load(site)
          : activityOwner.load(site);
      await api.started.future;
      bookmarkOwner.dispose();
      activityOwner.dispose();
      api.complete(0);
      await pending;
      expect(changes, 1);
      expect(bookmarkOwner.feedFor(_siteUrl).loaded, isFalse);
      expect(activityOwner.feedFor(_siteUrl).loaded, isFalse);
      unawaited(
        bookmarks ? bookmarkOwner.load(site) : activityOwner.load(site),
      );
      expect(changes, 1, reason: 'A disposed owner starts no load.');
    });
  }
}

class _HistoryApi extends FakeDiscourseApi {
  final started = Completer<void>();
  final secondStarted = Completer<void>();
  final _answers = [Completer<void>(), Completer<void>()];
  var _calls = 0;
  final keys = <String>[];

  Future<void> _wait() {
    final index = _calls++;
    (index == 0 ? started : secondStarted).complete();
    return _answers[index].future;
  }

  void complete(int index) => _answers[index].complete();
  void fail(int index) =>
      _answers[index].completeError(StateError('retired response'));

  @override
  Future<BookmarkListPage> bookmarkListPage({
    required String siteUrl,
    required String apiKey,
    required String username,
    int page = 0,
    String? clientId,
  }) async {
    keys.add(apiKey);
    await _wait();
    return const BookmarkListPage(bookmarks: [Bookmark(id: 1, title: 'Saved')]);
  }

  @override
  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    keys.add(apiKey);
    await _wait();
    return const UserActivityPage(
      items: [
        UserActivityItem(
          actionType: 4,
          topicId: 3,
          postNumber: 1,
          title: 'Private',
          slug: 'private',
          username: 'sam',
          excerpt: 'secret',
        ),
      ],
      rawItemCount: 1,
    );
  }
}
