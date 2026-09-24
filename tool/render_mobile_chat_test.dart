// Render the full production mobile shell, including Chat + Voice grouping.
// flutter test --no-pub tool/render_mobile_chat_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/mobile_shell_test.dart' as mobile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
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
  testWidgets('render Chat with Voice enabled in the mobile shell', (
    tester,
  ) async {
    final channels = [
      for (final (index, entry) in [
        ('general', 0, false, 0xffa0a0ad),
        ('flourpower', 3, true, 0xffe8a135),
        ('baking', 4, false, 0xffdfb567),
        ('plants', 2, false, 0xff80bad8),
        ('verdant_vera', 0, true, 0xff20af63),
        ('keyboards', 8, false, 0xff91d4b6),
        ('travel', 7, false, 0xffcaa0dc),
        ('books', 2, false, 0xffeab58b),
        ('hiking', 0, false, 0xff94d8cf),
      ].indexed)
        ChatChannel(
          id: index + 1,
          title: entry.$1,
          kind: entry.$3
              ? ChatChannelKind.directMessage
              : ChatChannelKind.category,
          categoryColor: Color(entry.$4),
          membership: const ChatMembership(following: true),
          users: entry.$3
              ? [ChatUser(id: index + 10, username: entry.$1)]
              : const [],
          tracking: ChatTracking(unreadCount: entry.$2),
          lastMessageId: index + 100,
          lastMessageAt: DateTime.now().subtract(Duration(minutes: index * 3)),
          lastMessageUserId: index == 4 ? 14 : 7,
          lastMessagePreview: 'Will follow up in the morning.',
        ),
    ];
    final shell = await mobile.pumpMobileShellFixture(
      tester,
      size: const Size(430, 932),
      voice: true,
      conversations: ChatChannels(
        public: channels.where((c) => !c.isDirectMessage).toList(),
        direct: channels.where((c) => c.isDirectMessage).toList(),
        hasThreads: true,
      ),
    );
    final output = Directory('build/mobile-chat-review')
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

    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatMobileSidebar), findsOneWidget);
    for (final palette in ['neutral', 'dracula']) {
      await shell.forumSettings.setThemes(
        shell.currentInstance!.url,
        ForumThemePreferences.preset(palette),
      );
      await shell.forumSettings.setThemeMode(
        shell.currentInstance!.url,
        AppThemeMode.dark,
      );
      await tester.pumpAndSettle();
      await capture('$palette-chat');
    }
    await tester.tap(find.byKey(const ValueKey('user-presence-menu')));
    await tester.pumpAndSettle();
    await capture('dracula-status');
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
