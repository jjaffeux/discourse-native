import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget input, {
    TargetPlatform platform = TargetPlatform.iOS,
    bool dark = false,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: platform,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: Center(child: input)),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (platform, seconds, dark, scale) in [
    (TargetPlatform.iOS, false, false, 1.0),
    (TargetPlatform.android, true, true, 1.5),
  ]) {
    testWidgets('mobile time wheels apply a draft on $platform', (
      tester,
    ) async {
      final changes = <DTimeValue?>[];
      final validity = <bool>[];
      await pump(
        tester,
        DTimeInput(
          initialValue: const DTimeValue(hour: 9, minute: 30, second: 15),
          includeSeconds: seconds,
          mobilePicker: true,
          onChanged: changes.add,
          onValidityChanged: validity.add,
        ),
        platform: platform,
        dark: dark,
        scale: scale,
      );
      await tester.tap(find.byType(DInput));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      final picker = tester.widget<CupertinoTimerPicker>(
        find.byType(CupertinoTimerPicker),
      );
      expect(
        picker.mode,
        seconds ? CupertinoTimerPickerMode.hms : CupertinoTimerPickerMode.hm,
      );
      expect(
        picker.initialTimerDuration,
        Duration(hours: 9, minutes: 30, seconds: seconds ? 15 : 0),
      );
      await tester.drag(
        find.byType(CupertinoPicker).at(1),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      final selectedMinute =
          tester
              .widget<CupertinoPicker>(find.byType(CupertinoPicker).at(1))
              .scrollController!
              .selectedItem %
          60;
      expect(selectedMinute, isNot(30));
      expect(changes, isEmpty);
      expect(find.text('Apply').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(changes, [
        DTimeValue(hour: 9, minute: selectedMinute, second: seconds ? 15 : 0),
      ]);
      expect(validity, [true]);
      final minuteText = selectedMinute.toString().padLeft(2, '0');
      expect(
        find.text(seconds ? '09:$minuteText:15' : '09:$minuteText'),
        findsOneWidget,
      );
      expect(find.byType(CupertinoTimerPicker), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('focus opens wheels and cancel restores the unchanged input', (
    tester,
  ) async {
    final changes = <DTimeValue?>[];
    await pump(
      tester,
      DTimeInput(
        initialValue: const DTimeValue(hour: 23, minute: 59),
        includeSeconds: false,
        mobilePicker: true,
        onChanged: changes.add,
      ),
    );
    final focus = tester.widget<DInput>(find.byType(DInput)).focusNode!;
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoPicker).at(1), const Offset(0, -32));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.text('23:59'), findsOneWidget);
    expect(focus.hasFocus, isTrue);
    expect(find.byType(CupertinoTimerPicker), findsNothing);

    await tester.tap(find.byType(DInput));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoTimerPicker>(find.byType(CupertinoTimerPicker))
          .initialTimerDuration,
      const Duration(hours: 23, minutes: 59),
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.byType(CupertinoTimerPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile picker option retains desktop keyboard editing', (
    tester,
  ) async {
    final changes = <DTimeValue?>[];
    await pump(
      tester,
      DTimeInput(mobilePicker: true, onChanged: changes.add),
      platform: TargetPlatform.macOS,
    );
    await tester.enterText(find.byType(TextField), '12:34:56');
    await tester.pumpAndSettle();
    expect(changes, [const DTimeValue(hour: 12, minute: 34, second: 56)]);
    expect(find.byType(CupertinoTimerPicker), findsNothing);
  });
}
