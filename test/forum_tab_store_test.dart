import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    // The shell cannot tell "no tabs stored" from "tabs unreadable": it opens
    // fresh Topics tabs for either, and saves the first time one is touched.
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

    // A retried load that reads clears it, and saving resumes.
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

    final firstSave = store.save([first]);
    await persistence.firstWriteStarted.future;
    final secondSave = store.save([second]);
    final latestSave = store.save([latest]);

    await Future<void>.delayed(Duration.zero);
    expect(persistence.writeCount, 1);
    expect(latestSave, same(secondSave));

    gate.complete();
    await Future.wait([firstSave, secondSave, latestSave]);

    expect(persistence.writeCount, 2);
    expect(await store.load(), [latest]);
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

  test('replacement load waits for an in-flight save', () async {
    final gate = Completer<void>();
    final persistence = _ControlledPersistence(firstWriteGate: gate);
    final oldStore = ForumTabStore(persistence: persistence);
    final replacementStore = ForumTabStore(persistence: persistence);
    final latest = _workspace('latest');

    final saving = oldStore.save([latest]);
    await persistence.firstWriteStarted.future;
    final loading = replacementStore.load();

    await Future<void>.delayed(Duration.zero);
    expect(persistence.readCount, 0);

    gate.complete();
    await saving;

    expect(await loading, [latest]);
    expect(persistence.readCount, 1);
  });
}

ForumWorkspace _workspace(String name) => ForumWorkspace(
  siteUrl: 'https://$name.example',
  accountIdentity: 'user:$name',
  activeTabId: 'tab-$name',
  tabs: [
    ForumTab(
      id: 'tab-$name',
      rootDestinationId: 'latest',
      contentStack: [
        ContentRoute(
          id: 'latest',
          title: 'Topics $name',
          icon: DIcons.layerGroup,
        ),
      ],
    ),
  ],
);

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
