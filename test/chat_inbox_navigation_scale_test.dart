import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/load_test_fonts.dart';

void main() {
  setUpAll(loadTestFonts);
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        ),
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
        (1.0, 1.0, mobile ? 36.0 : 30.0, mobile ? 14.0 : 12.5),
        (1.25, 2.0, mobile ? 67.5 : 58.125, mobile ? 35.0 : 31.25),
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
