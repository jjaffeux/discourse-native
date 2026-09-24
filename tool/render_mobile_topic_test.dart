// Offscreen review of production mobile widgets, with local macOS fonts.
// flutter test tool/render_mobile_navigation_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/mobile_topic_layout_test.dart' as mobile;

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
  testWidgets('render mobile topic layout', (tester) async {
    final shell = await mobile.pumpMobileTopicFixture(
      tester,
      size: const Size(496, 961),
    );
    final output = Directory('/tmp/mobile-topic-review')
      ..createSync(recursive: true);
    for (final (name, width, dark) in [
      ('dracula-496', 496.0, true),
      ('light-390', 390.0, false),
      ('dracula-320', 320.0, true),
    ]) {
      tester.view.physicalSize = Size(width, 961);
      await shell.forumSettings.setThemes(
        shell.currentInstance!.url,
        ForumThemePreferences.preset(dark ? 'dracula' : 'neutral'),
      );
      await shell.forumSettings.setThemeMode(
        shell.currentInstance!.url,
        dark ? AppThemeMode.dark : AppThemeMode.light,
      );
      await tester.pumpAndSettle();
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
