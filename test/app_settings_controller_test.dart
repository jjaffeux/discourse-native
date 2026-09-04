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
      textScale: AppTextScale.percent125.name,
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
        textScale: AppTextScale.percent125,
      ),
    );
    expect(controller.contentAlignment, ContentAlignment.left);
    expect(controller.disableGifAnimations, isTrue);
    expect(controller.textScale, AppTextScale.percent125);
    expect(controller.textScaleFactor, 1.25);
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

  test('a local text scale wins over a stale hydration read', () async {
    final readGate = Completer<void>();
    final persistence = _ControlledAppSettingsPersistence(
      textScale: AppTextScale.percent175.name,
      readGate: readGate,
    );
    final controller = _controller(persistence);

    final loading = controller.load();
    await persistence.readStarted.future;
    final saving = controller.setTextScale(AppTextScale.percent90);

    expect(controller.loaded, isTrue);
    expect(controller.textScale, AppTextScale.percent90);
    expect(controller.textScaleFactor, 0.9);

    readGate.complete();
    await Future.wait([loading, saving]);

    expect(controller.textScale, AppTextScale.percent90);
    expect(persistence.textScale, AppTextScale.percent90.name);
  });

  test('resetting before hydration supersedes a stored text scale', () async {
    final readGate = Completer<void>();
    final persistence = _ControlledAppSettingsPersistence(
      textScale: AppTextScale.percent175.name,
      readGate: readGate,
    );
    final controller = _controller(persistence);

    final loading = controller.load();
    await persistence.readStarted.future;
    final saving = controller.resetTextScale();

    readGate.complete();
    await Future.wait([loading, saving]);

    expect(controller.textScale, AppTextScale.percent100);
    expect(persistence.attemptedTextScaleWrites, [
      AppTextScale.percent100.name,
    ]);
  });

  test(
    'relative text changes hydrate before writing the settings snapshot',
    () async {
      final readGate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        contentAlignment: ContentAlignment.left.name,
        disableGifAnimations: true,
        textScale: AppTextScale.percent125.name,
        readGate: readGate,
      );
      final controller = _controller(persistence);

      final firstIncrease = controller.increaseTextScale();
      final secondIncrease = controller.increaseTextScale();
      await persistence.readStarted.future;

      expect(controller.loaded, isFalse);
      expect(persistence.attemptedTextScaleWrites, isEmpty);

      readGate.complete();
      await Future.wait([firstIncrease, secondIncrease]);

      expect(
        controller.settings,
        const AppSettings(
          contentAlignment: ContentAlignment.left,
          disableGifAnimations: true,
          textScale: AppTextScale.percent175,
        ),
      );
      expect(persistence.contentAlignment, ContentAlignment.left.name);
      expect(persistence.disableGifAnimations, isTrue);
      expect(persistence.attemptedTextScaleWrites, [
        AppTextScale.percent150.name,
        AppTextScale.percent175.name,
      ]);
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

  test('adjusts and resets text scale one bounded step at a time', () async {
    final persistence = _ControlledAppSettingsPersistence();
    final controller = _controller(persistence);

    await controller.increaseTextScale();
    expect(controller.textScale, AppTextScale.percent110);
    expect(controller.textScaleFactor, 1.1);

    await controller.increaseTextScale();
    expect(controller.textScale, AppTextScale.percent125);

    await controller.decreaseTextScale();
    expect(controller.textScale, AppTextScale.percent110);

    await controller.resetTextScale();
    expect(controller.textScale, AppTextScale.percent100);
    expect(persistence.attemptedTextScaleWrites, [
      AppTextScale.percent110.name,
      AppTextScale.percent125.name,
      AppTextScale.percent110.name,
      AppTextScale.percent100.name,
    ]);
  });

  test(
    'rapid text scale changes are optimistic and persist in order',
    () async {
      final firstWriteGate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        firstWriteGate: firstWriteGate,
      );
      final controller = _controller(persistence);
      var notifications = 0;
      controller.addListener(() => notifications++);

      final saving110 = controller.setTextScale(AppTextScale.percent110);
      await persistence.firstWriteStarted.future;
      final saving125 = controller.increaseTextScale();

      expect(controller.textScale, AppTextScale.percent125);
      expect(notifications, 2);
      expect(persistence.attemptedTextScaleWrites, isEmpty);

      firstWriteGate.complete();
      await Future.wait([saving110, saving125]);

      expect(persistence.attemptedTextScaleWrites, [
        AppTextScale.percent110.name,
        AppTextScale.percent125.name,
      ]);
      expect(persistence.textScale, AppTextScale.percent125.name);
    },
  );

  test('text scale bounds and repeated selections are no-ops', () async {
    final persistence = _ControlledAppSettingsPersistence();
    final controller = _controller(persistence);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.setTextScale(AppTextScale.percent80);
    await controller.decreaseTextScale();
    await controller.setTextScale(AppTextScale.percent80);
    await controller.setTextScale(AppTextScale.percent200);
    await controller.increaseTextScale();
    await controller.setTextScale(AppTextScale.percent200);

    expect(controller.textScale, AppTextScale.percent200);
    expect(notifications, 2);
    expect(persistence.attemptedTextScaleWrites, [
      AppTextScale.percent80.name,
      AppTextScale.percent200.name,
    ]);
  });

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
    this.textScale,
    this.readGate,
    this.firstWriteGate,
    this.acceptWrites = true,
  });

  String? contentAlignment;
  bool? disableGifAnimations;
  String? textScale;
  final Completer<void>? readGate;
  final Completer<void>? firstWriteGate;
  final bool acceptWrites;
  final Completer<void> readStarted = Completer<void>();
  final Completer<void> firstWriteStarted = Completer<void>();
  final List<String> attemptedWrites = [];
  final List<bool> attemptedGifAnimationWrites = [];
  final List<String> attemptedTextScaleWrites = [];
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
  Future<String?> readTextScale() async => textScale;

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

  @override
  Future<bool> writeTextScale(String value) async {
    attemptedTextScaleWrites.add(value);
    if (!acceptWrites) return false;
    textScale = value;
    return true;
  }
}
