import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_section.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;

void main() {
  testWidgets(
    'chat navigation keeps reference size and user text scaling',
    (tester) async {
      final shell = await pumpMobileShellFixture(
        tester,
        size: const Size(600, 1000),
      );
      shell.selectMobilePanel('chat');
      await tester.pumpAndSettle();
      for (final key in [
        'chat-inbox-channels-card',
        'chat-inbox-threads-card',
      ]) {
        _expectFilter(tester, find.byKey(ValueKey(key)), height: 44, text: 16);
      }

      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await shell.appSettings.setTextScale(AppTextScale.percent125);
      await tester.pumpAndSettle();
      for (final key in [
        'chat-inbox-channels-card',
        'chat-inbox-threads-card',
      ]) {
        _expectFilter(tester, find.byKey(ValueKey(key)), height: 65, text: 30);
      }
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    testWidgets('chat section expansion keeps reference size on $platform', (
      tester,
    ) async {
      final mobile = platform != TargetPlatform.macOS;
      for (final (appScale, platformScale, height, text) in [
        (1.0, 1.0, mobile ? 44.0 : 30.0, mobile ? 16.0 : 12.5),
        (1.25, 2.0, mobile ? 80.0 : 58.125, mobile ? 40.0 : 31.25),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark.copyWith(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: AppTextScaler(
                  platformScaler: TextScaler.linear(platformScale),
                  appScale: appScale,
                  baselineScale: mobile ? 17 / 14 : 1,
                ),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: ChatInboxMore(
                  hidden: 3,
                  expanded: false,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectFilter(tester, find.byType(DButton), height: height, text: text);
        expect(tester.takeException(), isNull);
      }
    });
  }
}

void _expectFilter(
  WidgetTester tester,
  Finder control, {
  required double height,
  required double text,
}) {
  expect(tester.getSize(control).height, closeTo(height, .001));
  final label = find.descendant(of: control, matching: find.byType(Text));
  final context = tester.element(label);
  final fontSize = DefaultTextStyle.of(context).style.fontSize!;
  expect(MediaQuery.textScalerOf(context).scale(fontSize), closeTo(text, .001));
}
