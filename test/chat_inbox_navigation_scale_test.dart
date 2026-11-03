import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_sidebar_parity_test.dart' show capture;
import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'sidebar_panel_tabs_test.dart' as panels;
import 'support/load_test_fonts.dart';
import 'support/native_ui_evidence.dart';

void main() {
  setUpAll(loadTestFonts);
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        ),
  );
  testWidgets('desktop chat directory pills sit eight below the switches', (
    tester,
  ) async {
    await prepareNativeUiEvidence(tester);
    final shell = await panels.pumpTabs(tester, threads: true, voice: false);
    shell.pluginSession.require(chatShellService).openChats();
    await tester.pumpAndSettle();
    final page = find.byType(ChatMobileSidebar);
    final filters = find.descendant(
      of: page,
      matching: find.byType(ChatInboxFilterBar),
    );
    final navigation = find.descendant(
      of: page,
      matching: find.byKey(const ValueKey('chat-inbox-navigation')),
    );
    expect(tester.getRect(navigation).top - tester.getRect(filters).bottom, 8);
    expect(tester.getRect(navigation).left - tester.getRect(page).left, 16);
    for (final key in ['chat-inbox-channels-card', 'chat-inbox-threads-card']) {
      _expectFilter(
        tester,
        find.descendant(of: page, matching: find.byKey(ValueKey(key))),
        height: 30,
        text: 12.5,
      );
    }
    expect(tester.takeException(), isNull);
    await capture(tester, 'chat-page-desktop-navigation');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  testWidgets(
    'chat navigation keeps reference size and user text scaling',
    (tester) async {
      await prepareNativeUiEvidence(tester);
      final shell = await pumpMobileShellFixture(
        tester,
        size: const Size(600, 1000),
      );
      shell.selectMobilePanel('chat');
      await tester.pumpAndSettle();
      final filters = find.byType(ChatInboxFilterBar);
      final navigation = find.byKey(const ValueKey('chat-inbox-navigation'));
      expect(
        tester.getRect(navigation).top - tester.getRect(filters).bottom,
        8,
      );
      expect(tester.getRect(navigation).left, 16);
      await capture(tester, 'chat-page-phone-navigation');
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
