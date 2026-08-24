import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/composer_geometry_store.dart';
import 'package:discourse_native/src/data/diagnostics_panel_width_store.dart';
import 'package:discourse_native/src/data/serial_operation_queue.dart';
import 'package:discourse_native/src/data/sidebar_section_store.dart';
import 'package:discourse_native/src/data/sidebar_width_store.dart';
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

  test('composer geometry persists the latest requested preference', () async {
    final persistence = _ControlledComposerGeometryPersistence();
    final firstStore = ComposerGeometryStore(persistence: persistence);
    final replacementStore = ComposerGeometryStore(persistence: persistence);

    final firstWrite = firstStore.write(_geometry(width: 640));
    await persistence.firstWriteStarted.future;
    final secondWrite = replacementStore.write(_geometry(width: 720));
    final replacementRead = replacementStore.read();
    await Future<void>.delayed(Duration.zero);

    expect(persistence.attemptedWidths, [640]);
    expect(persistence.reads, 0);

    persistence.finishFirstWrite.complete();
    await Future.wait([firstWrite, secondWrite]);

    expect(persistence.attemptedWidths, [640, 720]);
    expect(persistence.persistedWidth, 720);
    expect((await replacementRead)?.width, 720);
    expect(persistence.reads, 1);
  });

  test('diagnostics width persists across replacement in order', () async {
    final persistence = _ControlledDiagnosticsWidthPersistence();
    final firstStore = DiagnosticsPanelWidthStore(persistence: persistence);
    final replacementStore = DiagnosticsPanelWidthStore(
      persistence: persistence,
    );

    final firstWrite = firstStore.write(480);
    await persistence.firstWriteStarted.future;
    final secondWrite = replacementStore.write(560);
    final replacementRead = replacementStore.read();
    await Future<void>.delayed(Duration.zero);

    expect(persistence.attemptedWidths, [480]);
    expect(persistence.reads, 0);

    persistence.finishFirstWrite.complete();
    await Future.wait([firstWrite, secondWrite]);

    expect(persistence.attemptedWidths, [480, 560]);
    expect(persistence.persistedWidth, 560);
    expect(await replacementRead, 560);
    expect(persistence.reads, 1);
  });

  test('sidebar width persists across replacement in order', () async {
    final persistence = _ControlledSidebarWidthPersistence();
    final firstStore = SidebarWidthStore(persistence: persistence);
    final replacementStore = SidebarWidthStore(persistence: persistence);

    final firstWrite = firstStore.write(320);
    await persistence.firstWriteStarted.future;
    final secondWrite = replacementStore.write(360);
    final replacementRead = replacementStore.read();
    await Future<void>.delayed(Duration.zero);

    expect(persistence.attemptedWidths, [320]);
    expect(persistence.reads, 0);

    persistence.finishFirstWrite.complete();
    await Future.wait([firstWrite, secondWrite]);

    expect(persistence.attemptedWidths, [320, 360]);
    expect(persistence.persistedWidth, 360);
    expect(await replacementRead, 360);
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

ComposerGeometryPreference _geometry({required double width}) =>
    ComposerGeometryPreference(
      width: width,
      height: 320,
      horizontalPosition: 0.5,
      verticalPosition: 1,
    );

final class _ControlledComposerGeometryPersistence
    implements ComposerGeometryPersistence {
  final firstWriteStarted = Completer<void>();
  final finishFirstWrite = Completer<void>();
  final List<double> attemptedWidths = [];
  double? persistedWidth;
  int reads = 0;

  @override
  Future<String?> readGeometry() async {
    reads++;
    final width = persistedWidth;
    return width == null ? null : jsonEncode(_geometry(width: width).toJson());
  }

  @override
  Future<bool> writeGeometry(String encoded) async {
    final preference = ComposerGeometryPreference.fromJson(
      jsonDecode(encoded),
    )!;
    attemptedWidths.add(preference.width);
    if (attemptedWidths.length == 1) {
      firstWriteStarted.complete();
      await finishFirstWrite.future;
    }
    persistedWidth = preference.width;
    return true;
  }
}

final class _ControlledDiagnosticsWidthPersistence
    implements DiagnosticsPanelWidthPersistence {
  final firstWriteStarted = Completer<void>();
  final finishFirstWrite = Completer<void>();
  final List<double> attemptedWidths = [];
  double? persistedWidth;
  int reads = 0;

  @override
  Future<double?> readWidth() async {
    reads++;
    return persistedWidth;
  }

  @override
  Future<bool> writeWidth(double width) async {
    attemptedWidths.add(width);
    if (attemptedWidths.length == 1) {
      firstWriteStarted.complete();
      await finishFirstWrite.future;
    }
    persistedWidth = width;
    return true;
  }
}

final class _ControlledSidebarWidthPersistence
    implements SidebarWidthPersistence {
  final firstWriteStarted = Completer<void>();
  final finishFirstWrite = Completer<void>();
  final List<double> attemptedWidths = [];
  double? persistedWidth;
  int reads = 0;

  @override
  Future<double?> readWidth() async {
    reads++;
    return persistedWidth;
  }

  @override
  Future<bool> writeWidth(double width) async {
    attemptedWidths.add(width);
    if (attemptedWidths.length == 1) {
      firstWriteStarted.complete();
      await finishFirstWrite.future;
    }
    persistedWidth = width;
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
