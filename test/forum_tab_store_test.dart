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
  int writeCount = 0;

  @override
  Future<String?> read() async => stored;

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
