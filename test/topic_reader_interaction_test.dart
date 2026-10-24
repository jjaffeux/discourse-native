import 'dart:async';

import 'package:discourse_native/src/shell/topic_reader_interaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loaded steps select neighbors and include the earlier-page row', () {
    final rig = _Rig();
    addTearDown(rig.owner.dispose);
    rig.navigation.data = _snapshot(hasEarlier: true);
    expect(rig.step(1), isTrue);
    expect(rig.owner.selection.value, 20);
    expect(rig.visible, 20);
    expect(rig.geometry.items, [2]);
    expect(rig.focuses, 1);
    expect(rig.looks, 1);
    expect(rig.step(1), isTrue);
    expect(rig.owner.selection.value, 30);
    expect(rig.step(1), isFalse);
  });

  test('mega navigation uses loaded IDs instead of stream positions', () {
    final rig = _Rig();
    addTearDown(rig.owner.dispose);
    rig.navigation.data = (
      postIds: [10, 30],
      streamIds: [10, 20, 30, 40],
      progressByPostNumber: true,
      hasEarlier: false,
    );
    expect(rig.step(1), isTrue);
    expect(rig.owner.selection.value, 30);
    expect(rig.navigation.hydrated, isEmpty);
    expect(rig.step(1), isFalse);
  });

  test('missing hydration consumes both directions until it settles', () async {
    final rig = _Rig();
    addTearDown(rig.owner.dispose);
    rig.navigation.data = _snapshot(postIds: [10, 30]);
    final loaded = Completer<bool>();
    rig.navigation.hydrate = (_) => loaded.future;
    expect(rig.step(1), isTrue);
    expect(rig.step(1), isTrue);
    expect(rig.step(-1), isTrue);
    expect(rig.navigation.hydrated, [2]);
    expect(rig.owner.selection.value, 20);
    loaded.complete(false);
    await loaded.future;
    expect(rig.owner.selection.value, isNull);
    expect(rig.step(1), isTrue);
    expect(rig.navigation.hydrated, [2, 2]);
  });

  test(
    'manual scrolling clears selection without cancelling hydration',
    () async {
      final rig = _Rig();
      addTearDown(rig.owner.dispose);
      rig.navigation.data = _snapshot(postIds: [10, 30]);
      final loaded = Completer<bool>();
      rig.navigation.hydrate = (_) => loaded.future;
      rig.step(1);
      rig.owner.clearSelection();
      expect(rig.step(-1), isTrue);
      expect(rig.navigation.hydrated, [2]);
      expect(rig.owner.selection.value, isNull);
      loaded.complete(true);
      await loaded.future;
      expect(rig.owner.selection.value, isNull);
    },
  );

  for (final replacement in ['owner', 'session', 'site', 'topic', 'tab']) {
    test(
      '$replacement replacement retires hydration without touching successor',
      () async {
        final rig = _Rig();
        addTearDown(rig.owner.dispose);
        rig.navigation.data = _snapshot(postIds: [10, 30]);
        final loaded = Completer<bool>();
        rig.navigation.hydrate = (_) => loaded.future;
        rig.step(1);
        final identity = rig.navigation.identity;
        final next = _Navigation((
          owner: replacement == 'owner' ? Object() : identity.owner,
          session: replacement == 'session' ? Object() : identity.session,
          siteUrl: replacement == 'site' ? 'other' : identity.siteUrl,
          topicId: replacement == 'topic' ? 2 : identity.topicId,
          tabId: replacement == 'tab' ? 'other' : identity.tabId,
          navigationRevision: identity.navigationRevision,
        ));
        rig.navigation = next;
        rig.owner.bind(next);
        expect(rig.owner.selection.value, isNull);
        rig.step(1);
        expect(rig.owner.selection.value, 20);
        loaded.complete(false);
        await loaded.future;
        expect(rig.owner.selection.value, 20);
      },
    );
  }

  test('tall posts page by unobscured viewport before changing selection', () {
    final rig = _Rig();
    addTearDown(rig.owner.dispose);
    rig.geometry.posts[10] = (top: -10, bottom: 1500, bodyComplete: true);
    expect(rig.step(1), isTrue);
    expect(rig.owner.selection.value, 10);
    expect(rig.geometry.pixels, [550]);
    expect(rig.geometry.items, isEmpty);
    rig.geometry.posts[10] = (top: -10, bottom: 500, bodyComplete: true);
    expect(rig.step(1), isTrue);
    expect(rig.owner.selection.value, 20);
    expect(rig.geometry.items, [1]);
  });

  test('an incomplete visible body consumes a step without scrolling', () {
    final rig = _Rig();
    addTearDown(rig.owner.dispose);
    rig.geometry.posts[10] = (top: 0, bottom: 1000, bodyComplete: false);
    expect(rig.step(1), isTrue);
    expect(rig.owner.selection.value, 10);
    expect(rig.geometry.pixels, isEmpty);
    expect(rig.geometry.items, isEmpty);
  });

  test(
    'backward alignment waits for hydration, restoration and real body height',
    () async {
      final rig = _Rig()..visible = 30;
      addTearDown(rig.owner.dispose);
      rig.navigation.data = _snapshot(postIds: [10, 30]);
      final loaded = Completer<bool>();
      rig.navigation.hydrate = (_) => loaded.future;
      expect(rig.step(-1), isTrue);
      expect(rig.owner.selection.value, 20);
      expect(rig.step(1), isTrue);
      expect(rig.navigation.hydrated, [2]);
      final old = rig.navigation;
      final identity = old.identity;
      final next = _Navigation((
        owner: identity.owner,
        session: identity.session,
        siteUrl: identity.siteUrl,
        topicId: identity.topicId,
        tabId: identity.tabId,
        navigationRevision: 2,
      ));
      rig.navigation = next;
      old.isCurrent = false;
      rig.owner.bind(next);
      loaded.complete(true);
      await loaded.future;
      rig.geometry.posts[20] = (top: 0, bottom: 1500, bodyComplete: false);
      expect(rig.owner.revealPostEnd(), isFalse);
      expect(rig.step(1), isTrue);
      expect(rig.owner.selection.value, 20);
      rig.geometry.posts[20] = (top: 0, bottom: 1500, bodyComplete: true);
      next.restoring = true;
      expect(rig.owner.revealPostEnd(), isFalse);
      next.restoring = false;
      expect(rig.owner.revealPostEnd(), isTrue);
      expect(rig.geometry.pixels, [1100]);
      expect(rig.owner.revealPostEnd(), isFalse);
    },
  );

  test('Home cancels deferred End corrections without clearing selection', () {
    final rig = _Rig();
    addTearDown(rig.owner.dispose);
    rig.step(1);
    rig.owner.jumpToBoundary(end: true);
    expect(rig.geometry.boundary.reveals, 1);
    rig.owner.jumpToBoundary(end: false);
    rig.flushFrames();
    expect(rig.geometry.boundary.edges, [false]);
    expect(rig.owner.selection.value, 20);
  });

  test('End corrects twice and rejects a retired controller', () {
    final rig = _Rig();
    addTearDown(rig.owner.dispose);
    rig.owner.jumpToBoundary(end: true);
    rig.flushFrames();
    expect(rig.geometry.boundary.edges, [true, true]);
    rig.owner.jumpToBoundary(end: true);
    rig.geometry.boundary.isCurrent = false;
    rig.flushFrames();
    expect(rig.geometry.boundary.edges, [true, true]);
  });

  test(
    'day pages back to its earliest post then jumps on two frames',
    () async {
      final rig = _Rig();
      addTearDown(rig.owner.dispose);
      final day = DateTime(2020, 1, 2);
      rig.navigation.days = {10: day, 20: day, 30: day};
      rig.navigation.data = _snapshot(hasEarlier: true);
      rig.navigation.earlier = () async {
        rig.navigation.data = _snapshot(postIds: [1, 10, 20, 30]);
      };
      rig.geometry.leadingItems = 1;
      await rig.owner.jumpToDayStart(day);
      expect(rig.navigation.pages, 1);
      expect(rig.geometry.items, isEmpty);
      rig.flushFrame();
      expect(rig.geometry.items, [2]);
      expect(rig.navigation.finishes, 0);
      rig.flushFrame();
      expect(rig.geometry.items, [2, 2]);
      expect(rig.navigation.finishes, 1);
    },
  );

  test(
    'a refused day page stops and a newer day supersedes old corrections',
    () async {
      final rig = _Rig();
      addTearDown(rig.owner.dispose);
      final day = DateTime(2020, 1, 2);
      final other = DateTime(2020, 1, 3);
      rig.navigation.days = {10: day, 20: other};
      rig.navigation.data = _snapshot(hasEarlier: true);
      await rig.owner.jumpToDayStart(day);
      expect(rig.navigation.pages, 1);
      await rig.owner.jumpToDayStart(other);
      rig.flushFrames();
      expect(rig.geometry.items, [1, 1]);
      expect(rig.navigation.finishes, 1);
    },
  );

  test(
    'day replacement leaves keyboard hydration and boundary corrections admitted',
    () async {
      final rig = _Rig();
      addTearDown(rig.owner.dispose);
      rig.navigation.data = _snapshot(postIds: [10, 30]);
      final loaded = Completer<bool>();
      rig.navigation.hydrate = (_) => loaded.future;
      rig.step(1);
      rig.owner.jumpToBoundary(end: true);
      await rig.owner.jumpToDayStart(DateTime(2020));
      rig.flushFrames();
      expect(rig.geometry.boundary.edges, [true, true]);
      expect(rig.owner.selection.value, 20);
      expect(rig.step(-1), isTrue);
      expect(rig.navigation.hydrated, [2]);
      loaded.complete(true);
      await loaded.future;
    },
  );

  test(
    'a reentrant day jump cannot finish or retire its replacement',
    () async {
      final rig = _Rig();
      addTearDown(rig.owner.dispose);
      final first = DateTime(2020);
      final second = DateTime(2021);
      rig.navigation.days = {10: first, 20: second};
      await rig.owner.jumpToDayStart(first);
      rig.geometry.onJump = () {
        if (rig.geometry.items.length == 2) {
          unawaited(rig.owner.jumpToDayStart(second));
        }
      };
      rig.flushFrame();
      rig.flushFrame();
      expect(rig.navigation.finishes, 0);
      rig.flushFrames();
      expect(rig.geometry.items, [0, 0, 1, 1]);
      expect(rig.navigation.finishes, 1);
    },
  );

  test(
    'a new navigation revision retires day work while retaining cursor',
    () async {
      final rig = _Rig();
      addTearDown(rig.owner.dispose);
      rig.step(1);
      final day = DateTime(2020);
      rig.navigation.days = {10: day};
      rig.navigation.data = _snapshot(hasEarlier: true);
      final page = Completer<void>();
      rig.navigation.earlier = () => page.future;
      final pending = rig.owner.jumpToDayStart(day);
      final identity = rig.navigation.identity;
      rig.navigation.isCurrent = false;
      rig.owner.bind(
        _Navigation((
          owner: identity.owner,
          session: identity.session,
          siteUrl: identity.siteUrl,
          topicId: identity.topicId,
          tabId: identity.tabId,
          navigationRevision: 2,
        )),
      );
      page.complete();
      await pending;
      rig.flushFrames();
      expect(rig.owner.selection.value, 20);
      expect(rig.navigation.finishes, 0);
      expect(rig.geometry.items, [1]);
    },
  );

  for (final retirement in ['binding', 'dispose']) {
    test(
      '$retirement rejects day completion and boundary correction',
      () async {
        final rig = _Rig();
        final day = DateTime(2020);
        rig.navigation.days = {10: day};
        rig.navigation.data = _snapshot(hasEarlier: true);
        final page = Completer<void>();
        rig.navigation.earlier = () => page.future;
        final attempt = rig.owner.jumpToDayStart(day);
        rig.owner.jumpToBoundary(end: true);
        if (retirement == 'dispose') {
          rig.owner.dispose();
        } else {
          addTearDown(rig.owner.dispose);
          rig.navigation.isCurrent = false;
          rig.owner.bind(
            _Navigation((
              owner: Object(),
              session: Object(),
              siteUrl: 'example',
              topicId: 1,
              tabId: 'tab',
              navigationRevision: 2,
            )),
          );
        }
        page.complete();
        await attempt;
        rig.flushFrames();
        expect(rig.navigation.finishes, 0);
        expect(rig.geometry.items, isEmpty);
        expect(rig.geometry.boundary.edges, isEmpty);
      },
    );
  }
}

