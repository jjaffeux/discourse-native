import 'dart:async';

import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads once and exposes the stored settings', () async {
    final persistence = _ControlledAppSettingsPersistence(
      contentAlignment: 'left',
      disableGifAnimations: true,
    );
    final controller = _controller(persistence);
    var notifications = 0;
    controller.addListener(() => notifications++);

    final first = controller.load();
    final second = controller.load();

    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    await controller.load();

    expect(controller.loaded, isTrue);
    expect(
      controller.settings,
      const AppSettings(
        contentAlignment: ContentAlignment.left,
        disableGifAnimations: true,
      ),
    );
    expect(controller.contentAlignment, ContentAlignment.left);
    expect(controller.disableGifAnimations, isTrue);
    expect(persistence.readCount, 1);
    expect(notifications, 1);
  });

  test('a local selection wins over a stale hydration read', () async {
    final readGate = Completer<void>();
    final persistence = _ControlledAppSettingsPersistence(
      contentAlignment: 'left',
      readGate: readGate,
    );
    final controller = _controller(persistence);

    final loading = controller.load();
    await persistence.readStarted.future;
    final saving = controller.setContentAlignment(ContentAlignment.right);

    expect(controller.loaded, isTrue);
    expect(controller.contentAlignment, ContentAlignment.right);

    readGate.complete();
    await Future.wait([loading, saving]);

    expect(controller.contentAlignment, ContentAlignment.right);
    expect(persistence.contentAlignment, 'right');
  });

  test(
    'choosing the initial default still supersedes a pending read',
    () async {
      final readGate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        contentAlignment: 'left',
        readGate: readGate,
      );
      final controller = _controller(persistence);

      final loading = controller.load();
      await persistence.readStarted.future;
      final saving = controller.setContentAlignment(ContentAlignment.center);

      readGate.complete();
      await Future.wait([loading, saving]);

      expect(controller.contentAlignment, ContentAlignment.center);
      expect(persistence.contentAlignment, 'center');
      expect(persistence.attemptedWrites, ['center']);
    },
  );

  test(
    'rapid selections notify optimistically and persist the last value',
    () async {
      final firstWriteGate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        firstWriteGate: firstWriteGate,
      );
      final controller = _controller(persistence);
      var notifications = 0;
      controller.addListener(() => notifications++);

      final savingLeft = controller.setContentAlignment(ContentAlignment.left);
      await persistence.firstWriteStarted.future;
      final savingRight = controller.setContentAlignment(
        ContentAlignment.right,
      );

      expect(controller.contentAlignment, ContentAlignment.right);
      expect(notifications, 2);
      expect(persistence.attemptedWrites, ['left']);

      firstWriteGate.complete();
      await Future.wait([savingLeft, savingRight]);

      expect(persistence.attemptedWrites, ['left', 'right']);
      expect(persistence.contentAlignment, 'right');

      await controller.setContentAlignment(ContentAlignment.right);
      expect(persistence.attemptedWrites, ['left', 'right']);
      expect(notifications, 2);
    },
  );

  test('a rejected write retains the optimistic session choice', () async {
    final persistence = _ControlledAppSettingsPersistence(acceptWrites: false);
    final controller = _controller(persistence);

    await controller.setContentAlignment(ContentAlignment.right);

    expect(controller.loaded, isTrue);
    expect(controller.contentAlignment, ContentAlignment.right);
    expect(persistence.contentAlignment, isNull);
    expect(persistence.attemptedWrites, ['right']);
  });

  test('updates the GIF animation preference optimistically', () async {
    final persistence = _ControlledAppSettingsPersistence();
    final controller = _controller(persistence);

    await controller.setDisableGifAnimations(true);

    expect(controller.loaded, isTrue);
    expect(controller.disableGifAnimations, isTrue);
    expect(persistence.disableGifAnimations, isTrue);
    expect(persistence.attemptedGifAnimationWrites, [true]);
  });

  test('a replacement controller retains a rejected session choice', () async {
    final persistence = _ControlledAppSettingsPersistence(acceptWrites: false);
    final store = AppSettingsStore(persistence: persistence);
    final first = AppSettingsController(store: store);

    await first.setContentAlignment(ContentAlignment.right);
    first.dispose();

    final replacement = AppSettingsController(store: store);
    addTearDown(replacement.dispose);
    await replacement.load();

    expect(replacement.contentAlignment, ContentAlignment.right);
    expect(persistence.contentAlignment, isNull);
    expect(persistence.attemptedWrites, ['right']);
    expect(persistence.readCount, 0);
  });

  test('replacement controllers cannot reorder rapid writes', () async {
    final firstWriteGate = Completer<void>();
    final persistence = _ControlledAppSettingsPersistence(
      firstWriteGate: firstWriteGate,
    );
    final first = _controller(persistence, dispose: false);
    final replacement = _controller(persistence);

    final savingLeft = first.setContentAlignment(ContentAlignment.left);
    await persistence.firstWriteStarted.future;
    final savingRight = replacement.setContentAlignment(ContentAlignment.right);

    expect(persistence.attemptedWrites, ['left']);
    first.dispose();
    firstWriteGate.complete();
    await Future.wait([savingLeft, savingRight]);

    expect(persistence.attemptedWrites, ['left', 'right']);
    expect(persistence.contentAlignment, 'right');
    expect(replacement.contentAlignment, ContentAlignment.right);
  });

  test('dispose ignores a late read and rejects later selections', () async {
    final readGate = Completer<void>();
    final persistence = _ControlledAppSettingsPersistence(
      contentAlignment: 'left',
      readGate: readGate,
    );
    final controller = _controller(persistence, dispose: false);

    final loading = controller.load();
    await persistence.readStarted.future;
    controller.dispose();
    readGate.complete();
    await loading;
    await controller.setContentAlignment(ContentAlignment.right);

    expect(controller.loaded, isFalse);
    expect(controller.contentAlignment, ContentAlignment.center);
    expect(persistence.attemptedWrites, isEmpty);
  });
}

