import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/data/destination_bookmarks_store.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/account_destination_bookmarks.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.discourse.org';
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

void main() {
  test('a toggle saves for the account that opened it and announces', () async {
    final h = await _Harness.loaded();
    addTearDown(h.dispose);

    final result = await h.bookmarks.actionFor(_page)!.invoke();

    expect(result.saved, isTrue);
    expect(h.bookmarks.entriesFor(_site).single.route.title, 'Preferences');
    expect(h.announced, 1);
  });

  test('a saved destination toggles off', () async {
    final h = await _Harness.loaded();
    addTearDown(h.dispose);
    await h.bookmarks.actionFor(_page)!.invoke();

    final action = h.bookmarks.actionFor(_page)!;
    expect(action.bookmarked, isTrue);
    await action.invoke();

    expect(h.bookmarks.entriesFor(_site), isEmpty);
  });

  test('a signed-out site offers no toggle', () async {
    final h = await _Harness.loaded();
    addTearDown(h.dispose);
    h.connected = false;

    expect(h.bookmarks.actionFor(_page), isNull);
  });

  test('a toggle captured before sign-out writes nothing', () async {
    final h = await _Harness.loaded();
    addTearDown(h.dispose);
    final action = h.bookmarks.actionFor(_page)!;

    h.lifecycle.invalidate(_site);
    final result = await action.invoke();

    expect(result.message, appL10n.bookmarkChangedRefreshMenu);
    expect(h.store.entriesFor(_site, _account), isEmpty);
    expect(h.announced, 0);
  });

  test('a toggle queued behind a write it outlives writes nothing', () async {
    final h = await _Harness.loaded();
    addTearDown(h.dispose);
    final ahead = h.persistence.holdNextWrite();
    final first = h.bookmarks.actionFor(_page)!.invoke();
    await pumpEventQueue();

    final queued = h.bookmarks.actionFor(_category)!.invoke();
    await pumpEventQueue();
    h.lifecycle.invalidate(_site);
    ahead.complete();
    final result = await queued;
    await first;

    expect(result.message, appL10n.bookmarkChangedRefreshMenu);
    expect(
      h.store.entriesFor(_site, _account).map((entry) => entry.route.title),
      ['Preferences'],
    );
  });

  test('a sign-out during the durable write is not announced', () async {
    final h = await _Harness.loaded();
    addTearDown(h.dispose);
    final write = h.persistence.holdNextWrite();

    final toggled = h.bookmarks.actionFor(_page)!.invoke();
    await pumpEventQueue();
    h.lifecycle.invalidate(_site);
    write.complete();

    expect((await toggled).message, appL10n.bookmarkChangedRefreshMenu);
    expect(h.announced, 0);
  });

  test('another account on the same session cannot use the toggle', () async {
    final h = await _Harness.loaded();
    addTearDown(h.dispose);
    final action = h.bookmarks.actionFor(_page)!;

    h.account = 'user:another-reader';
    final result = await action.invoke();

    expect(result.message, appL10n.bookmarkChangedRefreshMenu);
    expect(h.store.entriesFor(_site, _account), isEmpty);
    expect(h.store.entriesFor(_site, 'user:another-reader'), isEmpty);
  });

  test('a toggle outliving its owner writes nothing', () async {
    final h = await _Harness.loaded();
    final action = h.bookmarks.actionFor(_page)!;

    h.dispose();
    final result = await action.invoke();

    expect(result.message, appL10n.bookmarkChangedRefreshMenu);
    expect(h.store.entriesFor(_site, _account), isEmpty);
  });

  test('a store that could not load refuses without announcing', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    final result = await h.bookmarks.actionFor(_page)!.invoke();

    expect(result.message, appL10n.couldNotSaveChanges);
    expect(h.announced, 0);
  });
}

final class _GatedPersistence implements DestinationBookmarksPersistence {
  String? value;
  Completer<void>? _gate;

  Completer<void> holdNextWrite() => _gate = Completer<void>();

  @override
  Future<String?> read() async => value;

  @override
  Future<bool> write(String value) async {
    final gate = _gate;
    _gate = null;
    if (gate != null) await gate.future;
    this.value = value;
    return true;
  }
}

final class _Harness {
  _Harness() {
    bookmarks.addListener(() => announced++);
  }

  static Future<_Harness> loaded() async {
    final harness = _Harness();
    await harness.store.load();
    return harness;
  }

  final persistence = _GatedPersistence();
  late final store = DestinationBookmarksStore(persistence: persistence);
  final lifecycle = SiteLifecycle();
  bool connected = true;
  String account = _account;
  int announced = 0;
  late final bookmarks = AccountDestinationBookmarks(
    store: store,
    lifecycle: lifecycle,
    isConnected: (_) => connected,
    currentSiteUrl: () => _site,
    accountIdentityFor: (_) => account,
  );
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    bookmarks.dispose();
  }
}
