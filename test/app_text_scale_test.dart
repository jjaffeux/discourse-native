import 'dart:async';

import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/app_text_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'AppTextScaler composes app zoom with platform accessibility scaling',
    () {
      const platform = _TestTextScaler();
      const scaler = AppTextScaler(platformScaler: platform, appScale: 1.25);

      expect(scaler.scale(12), platform.scale(12) * 1.25);
      expect(scaler.scale(24), platform.scale(24) * 1.25);
      // ignore: deprecated_member_use
      expect(scaler.textScaleFactor, platform.scale(16) / 16 * 1.25);
      expect(
        scaler,
        const AppTextScaler(platformScaler: platform, appScale: 1.25),
      );
      expect(
        scaler,
        isNot(const AppTextScaler(platformScaler: platform, appScale: 1.5)),
      );
    },
  );

  testWidgets('the region updates the inherited scaler without remounting', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await controller.setTextScale(AppTextScale.percent125);
    const childKey = ValueKey('scaled-child');

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppTextScaleRegion(controller: controller, child: child!),
        home: const SizedBox(key: childKey),
      ),
    );

    final before = tester.element(find.byKey(childKey));
    expect(MediaQuery.textScalerOf(before).scale(16), moreOrLessEquals(20));

    await controller.setTextScale(AppTextScale.percent150);
    await tester.pump();

    final after = tester.element(find.byKey(childKey));
    expect(after, same(before));
    expect(MediaQuery.textScalerOf(after).scale(16), moreOrLessEquals(24));
  });

  for (final (platform, modifier) in [
    (TargetPlatform.macOS, LogicalKeyboardKey.metaLeft),
    (TargetPlatform.iOS, LogicalKeyboardKey.metaLeft),
    (TargetPlatform.linux, LogicalKeyboardKey.controlLeft),
  ]) {
    testWidgets(
      '${platform.name} primary plus, minus, and zero shortcuts change text size',
      (tester) async {
        final persistence = MemoryAppSettingsPersistence();
        final controller = _controller(persistence: persistence);
        addTearDown(controller.dispose);
        await controller.load();

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) =>
                AppTextScaleRegion(controller: controller, child: child!),
            home: const Text('Zoom target'),
          ),
        );

        expect(
          await _pressShortcut(
            tester,
            modifier: modifier,
            key: LogicalKeyboardKey.equal,
            character: '=',
          ),
          isTrue,
        );
        expect(controller.textScale, AppTextScale.percent110);

        expect(
          await _pressShortcut(
            tester,
            modifier: modifier,
            key: LogicalKeyboardKey.equal,
            character: '+',
            shift: true,
          ),
          isTrue,
        );
        expect(controller.textScale, AppTextScale.percent125);

        expect(
          await _pressShortcut(
            tester,
            modifier: modifier,
            key: LogicalKeyboardKey.minus,
            character: '-',
          ),
          isTrue,
        );
        expect(controller.textScale, AppTextScale.percent110);

        expect(
          await _pressShortcut(
            tester,
            modifier: modifier,
            key: LogicalKeyboardKey.digit0,
            character: '0',
          ),
          isTrue,
        );
        expect(controller.textScale, AppTextScale.percent100);

        if (platform == TargetPlatform.macOS) {
          expect(
            await _pressShortcut(
              tester,
              modifier: modifier,
              key: LogicalKeyboardKey.numpadAdd,
            ),
            isTrue,
          );
          expect(controller.textScale, AppTextScale.percent110);
          expect(
            await _pressShortcut(
              tester,
              modifier: modifier,
              key: LogicalKeyboardKey.numpadSubtract,
            ),
            isTrue,
          );
          expect(controller.textScale, AppTextScale.percent100);
        }
        await tester.pump();
        expect(persistence.textScale, AppTextScale.percent100.name);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('zoom shortcuts work above focused fields and modal routes', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await controller.load();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) =>
            AppTextScaleRegion(controller: controller, child: child!),
        home: const Scaffold(body: TextField(autofocus: true)),
      ),
    );
    await tester.pump();

    unawaited(
      showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (context) =>
            const AlertDialog(content: TextField(autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      await _pressShortcut(
        tester,
        modifier: LogicalKeyboardKey.metaLeft,
        key: LogicalKeyboardKey.equal,
        character: '+',
        shift: true,
      ),
      isTrue,
    );
    expect(controller.textScale, AppTextScale.percent110);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

AppSettingsController _controller({
  MemoryAppSettingsPersistence? persistence,
}) => AppSettingsController(
  store: AppSettingsStore(
    persistence: persistence ?? MemoryAppSettingsPersistence(),
  ),
);

Future<bool> _pressShortcut(
  WidgetTester tester, {
  required LogicalKeyboardKey modifier,
  required LogicalKeyboardKey key,
  String? character,
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  final handled = await tester.sendKeyEvent(key, character: character);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  return handled;
}

final class _TestTextScaler extends TextScaler {
  const _TestTextScaler();

  @override
  double scale(double fontSize) => fontSize + 4;

  @override
  double get textScaleFactor => 1.5;
}
