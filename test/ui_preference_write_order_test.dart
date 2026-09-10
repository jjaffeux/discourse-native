import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/composer_layout_store.dart';
import 'package:discourse_native/src/data/serial_operation_queue.dart';
import 'package:discourse_native/src/data/sidebar_section_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'queue continues after failure and leaves other keys independent',
    () async {
      final queue = SerialOperationQueue();
      final owner = Object();
      final firstStarted = Completer<void>();
      final finishFirst = Completer<void>();
      final first = queue.run<void>(
        owner: owner,
        key: 'shared',
        operation: () async {
          firstStarted.complete();
          await finishFirst.future;
          throw StateError('first failed');
        },
      );
      final firstFailure = expectLater(first, throwsStateError);
      await firstStarted.future;

      final second = queue.run<int>(
        owner: owner,
        key: 'shared',
        operation: () async => 2,
      );
      final independent = queue.run<int>(
        owner: owner,
        key: 'independent',
        operation: () async => 3,
      );

      expect(await independent, 3);
      var secondFinished = false;
      unawaited(second.then<void>((_) => secondFinished = true));
      await Future<void>.delayed(Duration.zero);
      expect(secondFinished, isFalse);

      finishFirst.complete();
      await firstFailure;
      expect(await second, 2);
    },
  );

  test('composer layout persists the latest requested preference', () async {
    final persistence = _ControlledComposerLayoutPersistence();
    final firstStore = ComposerLayoutStore(persistence: persistence);
    final replacementStore = ComposerLayoutStore(persistence: persistence);

    final firstWrite = firstStore.write(_layout(sideWidth: 640));
    await persistence.firstWriteStarted.future;
    final secondWrite = replacementStore.write(_layout(sideWidth: 720));
    final replacementRead = replacementStore.read();
    await Future<void>.delayed(Duration.zero);

    expect(persistence.attemptedWidths, [640]);
    expect(persistence.reads, 0);

    persistence.finishFirstWrite.complete();
    await Future.wait([firstWrite, secondWrite]);

    expect(persistence.attemptedWidths, [640, 720]);
    expect(persistence.persistedWidth, 720);
    expect((await replacementRead).sideWidth, 720);
    expect(persistence.reads, 1);
  });

  test('sidebar section persists the latest requested state', () async {
    final persistence = _ControlledSidebarSectionPersistence();
    final store = SidebarSectionStore(persistence: persistence);
    final replacementStore = SidebarSectionStore(persistence: persistence);

    final firstWrite = store.write(
      siteUrl: 'https://meta.discourse.org',
      sectionId: 'community',
      collapsed: true,
    );
    await persistence.firstWriteStarted.future;
    final secondWrite = store.write(
      siteUrl: 'https://meta.discourse.org',
      sectionId: 'community',
      collapsed: false,
    );
    final replacementRead = replacementStore.read(
      siteUrl: 'https://meta.discourse.org',
      sectionId: 'community',
    );
    await Future<void>.delayed(Duration.zero);

    expect(persistence.attemptedStates, [true]);
    expect(persistence.reads, 0);

    persistence.finishFirstWrite.complete();
    await Future.wait([firstWrite, secondWrite]);

    expect(persistence.attemptedStates, [true, false]);
    expect(persistence.persistedState, isFalse);
    expect(await replacementRead, isFalse);
    expect(persistence.reads, 1);
  });
}

ComposerLayoutPreference _layout({required double sideWidth}) =>
    ComposerLayoutPreference(sideWidth: sideWidth);

final class _ControlledComposerLayoutPersistence
    implements ComposerLayoutPersistence {
  final firstWriteStarted = Completer<void>();
  final finishFirstWrite = Completer<void>();
  final List<double> attemptedWidths = [];
  double? persistedWidth;
  int reads = 0;

  @override
  Future<String?> readLayout() async {
    reads++;
    final width = persistedWidth;
    return width == null
        ? null
        : jsonEncode(_layout(sideWidth: width).toJson());
  }

  @override
  Future<bool> writeLayout(String encoded) async {
    final preference = ComposerLayoutPreference.fromJson(jsonDecode(encoded))!;
    attemptedWidths.add(preference.sideWidth);
    if (attemptedWidths.length == 1) {
      firstWriteStarted.complete();
      await finishFirstWrite.future;
    }
    persistedWidth = preference.sideWidth;
    return true;
  }
}

final class _ControlledSidebarSectionPersistence
    implements SidebarSectionPersistence {
  final firstWriteStarted = Completer<void>();
  final finishFirstWrite = Completer<void>();
  final List<bool> attemptedStates = [];
  bool? persistedState;
  int reads = 0;

  @override
  Future<bool?> readCollapsed({
    required String siteUrl,
    required String sectionId,
  }) async {
    reads++;
    return persistedState;
  }

  @override
  Future<bool> writeCollapsed({
    required String siteUrl,
    required String sectionId,
    required bool collapsed,
  }) async {
    attemptedStates.add(collapsed);
    if (attemptedStates.length == 1) {
      firstWriteStarted.complete();
      await finishFirstWrite.future;
    }
    persistedState = collapsed;
    return true;
  }
}
