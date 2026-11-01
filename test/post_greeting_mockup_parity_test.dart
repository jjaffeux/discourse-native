import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final name in ['celebration', 'wave']) {
      final loader = SvgAssetLoader(
        'packages/discourse_native/src/ui/assets/post_notice/$name.svg',
      );
      await svg.cache.putIfAbsent(
        loader.cacheKey(null),
        () => loader.loadBytes(null),
      );
    }
    if (Platform.environment['GREETING_RENDER_DIR'] == null) return;
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final type in ['new_user', 'returning_user']) {
    for (final (name, width, dark, scale) in [
      ('phone-light', 390.0, false, 1.0),
      ('phone-dark', 390.0, true, 1.0),
      ('desktop', 900.0, false, 1.0),
      ('large-text', 320.0, true, 2.0),
    ]) {
      testWidgets('$type greeting matches mockup on $name', (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.binding.setSurfaceSize(Size(width, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const user = DiscourseUser(id: 9, username: 'moderator', staff: true);
        final post = Post(
          id: 1,
          postNumber: 1,
          username: 'FabledQuokka62',
          cooked:
              '<p>Hi. Not sure if I am doing this feature request process right.</p>',
          notice: PostNotice(type: type),
        );
        final controller = ShellController(
          instanceStore: FakeInstanceStore([
            instance('meta.example').copyWith(user: user),
          ]),
          api: FakeDiscourseApi(
            user: user,
            topics: {
              7: topicPayload(
                id: 7,
                title: 'Display name in channels',
                posts: [post],
                canEditStaffNotes: true,
              ),
            },
          ),
          authenticator: FakeAuthenticator()
            ..keys['https://meta.example'] = 'key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(controller.dispose);
        await controller.load();
        controller.pushContent(
          ContentRoute.topic(
            topicId: 7,
            slug: 'display-name',
            title: 'Display name in channels',
          ),
        );
        await controller.loadTopic(7, 'display-name');
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme:
                  AppTheme.forBrightness(
                    dark ? Brightness.dark : Brightness.light,
                    fontFamily: 'Lato',
                    readingFontFamily: 'Lato',
                  ).copyWith(
                    platform: width > 600
                        ? TargetPlatform.macOS
                        : TargetPlatform.iOS,
                  ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const Scaffold(body: TopicView()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _capture(tester, '$type-$name');
        final notice = find.byKey(const ValueKey('post-notice-1'));
        final greeting = find.descendant(
          of: notice,
          matching: find.textContaining(
            type == 'new_user' ? 'This is the first time' : 'It’s been a while',
          ),
        );
        expect(greeting, findsOneWidget);
        expect(find.text('Change post notice'), findsNothing);
        final mark = find.descendant(
          of: notice,
          matching: find.byType(DAvatar),
        );
        expect(tester.getSize(mark), const Size(30, 30));
        final textStyle = DefaultTextStyle.of(tester.element(greeting)).style;
        expect(textStyle.fontSize, 14);
        expect(textStyle.fontWeight, FontWeight.w600);
        expect(textStyle.height, 1.5);
        final markRect = tester.getRect(mark);
        final textRect = tester.getRect(greeting);
        expect(textRect.left - markRect.right, 9);
        expect(textRect.center.dy, closeTo(markRect.center.dy, .01));
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['GREETING_RENDER_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final builder = ui.SceneBuilder();
    view.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      view.size.width.round(),
      view.size.height.round(),
    );
    scene.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