AppSettingsController _controller(
  AppSettingsPersistence persistence, {
  bool dispose = true,
}) {
  final controller = AppSettingsController(
    store: AppSettingsStore(persistence: persistence),
  );
  if (dispose) addTearDown(controller.dispose);
  return controller;
}

final class _ControlledAppSettingsPersistence
    implements AppSettingsPersistence {
  _ControlledAppSettingsPersistence({
    this.contentAlignment,
    this.disableGifAnimations,
    this.readGate,
    this.firstWriteGate,
    this.acceptWrites = true,
  });

  String? contentAlignment;
  bool? disableGifAnimations;
  final Completer<void>? readGate;
  final Completer<void>? firstWriteGate;
  final bool acceptWrites;
  final Completer<void> readStarted = Completer<void>();
  final Completer<void> firstWriteStarted = Completer<void>();
  final List<String> attemptedWrites = [];
  final List<bool> attemptedGifAnimationWrites = [];
  int readCount = 0;

  @override
  Future<String?> readContentAlignment() async {
    readCount++;
    final value = contentAlignment;
    if (!readStarted.isCompleted) readStarted.complete();
    await readGate?.future;
    return value;
  }

  @override
  Future<bool?> readDisableGifAnimations() async => disableGifAnimations;

  @override
  Future<bool> writeContentAlignment(String value) async {
    attemptedWrites.add(value);
    if (attemptedWrites.length == 1) {
      firstWriteStarted.complete();
      await firstWriteGate?.future;
    }
    if (!acceptWrites) return false;
    contentAlignment = value;
    return true;
  }

  @override
  Future<bool> writeDisableGifAnimations(bool value) async {
    attemptedGifAnimationWrites.add(value);
    if (!acceptWrites) return false;
    disableGifAnimations = value;
    return true;
  }
}
