import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    for (final dark in [false, true]) {
      testWidgets('profile avatar matches mockup on $platform, dark $dark', (
        tester,
      ) async {
        const user = DiscourseUser(id: 7, username: 'reader');
        final controller = ShellController(
          instanceStore: FakeInstanceStore([
            instance('meta.example').copyWith(user: user),
          ]),
          api: FakeDiscourseApi(user: user),
          authenticator: FakeAuthenticator()
            ..keys['https://meta.example'] = 'key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updater: FakeUpdater(),
          updateStore: FakeUpdateStore(),
        );
        await controller.load();
        addTearDown(controller.dispose);
        final theme = (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: platform,
        );
        const captureKey = ValueKey('account-controls-paint');
        final semantics = tester.ensureSemantics();
        try {
          for (final scale in [1.0, 2.0]) {
            await tester.pumpWidget(
              ShellScope(
                controller: controller,
                child: MaterialApp(
                  theme: theme,
                  home: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: const Scaffold(
                      body: Center(
                        child: RepaintBoundary(
                          key: captureKey,
                          child: UserMenuButton(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final button = find.byKey(UserMenuButton.avatarKey);
            final bounds = tester.getRect(button);
            final avatar = find.descendant(
              of: button,
              matching: find.byType(DAvatar),
            );
            expect(bounds.size, Size.square(32 * scale));
            expect(tester.getRect(avatar), bounds.deflate(2));
            expect(tester.getSemantics(button).rect.size, bounds.size);

            Future<void> checkPaint() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(captureKey),
              );
              final top =
                  bounds.topCenter - tester.getTopLeft(find.byKey(captureKey));
              final bytes = await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 4);
                try {
                  return (
                    data: (await image.toByteData(
                      format: ui.ImageByteFormat.rawRgba,
                    ))!,
                    width: image.width,
                  );
                } finally {
                  image.dispose();
                }
              });
              // The first two pixels are one solid border. The next pixel is
              // the avatar itself, with neither a surface gap nor a second edge.
              final tokens = DTokens.of(tester.element(button));
              for (final (inset, color) in [
                (.5, tokens.border),
                (1.5, tokens.border),
                (2.5, theme.colorScheme.primary),
              ]) {
                final x = (top.dx * 4).round();
                final y = ((top.dy + inset) * 4).round();
                final offset = (y * bytes!.width + x) * 4;
                final expected = [color.r, color.g, color.b, color.a];
                for (var channel = 0; channel < 4; channel++) {
                  expect(
                    bytes.data.getUint8(offset + channel),
                    closeTo(expected[channel] * 255, 1),
                    reason: 'Profile pixel at inset $inset, channel $channel',
                  );
                }
              }
            }

            await checkPaint();
            if (platform == TargetPlatform.macOS) {
              final mouse = await tester.createGesture(
                kind: PointerDeviceKind.mouse,
              );
              await mouse.addPointer(location: Offset.zero);
              await mouse.moveTo(bounds.center);
              await tester.pump();
              await checkPaint();
              await mouse.removePointer();
              await tester.pumpAndSettle();
            }
            if (platform == TargetPlatform.macOS) {
              await tester.tap(button);
              await tester.pumpAndSettle();
              await checkPaint();
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
          }
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
