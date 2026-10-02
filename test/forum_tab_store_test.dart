import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

void main() {
  test('restores the selected forum alongside its tabs', () async {
    final persistence = MemoryForumTabPersistence();
    final first = ForumTabStore(persistence: persistence);
    final workspace = _workspace('selected');
    await first.save([workspace], selectedSiteUrl: workspace.siteUrl);

    final restarted = ForumTabStore(persistence: persistence);
    expect(await restarted.load(), [workspace]);
    expect(restarted.selectedSiteUrl, workspace.siteUrl);

    await restarted.save([]);
    expect(await first.load(), isEmpty);
    expect(first.selectedSiteUrl, isNull);
  });

  test('older documents and malformed selection keep their tabs', () async {
    final persistence = MemoryForumTabPersistence();
    final workspace = _workspace('older');
    final store = ForumTabStore(persistence: persistence);
    for (final selection in [null, 42, '']) {
      persistence.value = jsonEncode({
        'version': ForumTabStore.formatVersion,
        'workspaces': [workspace.toJson()],
        'selectedSiteUrl': selection,
      });
      expect(await store.load(), [workspace]);
      expect(store.selectedSiteUrl, isNull);
    }
  });

  test('an unsupported format version falls back to no workspaces', () async {
    for (final version in [0, ForumTabStore.formatVersion + 1]) {
      final persistence = _ControlledPersistence()
        ..stored = jsonEncode({
          'version': version,
          'workspaces': [_workspace('persisted').toJson()],
        });
      final store = ForumTabStore(persistence: persistence);

      expect(await store.load(), isEmpty, reason: 'version $version');
      expect(persistence.writeCount, 0, reason: 'version $version');
    }
  });

  test('a document that could not be read is never written over', () async {
    final persistence = _ControlledPersistence()
      ..stored = jsonEncode({
        'version': ForumTabStore.formatVersion,
        'workspaces': [_workspace('persisted').toJson()],
      })
      ..readError = StateError('preferences unavailable');
    final store = ForumTabStore(persistence: persistence);

    expect(await store.load(), isEmpty);
    await store.save([_workspace('fresh')]);
    expect(persistence.writeCount, 0);
    expect(
      persistence.stored,
      jsonEncode({
        'version': ForumTabStore.formatVersion,
        'workspaces': [_workspace('persisted').toJson()],
      }),
    );

    persistence.readError = null;
    expect(await store.load(), [_workspace('persisted')]);
    await store.save([_workspace('fresh')]);
    expect(persistence.writeCount, 1);
    expect(await store.load(), [_workspace('fresh')]);
  });

  test('content the reader cannot use is written over', () async {
    final persistence = _ControlledPersistence()..stored = 'not json at all';
    final store = ForumTabStore(persistence: persistence);

    expect(await store.load(), isEmpty);
    await store.save([_workspace('fresh')]);

    expect(persistence.writeCount, 1);
    expect(await store.load(), [_workspace('fresh')]);
  });

  test('overlapping saves coalesce to the latest snapshot', () async {
    final gate = Completer<void>();
    final persistence = _ControlledPersistence(firstWriteGate: gate);
    final store = ForumTabStore(persistence: persistence);
    final first = _workspace('first');
    final second = _workspace('second');
    final latest = _workspace('latest');

    final firstSave = store.save([
      first,
    ], selectedSiteUrl: 'https://first.example');
    await persistence.firstWriteStarted.future;
    final secondSave = store.save([
      second,
    ], selectedSiteUrl: 'https://second.example');
    final latestSave = store.save([
      latest,
    ], selectedSiteUrl: 'https://latest.example');

    await Future<void>.delayed(Duration.zero);
    expect(persistence.writeCount, 1);
    expect(latestSave, same(secondSave));

    gate.complete();
    await Future.wait([firstSave, secondSave, latestSave]);

    expect(persistence.writeCount, 2);
    expect(await store.load(), [latest]);
    expect(store.selectedSiteUrl, 'https://latest.example');
  });

  test('replacement stores preserve request order', () async {
    final gate = Completer<void>();
    final persistence = _ControlledPersistence(firstWriteGate: gate);
    final oldStore = ForumTabStore(persistence: persistence);
    final replacementStore = ForumTabStore(persistence: persistence);

    final oldSave = oldStore.save([_workspace('old')]);
    await persistence.firstWriteStarted.future;
    final replacementSave = replacementStore.save([_workspace('latest')]);

    await Future<void>.delayed(Duration.zero);
    expect(persistence.writeCount, 1);

    gate.complete();
    await Future.wait([oldSave, replacementSave]);

    expect(persistence.writeCount, 2);
    expect(await replacementStore.load(), [_workspace('latest')]);
  });

  test(
    "replacement save wins over an older store's pending snapshot",
    () async {
      final gate = Completer<void>();
      final persistence = _ControlledPersistence(firstWriteGate: gate);
      final oldStore = ForumTabStore(persistence: persistence);
      final replacementStore = ForumTabStore(persistence: persistence);

      final inFlightSave = oldStore.save([_workspace('in-flight')]);
      await persistence.firstWriteStarted.future;
      final staleSave = oldStore.save([_workspace('stale-pending')]);
      final latestSave = replacementStore.save([_workspace('latest')]);

      await Future<void>.delayed(Duration.zero);
      expect(persistence.writeCount, 1);

      gate.complete();
      await Future.wait([inFlightSave, staleSave, latestSave]);

      expect(persistence.writeCount, 2);
      expect(await replacementStore.load(), [_workspace('latest')]);
    },
  );

  test(
    'replacement load waits for an in-flight and locally pending save',
    () async {
      final gate = Completer<void>();
      final persistence = _ControlledPersistence(firstWriteGate: gate);
      final oldStore = ForumTabStore(persistence: persistence);
      final replacementStore = ForumTabStore(persistence: persistence);
      final latest = _workspace('latest');

      final inFlightSave = oldStore.save([_workspace('in-flight')]);
      await persistence.firstWriteStarted.future;
      final latestSave = oldStore.save([latest]);
      final loading = replacementStore.load();

      await Future<void>.delayed(Duration.zero);
      expect(persistence.readCount, 0);

      gate.complete();
      await Future.wait([inFlightSave, latestSave]);

      expect(await loading, [latest]);
      expect(persistence.readCount, 1);
      expect(persistence.writeCount, 2);
    },
  );

  test(
    'a snapshot superseded before its write starts is never encoded',
    () async {
      // Visits save at once and scrolling every 500 ms, faster than a long
      // history is written, so encoding at each save is mostly discarded work.
      final gate = Completer<void>();
      final persistence = _ControlledPersistence(firstWriteGate: gate);
      final store = ForumTabStore(persistence: persistence);
      final serialized = <String>[];
      ForumWorkspace counted(String name) =>
          _workspace(name, route: _CountedRoute(serialized, name));

      final inFlightSave = store.save([counted('in-flight')]);
      await persistence.firstWriteStarted.future;
      final pendingSaves = [
        for (var save = 0; save < 20; save++)
          store.save([counted('save $save')]),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(serialized, ['in-flight']);

      gate.complete();
      // A quit awaits the newest save, so resolving must mean it is written.
      await pendingSaves.last;
      expect(serialized, ['in-flight', 'save 19']);
      expect(persistence.writeCount, 2);
      expect(persistence.stored, _document([counted('save 19')]));
      await inFlightSave;
    },
  );

  test(
    'the saved document is jsonEncode of the workspaces, byte for byte',
    () async {
      final random = Random(7);
      var workspaces = _generatedWorkspaces(random);
      expect(ForumTabStore.encode(workspaces), _document(workspaces));

      // Each edit replaces one tab or workspace and keeps the rest, so every
      // document mixes fresh encodings with ones kept from earlier documents.
      for (var edit = 0; edit < 300; edit++) {
        workspaces = _edited(workspaces, random);
        expect(
          ForumTabStore.encode(workspaces),
          _document(workspaces),
          reason: 'after edit $edit',
        );
      }

      final persistence = MemoryForumTabPersistence();
      await ForumTabStore(persistence: persistence).save(workspaces);
      expect(persistence.value, _document(workspaces));
    },
  );

  test('a save encodes only the tabs and history entries that changed', () {
    final serialized = <String>[];
    ContentRoute route(String id, {String? title}) =>
        _CountedRoute(serialized, id, title: title);
    ForumTab tab(String id) => ForumTab(
      id: id,
      rootDestinationId: 'latest',
      contentStack: [route('$id root'), route('$id current')],
      backHistory: [
        for (var visit = 0; visit < 10; visit++)
          ForumTabLocation(
            rootDestinationId: 'latest',
            contentStack: [route('$id root'), route('$id visit $visit')],
          ),
      ],
    );
    var workspaces = [
      for (final forum in ['a', 'b'])
        ForumWorkspace(
          siteUrl: 'https://$forum.example',
          accountIdentity: 'user:1',
          activeTabId: '${forum}0',
          tabs: [for (var index = 0; index < 3; index++) tab('$forum$index')],
        ),
    ];
    List<String> encodedAfter(ForumTab replacement) {
      workspaces = [
        for (final workspace in workspaces)
          workspace.copyWith(
            tabs: [
              for (final tab in workspace.tabs)
                tab.id == replacement.id ? replacement : tab,
            ],
          ),
      ];
      serialized.clear();
      final document = ForumTabStore.encode(workspaces);
      final encoded = List.of(serialized);
      expect(document, _document(workspaces));
      return encoded;
    }

    ForumTabStore.encode(workspaces);

    final scrolled = workspaces.first.tabById('a1')!;
    expect(
      encodedAfter(
        scrolled.copyWith(
          anchors: {
            'a1 current': const ForumTabAnchor(kind: 'topic', itemId: 9),
          },
        ),
      ),
      ['a1 root', 'a1 current'],
    );

    final visited = workspaces.last.tabById('b0')!;
    expect(
      encodedAfter(visited.push(route('b0 next'))),
      unorderedEquals([
        ...['b0 root', 'b0 current', 'b0 next'],
        ...['b0 root', 'b0 current'],
      ]),
    );

    final retitled = workspaces.first.tabById('a2')!;
    expect(
      encodedAfter(
        retitled.rewriteRoutes(
          (existing) => existing.id == 'a2 visit 3'
              ? route(existing.id, title: 'Renamed')
              : existing,
        ),
      ),
      unorderedEquals([
        ...['a2 root', 'a2 current'],
        ...['a2 root', 'a2 visit 3'],
      ]),
    );
  });

  test('a moved scroll anchor costs a fraction of encoding every tab', () {
    // Timed because what matters is how much is encoded: a scrolled list
    // saves every 500 ms, and history accumulates across launches.
    for (final forums in [1, 4]) {
      var workspaces = _longSession(forums: forums, tabs: 8);
      var row = 0;
      ForumTabStore.encode(workspaces);
      final (
        small: everyTab,
        large: movedAnchor,
      ) = measureScaling(() => _document(workspaces).length, () {
        final workspace = workspaces.first;
        final tab = workspace.tabs.first;
        final moved = tab.copyWith(
          anchors: {
            ...tab.anchors,
            tab.currentContent.id: ForumTabAnchor(kind: 'topic', itemId: ++row),
          },
        );
        workspaces = [
          workspace.copyWith(tabs: [moved, ...workspace.tabs.skip(1)]),
          ...workspaces.skip(1),
        ];
        return ForumTabStore.encode(workspaces).length;
      });
      expect(
        movedAnchor,
        lessThan(everyTab / 4),
        reason:
            'one moved anchor cost ${movedAnchor / everyTab} of encoding '
            '$forums forums',
      );
    }
  });
}

String _document(Iterable<ForumWorkspace> workspaces) => jsonEncode({
  'version': ForumTabStore.formatVersion,
  'workspaces': [for (final workspace in workspaces) workspace.toJson()],
});

ForumWorkspace _workspace(String name, {ContentRoute? route}) => ForumWorkspace(
  siteUrl: 'https://$name.example',
  accountIdentity: 'user:$name',
  activeTabId: 'tab-$name',
  tabs: [
    ForumTab(
      id: 'tab-$name',
      rootDestinationId: 'latest',
      contentStack: [
        route ??
            ContentRoute(
              id: 'latest',
              title: 'Topics $name',
              icon: DIcons.layerGroup,
            ),
      ],
    ),
  ],
);

/// Records its id each time it is serialized.
final class _CountedRoute extends ContentRoute {
  const _CountedRoute(this.serialized, String id, {String? title})
    : super(id: id, title: title ?? id, icon: DIcons.layerGroup);

  final List<String> serialized;

  @override
  Map<String, Object?> toJson() {
    serialized.add(id);
    return super.toJson();
  }
}

/// Tabs as a long desktop session leaves them: every tab at its history bound,
/// with a scroll anchor on each visited topic.
List<ForumWorkspace> _longSession({required int forums, required int tabs}) {
  ContentRoute topic(int id) => ContentRoute.topic(
    topicId: id,
    slug: 'a-reasonably-long-topic-slug-$id',
    title: 'A reasonably long topic title about something $id',
    postNumber: 12,
  );
  final latest = ContentRoute.topicList(TopicListMode.latest);
  const visits = ForumTab.maximumHistoryEntries;
  return [
    for (var forum = 0; forum < forums; forum++)
      ForumWorkspace(
        siteUrl: 'https://forum$forum.example',
        accountIdentity: 'user:1',
        activeTabId: 'tab-0',
        tabs: [
          for (var tab = 0; tab < tabs; tab++)
            ForumTab(
              id: 'tab-$tab',
              rootDestinationId: 'latest',
              contentStack: [latest, topic(tab * 1000 + visits)],
              backHistory: [
                for (var visit = 0; visit < visits; visit++)
                  ForumTabLocation(
                    rootDestinationId: 'latest',
                    contentStack: [latest, topic(tab * 1000 + visit)],
                  ),
              ],
              anchors: {
                for (var visit = 0; visit < visits; visit++)
                  topic(tab * 1000 + visit).id: ForumTabAnchor(
                    kind: 'topic',
                    itemId: visit,
                    offset: 12.5,
                  ),
              },
            ),
        ],
      ),
  ];
}

/// What JSON escapes and what hand assembly could mangle: quotes,
/// backslashes, control characters, separators, line separators, and text
/// outside ASCII, including an astral character and a lone surrogate.
const List<String> _awkwardUnits = [
  '"',
  r'\',
  '/',
  '\n',
  '\t',
  '\u0000',
  '\u001f',
  '\u007f',
  ' ',
  'é',
  '漢',
  '🧵',
  '\ud800',
  '{',
  '}',
  '[',
  ']',
  ',',
  ':',
  ' ',
  'a',
];

const List<double> _offsets = [0, 0.5, -3.25, 1e21, 1e-7, 5e-324, 123456.789];

String _awkward(Random random) => [
  for (var unit = random.nextInt(6); unit >= 0; unit--)
    _awkwardUnits[random.nextInt(_awkwardUnits.length)],
].join();

ContentRoute _route(Random random) => switch (random.nextInt(3)) {
  0 => ContentRoute.topic(
    topicId: random.nextInt(40),
    slug: _awkward(random),
    title: _awkward(random),
    subtitle: random.nextBool() ? _awkward(random) : null,
    color: random.nextBool() ? Color(random.nextInt(1 << 32)) : null,
    postNumber: random.nextBool() ? random.nextInt(900) : null,
  ),
  1 => ContentRoute(
    id: 'list-${random.nextInt(40)}',
    title: _awkward(random),
    icon: DIcons.tag,
    feedPath: '/c/${_awkward(random)}.json',
  ),
  _ => ContentRoute(
    id: _awkward(random),
    title: _awkward(random),
    icon: DIcons.layerGroup,
  ),
};

List<ContentRoute> _stack(Random random) => [
  for (var route = random.nextInt(3); route >= 0; route--) _route(random),
];

ForumTabAnchor _anchor(Random random) => ForumTabAnchor(
  kind: _awkward(random),
  itemId: random.nextInt(1000),
  offset: _offsets[random.nextInt(_offsets.length)],
);

ForumTab _tab(Random random, String id) {
  ForumTabLocation location() => ForumTabLocation(
    rootDestinationId: _awkward(random),
    contentStack: _stack(random),
  );
  final contentStack = _stack(random);
  return ForumTab(
    id: id,
    rootDestinationId: _awkward(random),
    panel: random.nextBool() ? ForumPanel.main : ForumPanel.secondary,
    contentStack: contentStack,
    backHistory: [
      for (var entry = random.nextInt(8); entry > 0; entry--) location(),
    ],
    forwardHistory: [
      for (var entry = random.nextInt(4); entry > 0; entry--) location(),
    ],
    anchors: {
      for (final route in contentStack)
        if (random.nextBool()) route.id: _anchor(random),
    },
  );
}

List<ForumWorkspace> _generatedWorkspaces(Random random) => [
  for (var forum = 0; forum < 3; forum++) _generatedWorkspace(random, forum),
];

ForumWorkspace _generatedWorkspace(Random random, int forum) {
  final tabs = [
    for (var index = random.nextInt(4); index >= 0; index--)
      _tab(random, '$index ${_awkward(random)}'),
  ];
  return ForumWorkspace(
    siteUrl: 'https://$forum.example/${_awkward(random)}',
    accountIdentity: _awkward(random),
    tabs: tabs,
    activeTabId: tabs[random.nextInt(tabs.length)].id,
  );
}

List<ForumWorkspace> _edited(List<ForumWorkspace> workspaces, Random random) {
  final workspace = workspaces[random.nextInt(workspaces.length)];
  final tab = workspace.tabs[random.nextInt(workspace.tabs.length)];
  ForumWorkspace replaced(ForumTab replacement) => workspace.copyWith(
    tabs: [
      for (final existing in workspace.tabs)
        existing.id == replacement.id ? replacement : existing,
    ],
  );
  final edited = switch (random.nextInt(7)) {
    0 => replaced(
      tab.copyWith(
        anchors: {...tab.anchors, tab.currentContent.id: _anchor(random)},
      ),
    ),
    1 => replaced(tab.push(_route(random))),
    2 => replaced(tab.goBack()),
    3 => replaced(tab.goForward()),
    4 => replaced(
      tab.rewriteRoutes(
        (route) => route.id == tab.currentContent.id
            ? ContentRoute(
                id: route.id,
                title: _awkward(random),
                icon: route.icon,
              )
            : route,
      ),
    ),
    5 => replaced(
      tab.copyWith(
        panel: tab.panel == ForumPanel.main
            ? ForumPanel.secondary
            : ForumPanel.main,
      ),
    ),
    _ => workspace.copyWith(activeTabId: tab.id),
  };
  return [
    for (final existing in workspaces)
      identical(existing, workspace) ? edited : existing,
  ];
}

final class _ControlledPersistence implements ForumTabPersistence {
  _ControlledPersistence({this.firstWriteGate});

  final Completer<void>? firstWriteGate;
  final Completer<void> firstWriteStarted = Completer<void>();

  String? stored;
  Object? readError;
  int readCount = 0;
  int writeCount = 0;

  @override
  Future<String?> read() async {
    readCount++;
    if (readError case final error?) throw error;
    return stored;
  }

  @override
  Future<bool> write(String value) async {
    writeCount++;
    if (writeCount == 1) {
      firstWriteStarted.complete();
      await firstWriteGate?.future;
    }
    stored = value;
    return true;
  }
}
