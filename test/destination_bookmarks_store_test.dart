import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/destination_bookmarks_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/destination_bookmark.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _site = 'https://forum.example';
const _otherSite = 'https://other.example/subfolder';
const _account = 'user:reader';
const _page = ContentRoute(
  destination: PageDestination(CorePage.preferences),
  title: 'Preferences',
  icon: DIcons.gear,
);
const _category = ContentRoute(
  destination: FeedDestination(
    key: 'category-12',
    sourcePath: '/c/support/12.json',
  ),
  title: 'Support',
  icon: DIcons.folder,
);
const _chat = ContentRoute(
  destination: ExtensionDestination('chat-c-9'),
  title: 'Travel',
  icon: DIcons.comment,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'typed identities collapse category entrypoints and exclude server targets',
    () {
      final category = DestinationBookmark.fromRoute(_category)!;
      final link = DestinationBookmark.fromRoute(
        const ContentRoute(
          destination: FeedDestination(
            key: 'list-/c/renamed/12.json',
            sourcePath: '/c/renamed/12.json',
          ),
          title: 'Renamed',
          icon: DIcons.tag,
        ),
      )!;
      final filtered = DestinationBookmark.fromRoute(
        ContentRoute.filteredTopicList(TopicListMode.latest, categoryId: 12),
      )!;
      expect(category.kind, DestinationBookmarkKind.category);
      expect(link.identity, category.identity);
      expect(filtered.identity, category.identity);
      expect(DestinationBookmark.fromRoute(_chat)!.identity, 'chat:9');
      expect(
        DestinationBookmark.fromRoute(_page)!.kind,
        DestinationBookmarkKind.page,
      );
      expect(
        DestinationBookmark.fromRoute(
          ContentRoute.topic(topicId: 12, slug: 'topic', title: 'Topic'),
        ),
        isNull,
      );
      expect(
        DestinationBookmark.fromRoute(
          const ContentRoute(
            destination: ExtensionDestination('chat-c-9-t-2'),
            title: 'Thread',
            icon: DIcons.comment,
          ),
        ),
        isNull,
      );
      expect(
        DestinationBookmark.fromRoute(
          const ContentRoute(
            destination: PageDestination(CorePage.bookmarks),
            title: 'Bookmarks',
            icon: DIcons.bookmark,
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'all destination kinds survive restart with full routes and isolated owners',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = DestinationBookmarksStore();
      await first.load();
      for (final route in [_page, _category, _chat]) {
        await first.set(
          _site,
          _account,
          DestinationBookmark.fromRoute(route)!,
          bookmarked: true,
        );
      }
      await first.set(
        _site,
        'user:other',
        DestinationBookmark.fromRoute(_page)!,
        bookmarked: true,
      );
      await first.set(
        _otherSite,
        _account,
        DestinationBookmark.fromRoute(_category)!,
        bookmarked: true,
      );
      final restarted = DestinationBookmarksStore();
      await restarted.load();
      expect(
        restarted.entriesFor(_site, _account).map((entry) => entry.route),
        [_chat, _category, _page],
      );
      expect(restarted.entriesFor(_site, 'user:other').single.route, _page);
      expect(
        restarted.entriesFor(_otherSite, _account).single.route,
        _category,
      );
      expect(restarted.entriesFor(_site, 'anonymous'), isEmpty);
      await restarted.forgetSite(_site);
      final afterRemoval = DestinationBookmarksStore();
      await afterRemoval.load();
      expect(afterRemoval.entriesFor(_site, _account), isEmpty);
      expect(afterRemoval.entriesFor(_site, 'user:other'), isEmpty);
      expect(
        afterRemoval.entriesFor(_otherSite, _account).single.route,
        _category,
      );
    },
  );

  test(
    'add and remove are idempotent and duplicates collapse on disk',
    () async {
      final persistence = MemoryDestinationBookmarksPersistence();
      final store = DestinationBookmarksStore(persistence: persistence);
      await store.load();
      for (final route in [_page, _category, _chat]) {
        final bookmark = DestinationBookmark.fromRoute(route)!;
        expect(
          await store.set(_site, _account, bookmark, bookmarked: true),
          isTrue,
        );
        expect(
          await store.set(_site, _account, bookmark, bookmarked: true),
          isFalse,
        );
      }
      final document = jsonDecode(persistence.value!) as Map<String, dynamic>;
      final entries = document['entries'] as List;
      final routes = (entries.single as Map)['routes'] as List;
      routes.addAll(List.of(routes));
      persistence.value = jsonEncode(document);
      final restarted = DestinationBookmarksStore(persistence: persistence);
      await restarted.load();
      expect(restarted.entriesFor(_site, _account), hasLength(3));
      for (final bookmark in restarted.entriesFor(_site, _account)) {
        expect(
          await restarted.set(_site, _account, bookmark, bookmarked: false),
          isTrue,
        );
        expect(
          await restarted.set(_site, _account, bookmark, bookmarked: false),
          isFalse,
        );
      }
      final afterRemoval = DestinationBookmarksStore(persistence: persistence);
      await afterRemoval.load();
      expect(afterRemoval.entriesFor(_site, _account), isEmpty);
    },
  );

  test(
    'failed and queued writes never roll back a newer durable mutation',
    () async {
      final persistence = _GatedPersistence();
      final store = DestinationBookmarksStore(persistence: persistence);
      await store.load();
      final first = store.set(
        _site,
        _account,
        DestinationBookmark.fromRoute(_page)!,
        bookmarked: true,
      );
      final failed = expectLater(first, throwsStateError);
      final next = store.set(
        _site,
        _account,
        DestinationBookmark.fromRoute(_category)!,
        bookmarked: true,
      );
      await pumpEventQueue();
      expect(store.entriesFor(_site, _account), isEmpty);
      persistence.first.complete(false);
      await failed;
      expect(await next, isTrue);
      expect(store.entriesFor(_site, _account).single.route, _category);
      final restarted = DestinationBookmarksStore(persistence: persistence);
      await restarted.load();
      expect(restarted.entriesFor(_site, _account).single.route, _category);
    },
  );

  test(
    'filtered group inbox destinations preserve their original filters across restart',
    () async {
      final persistence = MemoryDestinationBookmarksPersistence();
      final store = DestinationBookmarksStore(persistence: persistence);
      await store.load();
      final routes = [
        ContentRoute.searchList(
          'status:open',
          groupName: 'team',
          messageMode: MessageListMode.inbox,
        ),
        ContentRoute.messages(
          groupName: 'team',
        ).withTopicListSearch('important'),
      ];
      for (final route in routes) {
        final bookmark = DestinationBookmark.fromRoute(route)!;
        expect(bookmark.route, route);
        await store.set(_site, _account, bookmark, bookmarked: true);
      }
      final restarted = DestinationBookmarksStore(persistence: persistence);
      await restarted.load();
      expect(
        restarted.entriesFor(_site, _account).map((entry) => entry.route),
        routes.reversed,
      );
    },
  );

  test('an unreadable snapshot cannot be silently overwritten', () async {
    final persistence = MemoryDestinationBookmarksPersistence()
      ..value = '{invalid';
    final store = DestinationBookmarksStore(persistence: persistence);
    await expectLater(store.load(), throwsFormatException);
    await expectLater(
      store.set(
        _site,
        _account,
        DestinationBookmark.fromRoute(_page)!,
        bookmarked: true,
      ),
      throwsStateError,
    );
    expect(persistence.value, '{invalid');
  });
}

class _GatedPersistence implements DestinationBookmarksPersistence {
  final first = Completer<bool>();
  String? value;
  int writes = 0;
  @override
  Future<String?> read() async => value;
  @override
  Future<bool> write(String value) async {
    if (++writes == 1 && !await first.future) return false;
    this.value = value;
    return true;
  }
}
