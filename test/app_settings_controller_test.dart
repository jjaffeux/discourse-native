import 'dart:async';

import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final saveListener in [false, true]) {
    test(
      '${saveListener ? 'save' : 'settings'} listeners can choose a newer value synchronously',
      () async {
        final persistence = _ControlledAppSettingsPersistence();
        final controller = _controller(persistence);
        await controller.load();
        Future<void>? newer;
        void chooseNewer() {
          if (controller.themeMode != AppThemeMode.dark) return;
          newer = controller.setThemeMode(AppThemeMode.light);
        }

        if (saveListener) {
          controller.saveStates.addListener(chooseNewer);
        } else {
          controller.addListener(chooseNewer);
        }
        final first = controller.setThemeMode(AppThemeMode.dark);
        expect(controller.themeMode, AppThemeMode.light);
        expect(newer, isNotNull);
        expect(
          identical(newer, controller.setThemeMode(AppThemeMode.light)),
          isTrue,
        );
        await Future.wait([first, newer!]);
        expect(persistence.attemptedThemeModeWrites, ['dark', 'light']);
        expect(controller.themeMode, AppThemeMode.light);
        expect(
          controller.saveStates.value[AppSettingsField.themeMode]!.status,
          AppSettingsSaveStatus.saved,
        );
        expect(
          (await AppSettingsStore(persistence: persistence).read()).themeMode,
          AppThemeMode.light,
        );
      },
    );
  }

  test('an unawaited selection records failure on the save notifier', () async {
    final persistence = _ControlledAppSettingsPersistence()..throwWrites = true;
    final controller = _controller(persistence);
    await controller.load();
    final failed = Completer<void>();
    controller.saveStates.addListener(() {
      if (controller.saveStates.value[AppSettingsField.themeMode]!.status ==
          AppSettingsSaveStatus.failed) {
        failed.complete();
      }
    });
    unawaited(controller.setThemeMode(AppThemeMode.dark));
    await failed.future;
    expect(controller.themeMode, AppThemeMode.dark);
    expect(
      controller.saveStates.value[AppSettingsField.themeMode]!.failure!.error,
      isA<StateError>(),
    );
  });

  final choices =
      <(AppSettingsField, Future<void> Function(AppSettingsController))>[
        (
          AppSettingsField.limitContentSize,
          (c) => c.setLimitContentSize(false),
        ),
        (
          AppSettingsField.disableGifAnimations,
          (c) => c.setDisableGifAnimations(true),
        ),
        (AppSettingsField.reduceMotion, (c) => c.setReduceMotion(false)),
        (
          AppSettingsField.rawMarkdownComposers,
          (c) => c.setRawMarkdownComposers(true),
        ),
        (
          AppSettingsField.textScale,
          (c) => c.setTextScale(AppTextScale.percent125),
        ),
        (AppSettingsField.themeMode, (c) => c.setThemeMode(AppThemeMode.dark)),
        (
          AppSettingsField.topicListMode,
          (c) => c.setTopicListMode(TopicListDisplayMode.compact),
        ),
      ];

  for (final (field, choose) in choices) {
    for (final throws in [false, true]) {
      test(
        '$field joins pending writes and retries ${throws ? 'throwing' : 'rejected'} saves',
        () async {
          final gate = Completer<void>();
          final persistence = _ControlledAppSettingsPersistence(
            firstWriteGate: gate,
            acceptWrites: false,
          )..throwWrites = throws;
          final controller = _controller(persistence);
          await controller.load();
          var settingsNotifications = 0;
          var saveNotifications = 0;
          controller.addListener(() => settingsNotifications++);
          controller.saveStates.addListener(() => saveNotifications++);
          final saving = choose(controller);
          await persistence.firstWriteStarted.future;
          final repeated = choose(controller);
          expect(identical(saving, repeated), isTrue);
          var completed = false;
          unawaited(repeated.then((_) => completed = true));
          await Future<void>.delayed(Duration.zero);
          expect(completed, isFalse);
          expect(
            controller.saveStates.value[field]!.status,
            AppSettingsSaveStatus.pending,
          );
          gate.complete();
          await saving;
          final failure = controller.saveStates.value[field]!;
          expect(failure.status, AppSettingsSaveStatus.failed);
          expect(failure.failure!.error, isA<StateError>());
          expect(failure.failure!.stackTrace.toString(), isNotEmpty);
          final chosen = controller.settings;
          expect(
            await AppSettingsStore(persistence: persistence).read(),
            isNot(chosen),
          );
          persistence.acceptWrites = true;
          persistence.throwWrites = false;
          await choose(controller);
          expect(
            controller.saveStates.value[field]!.status,
            AppSettingsSaveStatus.saved,
          );
          expect(controller.saveStates.value[field]!.failure, isNull);
          expect(
            await AppSettingsStore(persistence: persistence).read(),
            chosen,
          );
          await choose(controller);
          expect(persistence.writeCount, 2);
          expect(settingsNotifications, 1);
          expect(saveNotifications, 4);
        },
      );
    }
  }

  for (final firstFails in [false, true]) {
    test(
      'an older ${firstFails ? 'failure' : 'success'} cannot complete a newer choice',
      () async {
        final firstGate = Completer<void>();
        final secondGate = Completer<void>();
        final persistence =
            _ControlledAppSettingsPersistence(firstWriteGate: firstGate)
              ..writeGates[2] = secondGate
              ..rejectedWriteNumbers.add(firstFails ? 1 : 2);
        final controller = _controller(persistence);
        await controller.load();
        final first = controller.setThemeMode(AppThemeMode.dark);
        await persistence.firstWriteStarted.future;
        final second = controller.setThemeMode(AppThemeMode.light);
        firstGate.complete();
        await first;
        expect(controller.themeMode, AppThemeMode.light);
        expect(
          controller.saveStates.value[AppSettingsField.themeMode]!.status,
          AppSettingsSaveStatus.pending,
        );
        expect(
          identical(second, controller.setThemeMode(AppThemeMode.light)),
          isTrue,
        );
        secondGate.complete();
        await second;
        expect(
          controller.saveStates.value[AppSettingsField.themeMode]!.status,
          firstFails
              ? AppSettingsSaveStatus.saved
              : AppSettingsSaveStatus.failed,
        );
        expect(controller.themeMode, AppThemeMode.light);
      },
    );
  }

  test('save outcomes remain independent between fields', () async {
    final persistence = _ControlledAppSettingsPersistence()
      ..rejectedWriteNumbers.add(1);
    final controller = _controller(persistence);
    await controller.load();
    final first = controller.setThemeMode(AppThemeMode.dark);
    final second = controller.setDisableGifAnimations(true);
    await Future.wait([first, second]);
    expect(
      controller.saveStates.value[AppSettingsField.themeMode]!.status,
      AppSettingsSaveStatus.failed,
    );
    expect(
      controller
          .saveStates
          .value[AppSettingsField.disableGifAnimations]!
          .status,
      AppSettingsSaveStatus.saved,
    );
    expect(controller.themeMode, AppThemeMode.dark);
    expect(controller.disableGifAnimations, isTrue);
  });

  test(
    'a hydrated session choice must be confirmed by an explicit save',
    () async {
      final persistence = _ControlledAppSettingsPersistence(
        acceptWrites: false,
      );
      final store = AppSettingsStore(persistence: persistence);
      final first = AppSettingsController(store: store);
      await first.setThemeMode(AppThemeMode.dark);
      first.dispose();
      final replacement = AppSettingsController(store: store);
      addTearDown(replacement.dispose);
      await replacement.load();
      expect(replacement.themeMode, AppThemeMode.dark);
      expect(
        replacement.saveStates.value[AppSettingsField.themeMode]!.status,
        AppSettingsSaveStatus.unconfirmed,
      );
      persistence.acceptWrites = true;
      await replacement.setThemeMode(AppThemeMode.dark);
      expect(persistence.attemptedThemeModeWrites, ['dark', 'dark']);
      expect(
        (await AppSettingsStore(persistence: persistence).read()).themeMode,
        AppThemeMode.dark,
      );
      expect(
        replacement.saveStates.value[AppSettingsField.themeMode]!.status,
        AppSettingsSaveStatus.saved,
      );
    },
  );

  test(
    'disposal suppresses late save notifications and observes failure',
    () async {
      final gate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        firstWriteGate: gate,
      )..throwWrites = true;
      final controller = _controller(persistence, dispose: false);
      await controller.load();
      var notifications = 0;
      controller.saveStates.addListener(() => notifications++);
      final saving = controller.setThemeMode(AppThemeMode.dark);
      await persistence.firstWriteStarted.future;
      expect(notifications, 1);
      controller.dispose();
      gate.complete();
      await saving;
      expect(notifications, 1);
      expect(controller.themeMode, AppThemeMode.dark);
      await controller.setThemeMode(AppThemeMode.light);
      expect(persistence.writeCount, 1);
    },
  );

  for (final reduced in [true, false]) {
    test(
      'motion choice $reduced wins over late hydration and failed saves',
      () async {
        final gate = Completer<void>();
        final persistence = _ControlledAppSettingsPersistence(
          readGate: gate,
          acceptWrites: false,
        )..reduceMotion = !reduced;
        final controller = _controller(persistence);
        final loading = controller.load();
        await persistence.readStarted.future;
        await controller.setReduceMotion(reduced);
        gate.complete();
        await loading;
        expect(controller.reduceMotion, reduced);
        expect((await controller.store.read()).reduceMotion, reduced);
      },
    );
  }

  for (final enabled in [true, false]) {
    test('raw Markdown choice $enabled wins over late hydration', () async {
      final gate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        rawMarkdownComposers: !enabled,
        textScale: 'percent125',
        readGate: gate,
        acceptWrites: false,
      );
      final controller = _controller(persistence);
      final loading = controller.load();
      await persistence.readStarted.future;
      await controller.setRawMarkdownComposers(enabled);
      expect(controller.rawMarkdownComposers, enabled);
      gate.complete();
      await loading;
      expect(controller.rawMarkdownComposers, enabled);
      expect(controller.textScale, AppTextScale.percent125);
      expect((await controller.store.read()).rawMarkdownComposers, enabled);
    });
  }

  for (final mode in TopicListDisplayMode.values) {
    test(
      'topic list choice $mode survives hydration without replacing other settings',
      () async {
        final gate = Completer<void>();
        final persistence = _ControlledAppSettingsPersistence(
          limitContentSize: true,
          themeMode: 'dark',
          topicListMode: 'compact',
          readGate: gate,
        );
        final controller = _controller(persistence);
        final loading = controller.load();
        await persistence.readStarted.future;
        final saving = controller.setTopicListMode(mode);
        expect(controller.topicListMode, mode);
        gate.complete();
        await Future.wait([loading, saving]);
        await _expectSettings(
          controller,
          persistence,
          AppSettings(
            limitContentSize: true,
            themeMode: AppThemeMode.dark,
            topicListMode: mode,
          ),
        );
      },
    );
  }

  test(
    'rapid topic list choices persist in order and skip repeated values',
    () async {
      final gate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        firstWriteGate: gate,
      );
      final controller = _controller(persistence);
      await controller.load();
      final compact = controller.setTopicListMode(TopicListDisplayMode.compact);
      await persistence.firstWriteStarted.future;
      final card = controller.setTopicListMode(TopicListDisplayMode.card);
      final repeated = controller.setTopicListMode(TopicListDisplayMode.card);
      expect(identical(card, repeated), isTrue);
      expect(controller.topicListMode, TopicListDisplayMode.card);
      gate.complete();
      await Future.wait([compact, card, repeated]);
      expect(persistence.attemptedTopicListModeWrites, ['compact', 'card']);
      expect(
        (await AppSettingsStore(persistence: persistence).read()).topicListMode,
        TopicListDisplayMode.card,
      );
    },
  );

  test('failed topic list writes retain the session choice', () async {
    final persistence = _ControlledAppSettingsPersistence(acceptWrites: false);
    final controller = _controller(persistence);
    await controller.setTopicListMode(TopicListDisplayMode.compact);
    await controller.load();
    expect(controller.topicListMode, TopicListDisplayMode.compact);
    expect(
      (await controller.store.read()).topicListMode,
      TopicListDisplayMode.compact,
    );
  });

  for (final mode in AppThemeMode.values) {
    test('choosing $mode during hydration preserves saved fields', () async {
      final readGate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        limitContentSize: false,
        disableGifAnimations: true,
        textScale: AppTextScale.percent175.name,
        themeMode: 'dark',
        readGate: readGate,
      );
      final controller = _controller(persistence);
      final loading = controller.load();
      await persistence.readStarted.future;

      final saving = controller.setThemeMode(mode);
      expect(controller.themeMode, mode);
      readGate.complete();
      await Future.wait([loading, saving]);

      await _expectSettings(
        controller,
        persistence,
        AppSettings(
          limitContentSize: false,
          disableGifAnimations: true,
          textScale: AppTextScale.percent175,
          themeMode: mode,
        ),
      );
    });
  }

  test(
    'rapid theme changes persist in order and skip repeated choices',
    () async {
      final persistence = _ControlledAppSettingsPersistence(
        firstWriteGate: Completer<void>(),
      );
      final controller = _controller(persistence);
      await controller.load();
      final dark = controller.setThemeMode(AppThemeMode.dark);
      await persistence.firstWriteStarted.future;
      final light = controller.setThemeMode(AppThemeMode.light);
      final system = controller.setThemeMode(AppThemeMode.system);
      final repeated = controller.setThemeMode(AppThemeMode.system);
      expect(identical(system, repeated), isTrue);
      expect(controller.themeMode, AppThemeMode.system);
      persistence.firstWriteGate!.complete();
      await Future.wait([dark, light, system, repeated]);
      expect(persistence.attemptedThemeModeWrites, ['dark', 'light', 'system']);
      expect(persistence.themeMode, 'system');
    },
  );

  test('failed theme writes retain the session choice', () async {
    final persistence = _ControlledAppSettingsPersistence(acceptWrites: false);
    final controller = _controller(persistence);
    await controller.load();
    await controller.setThemeMode(AppThemeMode.dark);
    expect(controller.themeMode, AppThemeMode.dark);
    expect((await controller.store.read()).themeMode, AppThemeMode.dark);
  });

  test('loads once and exposes the stored settings', () async {
    final persistence = _ControlledAppSettingsPersistence(
      limitContentSize: false,
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
        limitContentSize: false,
        disableGifAnimations: true,
        textScale: AppTextScale.percent125,
      ),
    );
    expect(controller.limitContentSize, false);
    expect(controller.disableGifAnimations, isTrue);
    expect(controller.textScale, AppTextScale.percent125);
    expect(controller.textScaleFactor, 1.25);
    expect(persistence.readCount, 1);
    expect(notifications, 1);
  });

  test('a local selection wins over a stale hydration read', () async {
    final readGate = Completer<void>();
    final persistence = _ControlledAppSettingsPersistence(
      limitContentSize: false,
      disableGifAnimations: true,
      textScale: AppTextScale.percent175.name,
      readGate: readGate,
    );
    final controller = _controller(persistence);

    final loading = controller.load();
    await persistence.readStarted.future;
    final saving = controller.setLimitContentSize(true);

    expect(controller.loaded, isFalse);
    expect(controller.limitContentSize, true);

    readGate.complete();
    await Future.wait([loading, saving]);

    expect(controller.limitContentSize, true);
    expect(persistence.limitContentSize, true);
    await _expectSettings(
      controller,
      persistence,
      const AppSettings(
        limitContentSize: true,
        disableGifAnimations: true,
        textScale: AppTextScale.percent175,
      ),
    );
  });

  for (final startLoad in [false, true]) {
    for (final (name, select, expected)
        in <
          (String, Future<void> Function(AppSettingsController), AppSettings)
        >[
          (
            'content size limit',
            (controller) => controller.setLimitContentSize(true),
            const AppSettings(
              disableGifAnimations: true,
              textScale: AppTextScale.percent175,
            ),
          ),
          (
            'GIF animations',
            (controller) => controller.setDisableGifAnimations(false),
            const AppSettings(
              limitContentSize: true,
              textScale: AppTextScale.percent175,
            ),
          ),
          (
            'text scale',
            (controller) => controller.setTextScale(AppTextScale.percent100),
            const AppSettings(
              limitContentSize: true,
              disableGifAnimations: true,
            ),
          ),
        ]) {
      test(
        'choosing default $name ${startLoad ? 'during' : 'before'} hydration '
        'preserves unrelated saved fields',
        () async {
          final readGate = Completer<void>();
          final persistence = _ControlledAppSettingsPersistence(
            limitContentSize: true,
            disableGifAnimations: true,
            textScale: AppTextScale.percent175.name,
            readGate: readGate,
          );
          final controller = _controller(persistence);
          final loading = startLoad ? controller.load() : null;
          if (startLoad) await persistence.readStarted.future;

          final saving = select(controller);
          expect(controller.settings, AppSettings.defaults);

          readGate.complete();
          await saving;
          if (loading != null) await loading;
          await controller.load();

          await _expectSettings(controller, persistence, expected);
        },
      );
    }
  }

  test(
    'several pending edits preserve the last choice and stored scale',
    () async {
      final readGate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        limitContentSize: false,
        disableGifAnimations: true,
        textScale: AppTextScale.percent175.name,
        readGate: readGate,
      );
      final controller = _controller(persistence);
      final loading = controller.load();
      await persistence.readStarted.future;

      final saves = [
        controller.setLimitContentSize(true),
        controller.setDisableGifAnimations(true),
        controller.setLimitContentSize(false),
        controller.setDisableGifAnimations(false),
      ];
      expect(controller.settings, const AppSettings(limitContentSize: false));
      // A slow hydration read must not delay persistence of explicit choices.
      await Future.wait(saves);
      expect(persistence.limitContentSize, false);
      expect(persistence.disableGifAnimations, isFalse);
      expect(persistence.textScale, AppTextScale.percent175.name);

      readGate.complete();
      await loading;

      await _expectSettings(
        controller,
        persistence,
        const AppSettings(
          limitContentSize: false,
          textScale: AppTextScale.percent175,
        ),
      );
    },
  );

  test(
    'choosing the initial default still supersedes a pending read',
    () async {
      final readGate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        limitContentSize: true,
        readGate: readGate,
      );
      final controller = _controller(persistence);

      final loading = controller.load();
      await persistence.readStarted.future;
      final saving = controller.setLimitContentSize(false);

      readGate.complete();
      await Future.wait([loading, saving]);

      expect(controller.limitContentSize, false);
      expect(persistence.limitContentSize, false);
      expect(persistence.attemptedWrites, [false]);
    },
  );

  test('a local text scale wins over a stale hydration read', () async {
    final readGate = Completer<void>();
    final persistence = _ControlledAppSettingsPersistence(
      limitContentSize: false,
      disableGifAnimations: true,
      textScale: AppTextScale.percent175.name,
      readGate: readGate,
    );
    final controller = _controller(persistence);

    final loading = controller.load();
    await persistence.readStarted.future;
    final saving = controller.setTextScale(AppTextScale.percent90);

    expect(controller.loaded, isFalse);
    expect(controller.textScale, AppTextScale.percent90);
    expect(controller.textScaleFactor, 0.9);

    readGate.complete();
    await Future.wait([loading, saving]);

    expect(controller.textScale, AppTextScale.percent90);
    expect(persistence.textScale, AppTextScale.percent90.name);
    await _expectSettings(
      controller,
      persistence,
      const AppSettings(
        limitContentSize: false,
        disableGifAnimations: true,
        textScale: AppTextScale.percent90,
      ),
    );
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

  test('relative text changes hydrate before saving', () async {
    final readGate = Completer<void>();
    final persistence = _ControlledAppSettingsPersistence(
      limitContentSize: false,
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
        limitContentSize: false,
        disableGifAnimations: true,
        textScale: AppTextScale.percent135,
      ),
    );
    expect(persistence.limitContentSize, false);
    expect(persistence.disableGifAnimations, isTrue);
    expect(persistence.attemptedTextScaleWrites, [
      AppTextScale.percent130.name,
      AppTextScale.percent135.name,
    ]);
  });

  test(
    'a content size limit edit does not make the initial text scale authoritative',
    () async {
      final readGate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        limitContentSize: false,
        disableGifAnimations: true,
        textScale: AppTextScale.percent125.name,
        readGate: readGate,
      );
      final controller = _controller(persistence);
      final loading = controller.load();
      await persistence.readStarted.future;

      final sizeLimit = controller.setLimitContentSize(true);
      final firstIncrease = controller.increaseTextScale();
      final secondIncrease = controller.increaseTextScale();
      expect(controller.limitContentSize, true);
      expect(controller.textScale, AppTextScale.percent100);
      await sizeLimit;
      expect(persistence.attemptedTextScaleWrites, isEmpty);

      readGate.complete();
      await Future.wait([loading, firstIncrease, secondIncrease]);

      await _expectSettings(
        controller,
        persistence,
        const AppSettings(
          limitContentSize: true,
          disableGifAnimations: true,
          textScale: AppTextScale.percent135,
        ),
      );
    },
  );

  test(
    'relative text changes use an explicit scale immediately during hydration',
    () async {
      final readGate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        limitContentSize: false,
        disableGifAnimations: true,
        textScale: AppTextScale.percent175.name,
        readGate: readGate,
      );
      final controller = _controller(persistence);
      final loading = controller.load();
      await persistence.readStarted.future;

      final selection = controller.setTextScale(AppTextScale.percent90);
      final increase = controller.increaseTextScale();
      expect(controller.textScale, AppTextScale.percent95);
      final decrease = controller.decreaseTextScale();
      expect(controller.textScale, AppTextScale.percent90);
      final reset = controller.resetTextScale();
      expect(controller.textScale, AppTextScale.percent100);
      await Future.wait([selection, increase, decrease, reset]);

      readGate.complete();
      await loading;

      await _expectSettings(
        controller,
        persistence,
        const AppSettings(limitContentSize: false, disableGifAnimations: true),
      );
    },
  );

  test(
    'rapid selections notify optimistically and persist the last value',
    () async {
      final firstWriteGate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        firstWriteGate: firstWriteGate,
        limitContentSize: true,
      );
      final controller = _controller(persistence);
      await controller.load();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final savingDisabled = controller.setLimitContentSize(false);
      await persistence.firstWriteStarted.future;
      final savingEnabled = controller.setLimitContentSize(true);

      expect(controller.limitContentSize, true);
      expect(notifications, 2);
      expect(persistence.attemptedWrites, [false]);

      firstWriteGate.complete();
      await Future.wait([savingDisabled, savingEnabled]);

      expect(persistence.attemptedWrites, [false, true]);
      expect(persistence.limitContentSize, true);

      await controller.setLimitContentSize(true);
      expect(persistence.attemptedWrites, [false, true]);
      expect(notifications, 2);
    },
  );

  test('adjusts and resets text scale one bounded step at a time', () async {
    final persistence = _ControlledAppSettingsPersistence();
    final controller = _controller(persistence);

    await controller.increaseTextScale();
    expect(controller.textScale, AppTextScale.percent105);
    expect(controller.textScaleFactor, 1.05);

    await controller.increaseTextScale();
    expect(controller.textScale, AppTextScale.percent110);

    await controller.decreaseTextScale();
    expect(controller.textScale, AppTextScale.percent105);

    await controller.resetTextScale();
    expect(controller.textScale, AppTextScale.percent100);
    expect(persistence.attemptedTextScaleWrites, [
      AppTextScale.percent105.name,
      AppTextScale.percent110.name,
      AppTextScale.percent105.name,
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
      await controller.load();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final saving110 = controller.setTextScale(AppTextScale.percent110);
      await persistence.firstWriteStarted.future;
      final saving115 = controller.increaseTextScale();

      expect(controller.textScale, AppTextScale.percent115);
      expect(notifications, 2);
      expect(persistence.attemptedTextScaleWrites, [
        AppTextScale.percent110.name,
      ]);

      firstWriteGate.complete();
      await Future.wait([saving110, saving115]);

      expect(persistence.attemptedTextScaleWrites, [
        AppTextScale.percent110.name,
        AppTextScale.percent115.name,
      ]);
      expect(persistence.textScale, AppTextScale.percent115.name);
    },
  );

  test('text scale bounds and repeated selections are no-ops', () async {
    final persistence = _ControlledAppSettingsPersistence();
    final controller = _controller(persistence);
    await controller.load();
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

    await controller.setLimitContentSize(true);
    await controller.load();

    expect(controller.loaded, isTrue);
    expect(controller.limitContentSize, true);
    expect(persistence.limitContentSize, isNull);
    expect(persistence.attemptedWrites, [true]);
  });

  test('updates the GIF animation preference optimistically', () async {
    final persistence = _ControlledAppSettingsPersistence();
    final controller = _controller(persistence);

    await controller.setDisableGifAnimations(true);
    await controller.load();

    expect(controller.loaded, isTrue);
    expect(controller.disableGifAnimations, isTrue);
    expect(persistence.disableGifAnimations, isTrue);
    expect(persistence.attemptedGifAnimationWrites, [true]);
  });

  test('a replacement controller retains a rejected session choice', () async {
    final persistence = _ControlledAppSettingsPersistence(
      limitContentSize: false,
      disableGifAnimations: true,
      textScale: AppTextScale.percent175.name,
      acceptWrites: false,
    );
    final store = AppSettingsStore(persistence: persistence);
    final first = AppSettingsController(store: store);

    await first.setLimitContentSize(true);
    first.dispose();

    final replacement = AppSettingsController(store: store);
    addTearDown(replacement.dispose);
    await replacement.load();

    expect(
      replacement.settings,
      const AppSettings(
        limitContentSize: true,
        disableGifAnimations: true,
        textScale: AppTextScale.percent175,
      ),
    );
    expect(persistence.limitContentSize, false);
    expect(persistence.attemptedWrites, [true]);
    expect(await store.read(), replacement.settings);
  });

  test('replacement controllers cannot reorder rapid writes', () async {
    final firstWriteGate = Completer<void>();
    final persistence = _ControlledAppSettingsPersistence(
      firstWriteGate: firstWriteGate,
    );
    final first = _controller(persistence, dispose: false);
    final replacement = _controller(persistence);

    final savingDisabled = first.setLimitContentSize(false);
    await persistence.firstWriteStarted.future;
    final savingEnabled = replacement.setLimitContentSize(true);

    expect(persistence.attemptedWrites, [false]);
    first.dispose();
    firstWriteGate.complete();
    await Future.wait([savingDisabled, savingEnabled]);

    expect(persistence.attemptedWrites, [false, true]);
    expect(persistence.limitContentSize, true);
    expect(replacement.limitContentSize, true);
  });

  test('dispose ignores a late read and rejects later selections', () async {
    final readGate = Completer<void>();
    final persistence = _ControlledAppSettingsPersistence(
      limitContentSize: false,
      readGate: readGate,
    );
    final controller = _controller(persistence, dispose: false);

    final loading = controller.load();
    await persistence.readStarted.future;
    controller.dispose();
    readGate.complete();
    await loading;
    await controller.setLimitContentSize(true);

    expect(controller.loaded, isFalse);
    expect(controller.limitContentSize, true);
    expect(persistence.attemptedWrites, isEmpty);
  });

  test(
    'disposal preserves an accepted edit without late hydration notifications',
    () async {
      final readGate = Completer<void>();
      final firstWriteGate = Completer<void>();
      final persistence = _ControlledAppSettingsPersistence(
        limitContentSize: false,
        disableGifAnimations: true,
        textScale: AppTextScale.percent175.name,
        readGate: readGate,
        firstWriteGate: firstWriteGate,
      );
      final controller = _controller(persistence, dispose: false);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final loading = controller.load();
      await persistence.readStarted.future;
      final saving = controller.setLimitContentSize(true);
      await persistence.firstWriteStarted.future;
      expect(notifications, 1);

      controller.dispose();
      await controller.setLimitContentSize(false);
      await controller.setDisableGifAnimations(false);
      await controller.setTextScale(AppTextScale.percent100);
      await controller.increaseTextScale();
      await controller.decreaseTextScale();
      await controller.resetTextScale();
      firstWriteGate.complete();
      readGate.complete();
      await Future.wait([loading, saving]);

      expect(notifications, 1);
      expect(controller.loaded, isFalse);
      expect(controller.settings, const AppSettings(limitContentSize: true));
      const expected = AppSettings(
        limitContentSize: true,
        disableGifAnimations: true,
        textScale: AppTextScale.percent175,
      );
      expect(await controller.store.read(), expected);
      expect(await AppSettingsStore(persistence: persistence).read(), expected);
      expect(persistence.attemptedWrites, [true]);
      expect(persistence.attemptedGifAnimationWrites, isEmpty);
      expect(persistence.attemptedTextScaleWrites, isEmpty);
    },
  );
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

Future<void> _expectSettings(
  AppSettingsController controller,
  AppSettingsPersistence persistence,
  AppSettings expected,
) async {
  expect(controller.settings, expected);
  expect(await controller.store.read(), expected);
  expect(await AppSettingsStore(persistence: persistence).read(), expected);
}

final class _ControlledAppSettingsPersistence
    implements AppSettingsPersistence {
  _ControlledAppSettingsPersistence({
    this.limitContentSize,
    this.disableGifAnimations,
    this.rawMarkdownComposers,
    this.textScale,
    this.themeMode,
    this.topicListMode,
    this.readGate,
    this.firstWriteGate,
    this.acceptWrites = true,
  });

  bool? limitContentSize;
  bool? disableGifAnimations;
  bool? rawMarkdownComposers;
  bool? reduceMotion;
  String? textScale;
  String? themeMode;
  String? topicListMode;
  final Completer<void>? readGate;
  final Completer<void>? firstWriteGate;
  bool acceptWrites;
  bool throwWrites = false;
  int writeCount = 0;
  final Map<int, Completer<void>> writeGates = {};
  final Set<int> rejectedWriteNumbers = {};
  final Completer<void> readStarted = Completer<void>();
  final Completer<void> firstWriteStarted = Completer<void>();
  final List<bool> attemptedWrites = [];
  final List<bool> attemptedGifAnimationWrites = [];
  final List<String> attemptedTextScaleWrites = [];
  final List<String> attemptedThemeModeWrites = [];
  final List<String> attemptedTopicListModeWrites = [];
  int readCount = 0;

  @override
  Future<bool?> readLimitContentSize() async {
    readCount++;
    final value = limitContentSize;
    if (!readStarted.isCompleted) readStarted.complete();
    await readGate?.future;
    return value;
  }

  @override
  Future<bool?> readDisableGifAnimations() async => disableGifAnimations;

  @override
  Future<bool?> readReduceMotion() async => reduceMotion;

  @override
  Future<bool> writeReduceMotion(bool value) async {
    if (!await _acceptWrite()) return false;
    reduceMotion = value;
    return true;
  }

  @override
  Future<bool?> readRawMarkdownComposers() async => rawMarkdownComposers;

  @override
  Future<String?> readTextScale() async => textScale;

  @override
  Future<String?> readThemeMode() async => themeMode;

  @override
  Future<bool> writeLimitContentSize(bool value) async {
    attemptedWrites.add(value);
    if (!await _acceptWrite()) return false;
    limitContentSize = value;
    return true;
  }

  @override
  Future<bool> writeDisableGifAnimations(bool value) async {
    attemptedGifAnimationWrites.add(value);
    if (!await _acceptWrite()) return false;
    disableGifAnimations = value;
    return true;
  }

  @override
  Future<bool> writeRawMarkdownComposers(bool value) async {
    if (!await _acceptWrite()) return false;
    rawMarkdownComposers = value;
    return true;
  }

  @override
  Future<bool> writeTextScale(String value) async {
    attemptedTextScaleWrites.add(value);
    if (!await _acceptWrite()) return false;
    textScale = value;
    return true;
  }

  @override
  Future<bool> writeThemeMode(String value) async {
    attemptedThemeModeWrites.add(value);
    if (!await _acceptWrite()) return false;
    themeMode = value;
    return true;
  }

  @override
  Future<String?> readTopicListMode() async => topicListMode;

  @override
  Future<bool> writeTopicListMode(String value) async {
    attemptedTopicListModeWrites.add(value);
    if (!await _acceptWrite()) return false;
    topicListMode = value;
    return true;
  }

  Future<bool> _acceptWrite() async {
    final number = ++writeCount;
    if (!firstWriteStarted.isCompleted) {
      firstWriteStarted.complete();
      await firstWriteGate?.future;
    }
    await writeGates[number]?.future;
    if (throwWrites) throw StateError('preferences unavailable');
    return acceptWrites && !rejectedWriteNumbers.contains(number);
  }
}
