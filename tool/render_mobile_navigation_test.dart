// Offscreen review of production mobile widgets, with local macOS fonts.
// flutter test tool/render_mobile_navigation_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/mobile_shell_test.dart' as mobile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // This executable is an offscreen test fixture.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final family in [
      'Roboto',
      '.SF UI Text',
      '.SF UI Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(
                File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
  });
  testWidgets('render mobile navigation in light and Dracula', (tester) async {
    final shell = await mobile.pumpMobileShellFixture(tester, events: true);
    final output = Directory('/tmp/mobile-navigation-review')
      ..createSync(recursive: true);
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final layer =
            tester.binding.renderViews.single.debugLayer! as OffsetLayer;
        final image = await layer.toImage(
          Offset.zero & tester.view.physicalSize,
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${output.path}/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final dark in [false, true]) {
      final name = dark ? 'dracula' : 'light';
      await shell.forumSettings.setThemes(
        shell.currentInstance!.url,
        ForumThemePreferences(selectedId: dark ? 'dracula' : 'neutral'),
      );
      await shell.forumSettings.setThemeMode(
        shell.currentInstance!.url,
        dark ? AppThemeMode.dark : AppThemeMode.light,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
      await tester.pumpAndSettle();
      await capture('$name-topics');
      await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
      await tester.pumpAndSettle();
      await capture('$name-forum');
      await tester.tap(find.text('Shortcuts'));
      await tester.pumpAndSettle();
      await capture('$name-shortcuts');
      await tester.tap(find.byTooltip('Close navigation'));
      await tester.pumpAndSettle();
      for (final tab in ['messages', 'chat', 'users', 'events']) {
        final destination = switch (tab) {
          'chat' => 'panel/chat',
          'events' => 'destination/events-upcoming',
          _ => tab,
        };
        await tester.tap(find.byKey(ValueKey('mobile-mode-$destination')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        if (tab == 'chat') await capture('$name-messages-to-chat');
        await tester.pumpAndSettle();
        await capture('$name-$tab');
      }
      await tester.tap(find.byKey(const ValueKey('mobile-mode-more')));
      await tester.pumpAndSettle();
      await capture('$name-more');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    tester.view.physicalSize = const Size(320, 720);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
    await tester.pumpAndSettle();
    await capture('dracula-320-text200');
    expect(find.byType(DHistoryTransition), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