TopicReaderCommandSnapshot _snapshot({
  List<int> postIds = const [10, 20, 30],
  bool hasEarlier = false,
}) => (
  postIds: postIds,
  streamIds: const [10, 20, 30],
  progressByPostNumber: false,
  hasEarlier: hasEarlier,
);

final class _Rig {
  _Rig() {
    owner = TopicReaderInteraction(
      geometry: geometry,
      postFrame: frames.add,
      scheduleFrame: () {},
      focus: () => focuses++,
      scheduleLook: () => looks++,
    )..bind(navigation);
  }

  late final TopicReaderInteraction owner;
  _Navigation navigation = _Navigation((
    owner: Object(),
    session: Object(),
    siteUrl: 'example',
    topicId: 1,
    tabId: 'tab',
    navigationRevision: 1,
  ));
  final geometry = _Geometry();
  final frames = <void Function()>[];
  int? visible = 10;
  int focuses = 0;
  int looks = 0;

  bool step(int direction) => owner.navigatePost(
    snapshot: navigation.data,
    direction: direction,
    visiblePostId: visible,
    selectVisiblePost: (id) => visible = id,
  );

  void flushFrame() {
    final pending = List.of(frames);
    frames.clear();
    for (final callback in pending) {
      callback();
    }
  }

  void flushFrames() {
    while (frames.isNotEmpty) {
      flushFrame();
    }
  }
}

