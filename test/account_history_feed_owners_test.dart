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
        isTrue,
      );
      expect(changes, 1, reason: 'Retirement waits for the facade to publish.');
      final fresh = load();
      await api.secondStarted.future;
      api.complete(0);
      await stale;
      expect(loaded(), isFalse);
      expect(load(), same(fresh));
      api.complete(1);
      await fresh;
      expect(loaded(), isTrue);
      expect(changes, 3);
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
    });
  }
}

class _HistoryApi extends FakeDiscourseApi {
  final started = Completer<void>();
  final secondStarted = Completer<void>();
  final _answers = [Completer<void>(), Completer<void>()];
  var _calls = 0;

  Future<void> _wait() {
    final index = _calls++;
    (index == 0 ? started : secondStarted).complete();
    return _answers[index].future;
  }

  void complete(int index) => _answers[index].complete();

  @override
  Future<BookmarkListPage> bookmarkListPage({
    required String siteUrl,
    required String apiKey,
    required String username,
    int page = 0,
    String? clientId,
  }) async {
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
    await _wait();
    return const UserActivityPage();
  }
}
