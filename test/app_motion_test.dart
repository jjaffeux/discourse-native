import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/shell/app_motion.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('device changes remain live until an explicit motion choice', (
    tester,
  ) async {
    final controller = AppSettingsController(
      store: AppSettingsStore(persistence: MemoryAppSettingsPersistence()),
    );
    addTearDown(controller.dispose);
    await controller.load();
    bool? reduced;
    Future<void> pump(bool deviceReduced) => tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: deviceReduced),
        child: AppMotionRegion(
          controller: controller,
          child: Builder(
            builder: (context) {
              reduced = MediaQuery.disableAnimationsOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await pump(false);
    expect(reduced, isFalse);
    await pump(true);
    expect(reduced, isTrue);
    await controller.setReduceMotion(false);
    await tester.pump();
    expect(reduced, isFalse);
    await pump(false);
    await controller.setReduceMotion(true);
    await tester.pump();
    expect(reduced, isTrue);
  });
}