final class _Navigation implements TopicReaderNavigation {
  _Navigation(this.identity);

  @override
  final TopicReaderCommandIdentity identity;
  @override
  bool isCurrent = true;
  @override
  bool restored = true;
  @override
  bool restoring = false;
  @override
  int? progressPosition = 1;
  TopicReaderCommandSnapshot data = _snapshot();
  @override
  TopicReaderCommandSnapshot get snapshot => data;
  Map<int, DateTime> days = {};
  final hydrated = <int>[];
  Future<bool> Function(int)? hydrate;
  Future<void> Function()? earlier;
  int pages = 0;
  int finishes = 0;

  @override
  Future<bool> hydrateIndex(int index) {
    hydrated.add(index);
    return hydrate?.call(index) ?? Future.value(true);
  }

  @override
  Future<void> loadEarlier() async {
    pages++;
    await earlier?.call();
  }

  @override
  DateTime? dayForPost(int postId) => days[postId];
  @override
  void beginDayJump() {}
  @override
  void finishDayJump() => finishes++;
}

final class _Geometry implements TopicReaderCommandGeometry {
  @override
  TopicReaderCommandScroll? commandScroll = (
    pixels: 100,
    minScrollExtent: 0,
    maxScrollExtent: 3000,
    viewportExtent: 500,
  );
  final posts = <int, TopicReaderCommandPost>{};
  final pixels = <double>[];
  final items = <int>[];
  void Function()? onJump;
  final boundary = _Boundary();
  @override
  int leadingItems = 0;
  @override
  TopicReaderCommandPost? commandPost(int postId) => posts[postId];
  @override
  void jumpToPixels(double value) => pixels.add(value);
  @override
  void jumpToPost(int itemIndex) {
    items.add(itemIndex);
    onJump?.call();
  }

  @override
  TopicReaderCommandBoundary? captureBoundary() => boundary;
}

final class _Boundary implements TopicReaderCommandBoundary {
  @override
  bool isCurrent = true;
  @override
  bool hasItems = true;
  int reveals = 0;
  final edges = <bool>[];
  @override
  void revealLastItem() => reveals++;
  @override
  void jumpToEdge({required bool end}) => edges.add(end);
}
