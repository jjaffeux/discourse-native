import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'support/button_surface.dart';
import 'support/fakes.dart';
import 'support/stock_glass.dart';

const _site = 'https://meta.example';
const _post = Post(
  id: 1,
  postNumber: 1,
  username: 'author',
  cooked: '<p>Post</p>',
  likeCount: 3,
  canLike: true,
);

void main() {
  setUpAll(() async {
    if (Platform.environment['POST_ACTION_RENDER_DIR'] == null) return;
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final dark in [false, true]) {
    for (final glass in [false, true]) {
      testWidgets(
        'production Reply and More match bare post actions ($dark, $glass)',
        (tester) async {
          final shell = ShellController(
            instanceStore: FakeInstanceStore([
              instance(
                'meta.example',
              ).copyWith(user: const DiscourseUser(username: 'reader')),
            ]),
            api: FakeDiscourseApi(
              topics: {
                7: topicPayload(
                  id: 7,
                  title: 'A topic',
                  posts: const [_post],
                  canCreatePost: true,
                ),
              },
            ),
            authenticator: FakeAuthenticator()..keys[_site] = 'key',
            drafts: FakeDraftStore(),
            trackers: FakeSiteTracker.reset(),
            updateStore: FakeUpdateStore(),
          );
          await shell.load();
          addTearDown(shell.dispose);
          shell.pushContent(
            ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
          );
          await shell.loadTopic(7, 'a-topic');
          final key = GlobalKey();
          final theme = DMaterialTheme.apply(
            AppTheme.forBrightness(
              dark ? Brightness.dark : Brightness.light,
              fontFamily: 'Lato',
            ),
            glass
                ? DAppearanceMaterial.liquidGlass
                : DAppearanceMaterial.standard,
          );
          Future<void> mount({
            double scale = 1,
            TargetPlatform platform = TargetPlatform.macOS,
            bool reduced = false,
          }) => tester.pumpWidget(
            ShellScope(
              controller: shell,
              child: MaterialApp(
                theme: theme.copyWith(platform: platform),
                home: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: reduced,
                  ),
                  child: Scaffold(
                    body: Center(
                      child: RepaintBoundary(
                        key: key,
                        child: ColoredBox(
                          color: theme.scaffoldBackgroundColor,
                          child: SizedBox(
                            width: scale == 1 ? 440 : 320,
                            height: 130,
                            child: const Padding(
                              padding: EdgeInsets.all(24),
                              child: PostActions(
                                siteUrl: _site,
                                post: _post,
                                persistent: true,
                                child: PostActionsFooter(
                                  child: PostLikes(siteUrl: _site, post: _post),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await mount();
          await tester.pumpAndSettle();
          final more = find.byKey(const ValueKey('post-more-actions-1'));
          final reply = find.byKey(
            const ValueKey(('post-footer-action', 1, 'Reply')),
          );
          final tokens = DTokens.of(tester.element(reply));
          for (final button in [more, reply]) {
            expect(
              tester.widget<DButton>(button).density,
              DButtonDensity.postAction,
            );
            expect(tester.getSize(button), const Size.square(30));
            expect(buttonSurface(tester, of: button).color, Colors.transparent);
            expect(
              buttonSurface(tester, of: button).borderColor,
              Colors.transparent,
            );
            expect(
              buttonSurface(tester, of: button).borderRadius,
              BorderRadius.circular(8),
            );
            expect(
              find.descendant(of: button, matching: find.byType(LiquidGlass)),
              findsNothing,
            );
            final icon = find.descendant(
              of: button,
              matching: find.byType(DIcon),
            );
            expect(IconTheme.of(tester.element(icon)).size, 13);
            expect(
              IconTheme.of(tester.element(icon)).color,
              Color.lerp(tokens.background, tokens.foreground, .32),
            );
          }
          expect(tester.getRect(reply).left - tester.getRect(more).right, 4);
          await _capture(
            tester,
            key,
            'post-actions-${dark ? 'dark' : 'light'}-${glass ? 'glass' : 'standard'}-rest',
          );
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(reply));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          final icon = find.descendant(of: reply, matching: find.byType(DIcon));
          expect(
            IconTheme.of(tester.element(icon)).color,
            Color.lerp(tokens.background, tokens.foreground, .62),
          );
          expect(
            buttonSurface(tester, of: reply).borderColor,
            Colors.transparent,
          );
          expect(
            buttonSurface(tester, of: reply).color,
            glass
                ? Colors.transparent
                : tokens.foreground.withValues(alpha: .08),
          );
          final lens = find.descendant(
            of: reply,
            matching: find.byType(LiquidGlass),
          );
          if (glass) {
            expectStockGlass(tester, lens);
          } else {
            expect(lens, findsNothing);
          }
          await _capture(
            tester,
            key,
            'post-actions-${dark ? 'dark' : 'light'}-${glass ? 'glass' : 'standard'}-hover',
          );
          final primitive = find.descendant(
            of: reply,
            matching: find.byType(FilledButton),
          );
          await mouse.down(tester.getCenter(reply));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          expect(
            (tester.getBottomRight(primitive) - tester.getTopLeft(primitive))
                .dx,
            closeTo(27.6, .01),
          );
          await mouse.cancel();
          await tester.pumpAndSettle();
          await mouse.removePointer();
          await tester.tapAt(
            Offset(
              tester.getRect(more).right + 2,
              tester.getRect(more).center.dy,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DDropdownMenuContent), findsNothing);
          expect(shell.visibleComposer, isNull);
          await tester.tap(more);
          await tester.pumpAndSettle();
          expect(find.byType(DDropdownMenuContent), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(shell.visibleComposer!.target.replyToPostNumber, 1);
          await mount(scale: 2, platform: TargetPlatform.iOS, reduced: true);
          await tester.pumpAndSettle();
          expect(tester.getSize(reply).height, greaterThan(30));
          expect(tester.getRect(reply).left - tester.getRect(more).right, 4);
          expect(
            tester
                .widget<AnimatedScale>(
                  find.descendant(
                    of: reply,
                    matching: find.byType(AnimatedScale),
                  ),
                )
                .duration,
            Duration.zero,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['POST_ACTION_RENDER_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
