import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/shell/topic_viewport_coordinator.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Lato')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });
  testWidgets('compact navigation fits narrow and enlarged layouts', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
          tester.view.physicalSize = const Size(320, 640);
          final shell = await _loadShell(FakeDiscourseApi(user: _user));
          await _openProgress(
            tester,
            shell,
            TargetPlatform.macOS,
            dark: dark,
            scale: scale,
            direction: direction,
          );
          expect(find.text('Topic progress'), findsNothing);
          final panel = tester.getRect(find.byType(DPopoverContent));
          for (final label in ['First post', 'Latest post']) {
            final button = find.widgetWithText(DButton, label);
            final bounds = tester.getRect(button);
            expect(panel.contains(bounds.topLeft), isTrue);
            expect(panel.contains(bounds.bottomRight), isTrue);
          }
          expect(find.text('Jump'), findsNothing);
          expect(panel.width, 300);
          if (scale == 1) {
            // The 168 frame and one line of the post's words, 12.5 at 1.4
            // with 2 above and below.
            expect(panel.height, closeTo(168 + 12.5 * 1.4 + 4, 1));
            final first = tester.getRect(
              find.widgetWithText(DButton, 'First post'),
            );
            final last = tester.getRect(
              find.widgetWithText(DButton, 'Latest post'),
            );
            expect(first.top, last.top);
          }
          for (final label in ['First post', 'Latest post']) {
            expect(
              tester
                  .widget<DButton>(find.widgetWithText(DButton, label))
                  .variant,
              DButtonVariant.ghost,
            );
            expect(
              tester
                  .widget<DButton>(find.widgetWithText(DButton, label))
                  .density,
              DButtonDensity.timelineEnd,
            );
          }
          await _capture(
            tester,
            'panel-${dark ? 'dark' : 'light'}-$scale-${direction.name}',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(DPopoverContent), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    }
  });

  testWidgets('phone sheet respects consumed safe areas and swipes away', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    final shell = await _loadShell(FakeDiscourseApi(user: _user));
    await _openProgress(
      tester,
      shell,
      TargetPlatform.iOS,
      consumeSafeArea: true,
    );
    final panel = tester.getRect(find.byType(DSheetContent));
    expect(panel.left, 0);
    expect(panel.right, 390);
    expect(panel.bottom, 844);
    final handle = find.byKey(const ValueKey('sheet-drag-handle'));
    expect(tester.getSize(handle), const Size(36, 5));
    final revision = shell.topicNavigationRevision;
    await tester.drag(
      handle,
      const Offset(0, 12),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsOneWidget);
    expect(tester.getRect(find.byType(DSheetContent)), panel);
    await tester.drag(
      handle,
      const Offset(0, 150),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsNothing);
    expect(shell.topicNavigationRevision, revision);
    await tester.tap(find.byKey(const ValueKey('topic-progress-button')));
    await tester.pumpAndSettle();
    expect(_selection('2 / 3'), findsOneWidget);
    final above = Offset(panel.center.dx, panel.top - 40);
    await tester.dragFrom(
      above,
      const Offset(0, 180),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsNothing);
    expect(shell.topicNavigationRevision, revision);
    await tester.tap(find.byKey(const ValueKey('topic-progress-button')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(3, 100));
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline metadata and controls fit both materials and routes', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          for (final direction in TextDirection.values) {
            final shell = await _loadShell(FakeDiscourseApi(user: _user));
            await _openProgress(
              tester,
              shell,
              platform,
              dark: dark,
              scale: scale,
              direction: direction,
            );
            expect(find.text('sam'), findsOneWidget);
            expect(find.text('17 May 2026'), findsNWidgets(2));
            expect(find.text('14 October 2026'), findsOneWidget);
            expect(
              tester.getSize(find.byType(DAvatar)),
              Size(32 * scale, 32 * scale),
            );
            final panel = tester.getRect(_panelFinder(platform));
            for (final label in ['First post', 'Latest post']) {
              final button = find.widgetWithText(DButton, label);
              final rect = tester.getRect(button);
              expect(panel.contains(rect.topLeft), isTrue);
              expect(panel.contains(rect.bottomRight), isTrue);
              expect(
                rect.height,
                closeTo(
                  (34 + 12.5 * (scale - 1) * 1.5) *
                      (platform == TargetPlatform.macOS ? 1 : 17 / 13),
                  .01,
                ),
              );
            }
            await _capture(
              tester,
              '${platform.name}-flat-${dark ? 'dark' : 'light'}-$scale-${direction.name}',
            );
            await tester.tap(find.text('First post'));
            await tester.pumpAndSettle();
            expect(shell.currentContent?.postNumber, 1);
            if (platform == TargetPlatform.macOS) {
              expect(
                tester
                    .widget<DButton>(find.widgetWithText(DButton, 'First post'))
                    .onPressed,
                isNull,
              );
              expect(_selection('1 / 3'), findsOneWidget);
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
            }
            expect(_panelFinder(platform), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    }
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    final mobile = platform != TargetPlatform.macOS;
    group(platform.name, () {
      testWidgets('a drag shorter than a load fetches only its release', (
        tester,
      ) async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          user: _user,
          postGate: gate,
          postsById: const {200: _target},
        );
        final shell = await _loadShell(api, cacheTarget: false);
        await _openProgress(tester, shell, platform);
        final revision = shell.topicNavigationRevision;
        final slider = tester.getRect(find.byType(DMultiSlider));
        final gesture = await tester.startGesture(
          slider.center,
          kind: mobile ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(Offset(slider.right - 7, slider.center.dy));
        await tester.pump();
        expect(_selection('3 / 3'), findsOneWidget);
        expect(shell.currentContent?.postNumber, 1);
        expect(shell.topicNavigationRevision, revision);
        expect(api.postFetches, isEmpty);

        await gesture.moveTo(slider.center);
        await tester.pump();
        expect(_selection('2 / 3'), findsOneWidget);
        expect(api.postFetches, isEmpty);
        expect(_panelFinder(platform), findsOneWidget);
        await gesture.up();
        await tester.pump();
        expect(api.postFetches, [
          [200],
        ]);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.postNumber, 1);
        expect(_panelFinder(platform), mobile ? findsNothing : findsOneWidget);
        gate.complete();
        await tester.pumpAndSettle();
        expect(shell.currentContent?.postNumber, _target.postNumber);
        expect(_panelFinder(platform), mobile ? findsNothing : findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      group('a drag moves the topic', () {
        const last = Post(
          id: 300,
          postNumber: 12,
          username: 'sam',
          cooked: '<p>Last</p>',
        );
        const loadInterval = Duration(milliseconds: 121);

        PointerDeviceKind pointer() =>
            mobile ? PointerDeviceKind.touch : PointerDeviceKind.mouse;
        Offset toEnd(Rect slider) => Offset(slider.right - 7, slider.center.dy);
        Offset toStart(Rect slider) =>
            Offset(slider.left + 7, slider.center.dy);

        testWidgets('a position already laid out moves at once, with no load', (
          tester,
        ) async {
          final viewport = _ScrubViewport(shows: {3});
          final api = FakeDiscourseApi(user: _user);
          final shell = await _loadShell(api);
          await _openProgress(tester, shell, platform, viewport: viewport);
          final revision = shell.topicNavigationRevision;
          final slider = tester.getRect(find.byType(DMultiSlider));
          final gesture = await tester.startGesture(
            slider.center,
            kind: pointer(),
          );
          await tester.pump();

          await gesture.moveTo(toEnd(slider));
          await tester.pump();

          expect(viewport.shown, [3]);
          expect(viewport.began, 1);
          expect(_selection('3 / 3'), findsOneWidget);

          await tester.pump(loadInterval * 2);
          expect(api.postFetches, isEmpty);
          expect(shell.topicNavigationRevision, revision);
          await gesture.cancel();
          await tester.pumpAndSettle();
        });

        testWidgets(
          'anywhere else loads the newest position, one load at a time',
          (tester) async {
            final gate = Completer<void>();
            final api = FakeDiscourseApi(
              user: _user,
              postGate: gate,
              postsById: const {200: _target, 300: last},
            );
            final shell = await _loadShell(api, cacheTarget: false);
            await _openProgress(tester, shell, platform);
            final route = shell.currentContent;
            final slider = tester.getRect(find.byType(DMultiSlider));
            final gesture = await tester.startGesture(
              slider.center,
              kind: pointer(),
            );
            await tester.pump();

            await gesture.moveTo(toEnd(slider));
            await tester.pump();
            expect(api.postFetches, isEmpty);
            await tester.pump(loadInterval);
            expect(api.postFetches, [
              [200, 300],
            ]);

            // Positions passed while it is out are never themselves fetched.
            await gesture.moveTo(toStart(slider));
            await tester.pump(loadInterval);
            await gesture.moveTo(slider.center);
            await tester.pump(loadInterval);
            expect(api.postFetches, hasLength(1));
            expect(shell.currentContent, same(route));
            expect(_selection('2 / 3'), findsOneWidget);

            // The load that lands was for a position the drag has left.
            gate.complete();
            await tester.pump();
            await tester.pump();
            expect(shell.currentContent, same(route));

            // Its posts were kept, so reaching the newest needs no request.
            await tester.pump(loadInterval);
            await tester.pump();
            expect(api.postFetches, hasLength(1));
            expect(shell.currentContent?.postNumber, _target.postNumber);

            await gesture.up();
            await tester.pumpAndSettle();
            expect(shell.currentContent?.postNumber, _target.postNumber);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets('a load between the reader and the drag still moves it', (
          tester,
        ) async {
          final gate = Completer<void>();
          final api = FakeDiscourseApi(
            user: _user,
            postGate: gate,
            postsById: const {200: _target, 300: last},
          );
          final shell = await _loadShell(api, cacheTarget: false);
          await _openProgress(tester, shell, platform, position: 1);
          final slider = tester.getRect(find.byType(DMultiSlider));
          final gesture = await tester.startGesture(
            toStart(slider),
            kind: pointer(),
          );
          await tester.pump();
          await gesture.moveTo(slider.center);
          await tester.pump(loadInterval);
          expect(api.postFetches, hasLength(1));

          // The drag runs ahead of the network, in the same direction.
          await gesture.moveTo(toEnd(slider));
          await tester.pump();
          gate.complete();
          await tester.pump();
          await tester.pump();
          expect(shell.currentContent?.postNumber, _target.postNumber);

          await tester.pump(loadInterval);
          await tester.pump();
          expect(shell.currentContent?.postNumber, last.postNumber);
          await gesture.cancel();
          await tester.pumpAndSettle();
        });

        testWidgets('a release lands exactly on its post over a pending load', (
          tester,
        ) async {
          final gate = Completer<void>();
          final api = FakeDiscourseApi(
            user: _user,
            postGate: gate,
            postsById: const {200: _target, 300: last},
          );
          final shell = await _loadShell(api, cacheTarget: false);
          await _openProgress(tester, shell, platform);
          final slider = tester.getRect(find.byType(DMultiSlider));
          final gesture = await tester.startGesture(
            slider.center,
            kind: pointer(),
          );
          await tester.pump();

          await gesture.moveTo(toEnd(slider));
          await tester.pump(loadInterval);
          expect(api.postFetches, hasLength(1));
          await gesture.moveTo(slider.center);
          await tester.pump();

          await gesture.up();
          await tester.pump();
          gate.complete();
          await tester.pumpAndSettle();

          expect(shell.currentContent?.postNumber, _target.postNumber);
          expect(tester.takeException(), isNull);
        });

        testWidgets('reading stays off until the release has landed', (
          tester,
        ) async {
          final gate = Completer<void>();
          final viewport = _ScrubViewport();
          final api = FakeDiscourseApi(
            user: _user,
            postGate: gate,
            postsById: const {200: _target},
          );
          final shell = await _loadShell(api, cacheTarget: false);
          await _openProgress(tester, shell, platform, viewport: viewport);
          final slider = tester.getRect(find.byType(DMultiSlider));
          final gesture = await tester.startGesture(
            slider.center,
            kind: pointer(),
          );
          await tester.pump();
          await gesture.moveTo(toEnd(slider));
          await tester.pump();
          await gesture.moveTo(slider.center);
          await tester.pump();
          expect(viewport.began, 1);

          await gesture.up();
          await tester.pumpAndSettle();
          expect(
            _panelFinder(platform),
            mobile ? findsNothing : findsOneWidget,
          );
          expect(viewport.ended, 0);

          gate.complete();
          await tester.pumpAndSettle();
          expect(viewport.ended, 1);
          expect(shell.currentContent?.postNumber, _target.postNumber);
        });

        testWidgets('a panel removed mid-drag returns to where it began', (
          tester,
        ) async {
          final viewport = _ScrubViewport(origin: true);
          final shell = await _loadShell(FakeDiscourseApi(user: _user));
          await _openProgress(tester, shell, platform, viewport: viewport);
          final slider = tester.getRect(find.byType(DMultiSlider));
          final gesture = await tester.startGesture(
            slider.center,
            kind: pointer(),
          );
          await tester.pump();
          await gesture.moveTo(toEnd(slider));
          await tester.pump();

          await tester.pumpWidget(const SizedBox.shrink());

          expect(viewport.restored, 1);
          expect(viewport.ended, 1);
          await gesture.cancel();
        });

        if (!mobile) {
          testWidgets('a new drag cannot be pulled off by an earlier release', (
            tester,
          ) async {
            final gate = Completer<void>();
            final viewport = _ScrubViewport(shows: {1});
            final api = FakeDiscourseApi(
              user: _user,
              postGate: gate,
              postsById: const {200: _target},
            );
            final shell = await _loadShell(api, cacheTarget: false);
            await _openProgress(tester, shell, platform, viewport: viewport);
            final route = shell.currentContent;
            final slider = tester.getRect(find.byType(DMultiSlider));
            final first = await tester.startGesture(
              slider.center,
              kind: pointer(),
            );
            await tester.pump();
            await first.moveTo(toEnd(slider));
            await tester.pump();
            await first.moveTo(slider.center);
            await tester.pump();
            await first.up();
            await tester.pump();
            expect(api.postFetches, hasLength(1));

            final second = await tester.startGesture(
              slider.center,
              kind: pointer(),
            );
            await tester.pump();
            await second.moveTo(toStart(slider));
            await tester.pump();
            expect(viewport.shown, [1]);

            gate.complete();
            await tester.pump();
            await tester.pump();

            expect(shell.currentContent, same(route));
            expect(
              find.text('Could not open that post. Try again.'),
              findsNothing,
            );
            await second.cancel();
            await tester.pumpAndSettle();
          });
        }

        testWidgets('a cancelled drag goes back to where it began', (
          tester,
        ) async {
          final viewport = _ScrubViewport(origin: true);
          final shell = await _loadShell(FakeDiscourseApi(user: _user));
          await _openProgress(tester, shell, platform, viewport: viewport);
          final route = shell.currentContent;
          final slider = tester.getRect(find.byType(DMultiSlider));
          final gesture = await tester.startGesture(
            slider.center,
            kind: pointer(),
          );
          await tester.pump();
          await gesture.moveTo(toEnd(slider));
          await tester.pump();

          await gesture.cancel();
          await tester.pumpAndSettle();

          expect(viewport.restored, 1);
          expect(viewport.ended, 1);
          expect(shell.currentContent, same(route));
          expect(_selection('2 / 3'), findsOneWidget);
        });

        testWidgets('a cancelled drag reloads an origin it moved away from', (
          tester,
        ) async {
          final api = FakeDiscourseApi(
            user: _user,
            postsById: const {300: last},
          );
          final shell = await _loadShell(api);
          await _openProgress(tester, shell, platform);
          final slider = tester.getRect(find.byType(DMultiSlider));
          final gesture = await tester.startGesture(
            slider.center,
            kind: pointer(),
          );
          await tester.pump();
          await gesture.moveTo(toEnd(slider));
          await tester.pump(loadInterval);
          await tester.pump();
          expect(shell.currentContent?.postNumber, last.postNumber);

          await gesture.cancel();
          await tester.pumpAndSettle();

          expect(shell.currentContent?.postNumber, _target.postNumber);
          expect(_selection('2 / 3'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      testWidgets('cancelled drag restores the preview without navigating', (
        tester,
      ) async {
        final api = FakeDiscourseApi(user: _user);
        final shell = await _loadShell(api);
        await _openProgress(tester, shell, platform);
        final revision = shell.topicNavigationRevision;
        final slider = tester.getRect(find.byType(DMultiSlider));
        final gesture = await tester.startGesture(
          slider.center,
          kind: mobile ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
        );
        await gesture.moveTo(Offset(slider.right - 7, slider.center.dy));
        await tester.pump();
        expect(_selection('3 / 3'), findsOneWidget);
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(_selection('2 / 3'), findsOneWidget);
        expect(shell.currentContent?.postNumber, 1);
        expect(shell.topicNavigationRevision, revision);
        expect(api.postFetches, isEmpty);
      });

      testWidgets('keyboard steps still navigate immediately', (tester) async {
        final shell = await _loadShell(FakeDiscourseApi(user: _user));
        await _openProgress(tester, shell, platform);
        await tester.tap(find.text('First post'));
        await tester.pumpAndSettle();
        if (mobile) await _reopenProgress(tester);
        await tester.tap(find.byType(DMultiSlider));
        await tester.pumpAndSettle();
        expect(shell.currentContent?.postNumber, _target.postNumber);
        if (mobile) await _reopenProgress(tester);
        final thumbFocus = find.descendant(
          of: find.byType(DMultiSlider),
          matching: find.byWidgetPredicate(
            (widget) => widget is Focus && widget.onKeyEvent != null,
          ),
        );
        tester.widget<Focus>(thumbFocus).focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.postNumber, 1);
        expect(_panelFinder(platform), mobile ? findsNothing : findsOneWidget);
        if (!mobile) expect(_selection('1 / 3'), findsOneWidget);
      });

      for (final change in [
        'site',
        'topic',
        'tab',
        'account',
        'account session',
        'topic round trip',
      ]) {
        testWidgets('an open progress route rejects a changed $change', (
          tester,
        ) async {
          final shell = await _loadShell(FakeDiscourseApi(user: _user));
          await _openProgress(tester, shell, platform);
          final openingTab = shell.activeTabId;
          switch (change) {
            case 'site':
              shell.selectInstance(1);
              _openTopic(shell);
            case 'topic':
              _openTopic(shell, topicId: 2);
            case 'tab':
              shell.createTab();
              _openTopic(shell);
            case 'account':
              await shell.disconnectCurrentInstance();
              _storeTopics(shell, _siteUrl);
              _openTopic(shell);
            case 'account session':
              // Retire the account lease while retaining the same site, topic,
              // tab and visible account identity, as a same-account reconnect can.
              shell.lifecycle.invalidate(_siteUrl);
              expect(shell.activeTabId, openingTab);
            case 'topic round trip':
              _openTopic(shell, topicId: 2);
              expect(shell.handleBack(), isTrue);
          }
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('topic-progress-selection')),
            findsOneWidget,
          );
          final source = shell.currentContent;
          final revision = shell.topicNavigationRevision;

          await _scrubToMiddle(tester, platform);
          await tester.pumpAndSettle();

          expect(shell.currentContent, same(source));
          expect(shell.topicNavigationRevision, revision);
          expect(
            find.byKey(const ValueKey('topic-progress-selection')),
            findsOneWidget,
          );
          expect(
            find.text(
              'Close and reopen topic progress to jump in the current topic.',
            ),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('topic-progress-button')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      }

      for (final dismissal
          in mobile ? ['slider release'] : ['Escape', 'barrier']) {
        testWidgets('late success after $dismissal preserves a new route', (
          tester,
        ) async {
          final gate = Completer<void>();
          final api = FakeDiscourseApi(
            user: _user,
            postGate: gate,
            postsById: const {200: _target},
          );
          final shell = await _loadShell(api, cacheTarget: false);
          final navigator = await _openProgress(tester, shell, platform);

          await _scrubToMiddle(tester, platform);
          await tester.pump();
          expect(api.postFetches, [
            [200],
          ]);
          expect(shell.currentContent?.postNumber, 1);

          if (dismissal == 'Escape') {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else if (dismissal == 'barrier') {
            await tester.tapAt(const Offset(5, 5));
          }
          await tester.pumpAndSettle();
          expect(_panelFinder(platform), findsNothing);

          unawaited(
            navigator.push<void>(
              DialogRoute<void>(
                context: navigator.context,
                builder: (_) =>
                    const AlertDialog(content: Text('Replacement route')),
              ),
            ),
          );
          await tester.pump();

          expect(find.text('Replacement route'), findsOneWidget);

          gate.complete();
          await tester.pumpAndSettle();

          // The real controller successfully resolves the unloaded stream ID;
          // only the dismissed editor's completion must be inert.
          expect(shell.currentContent?.postNumber, _target.postNumber);
          expect(find.text('Replacement route'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('topic-progress-selection')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('late completion cannot close a reopened panel', (
        tester,
      ) async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          user: _user,
          postGate: gate,
          postsById: const {200: _target},
        );
        final shell = await _loadShell(api, cacheTarget: false);
        await _openProgress(tester, shell, platform);
        await _scrubToMiddle(tester, platform);
        await tester.pump();
        if (!mobile) await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await _reopenProgress(tester);
        gate.complete();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topic-progress-selection')),
          findsOneWidget,
        );
        expect(_selection('2 / 3'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('newer scrubs supersede a pending unloaded post', (
        tester,
      ) async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          user: _user,
          postGate: gate,
          postsById: const {200: _target},
        );
        final shell = await _loadShell(api, cacheTarget: false);
        await _openProgress(tester, shell, platform);
        await _scrubToMiddle(tester, platform);
        expect(api.postFetches, [
          [200],
        ]);
        if (mobile) {
          await tester.pumpAndSettle();
          expect(_panelFinder(platform), findsNothing);
          await _reopenProgress(tester);
        }
        expect(_selection('2 / 3'), findsOneWidget);
        await tester.tap(find.text('First post'));
        await tester.pumpAndSettle();
        expect(_panelFinder(platform), mobile ? findsNothing : findsOneWidget);
        if (!mobile) expect(_selection('1 / 3'), findsOneWidget);
        expect(shell.currentContent?.postNumber, 1);
        final revision = shell.topicNavigationRevision;
        gate.complete();
        await tester.pumpAndSettle();
        expect(shell.currentContent?.postNumber, 1);
        expect(shell.topicNavigationRevision, revision);
        if (!mobile) expect(_selection('1 / 3'), findsOneWidget);
        expect(find.text('Could not open that post. Try again.'), findsNothing);
        expect(_panelFinder(platform), mobile ? findsNothing : findsOneWidget);
      });

      for (final action in ['First post', 'Latest post']) {
        testWidgets(
          '$action jumps and ${mobile ? 'dismisses the sheet' : 'keeps the popover open'}',
          (tester) async {
            final gate = Completer<void>();
            final api = FakeDiscourseApi(
              user: _user,
              postGate: gate,
              postsById: const {
                300: Post(
                  id: 300,
                  postNumber: 12,
                  username: 'sam',
                  cooked: '<p>Last</p>',
                ),
              },
            );
            final shell = await _loadShell(api);
            await _openProgress(tester, shell, platform);
            await tester.tap(find.text(action));
            await tester.pumpAndSettle();
            expect(
              _panelFinder(platform),
              mobile ? findsNothing : findsOneWidget,
            );
            expect(shell.currentContent?.postNumber, 1);
            expect(
              api.postFetches,
              action == 'First post'
                  ? isEmpty
                  : [
                      [300],
                    ],
            );
            gate.complete();
            await tester.pumpAndSettle();
            expect(
              shell.currentContent?.postNumber,
              action == 'First post' ? 1 : 12,
            );
            expect(
              _panelFinder(platform),
              mobile ? findsNothing : findsOneWidget,
            );
            if (!mobile) {
              expect(
                _selection(action == 'First post' ? '1 / 3' : '3 / 3'),
                findsOneWidget,
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }

      testWidgets('an unchanged source can retry a failed lookup and jump', (
        tester,
      ) async {
        final responses = <int, Post>{};
        final api = FakeDiscourseApi(user: _user, postsById: responses);
        final shell = await _loadShell(api, cacheTarget: false);
        await _openProgress(tester, shell, platform);

        await _scrubToMiddle(tester, platform);
        await tester.pumpAndSettle();

        expect(_panelFinder(platform), mobile ? findsNothing : findsOneWidget);
        if (mobile) {
          await _reopenProgress(tester);
        } else {
          expect(
            find.text('Could not open that post. Try again.'),
            findsOneWidget,
          );
        }
        expect(shell.currentContent?.postNumber, 1);

        responses[200] = _target;
        await _scrubToMiddle(tester, platform);
        await tester.pumpAndSettle();

        expect(api.postFetches, [
          [200],
          [200],
        ]);
        expect(shell.currentContent?.postNumber, _target.postNumber);
        expect(_panelFinder(platform), mobile ? findsNothing : findsOneWidget);
        expect(
          find.byKey(const ValueKey('topic-progress-button')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    });
  }
}

const _siteUrl = 'https://meta.example';

final class _ScrubViewport implements TopicScrubViewport {
  _ScrubViewport({this.shows = const {}, this.origin = false});

  final Set<int> shows;
  final bool origin;
  final shown = <int>[];
  int began = 0;
  int ended = 0;
  int restored = 0;

  @override
  Object beginScrub() {
    began++;
    return this;
  }

  @override
  void endScrub(Object scrub) => ended++;

  @override
  bool showScrubPosition(int position) {
    if (!shows.contains(position)) return false;
    shown.add(position);
    return true;
  }

  @override
  bool restoreScrubOrigin() {
    if (origin) restored++;
    return origin;
  }
}

Future<void> _reopenProgress(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('topic-progress-button')));
  await tester.pumpAndSettle();
  expect(_selection('2 / 3'), findsOneWidget);
}

Future<void> _scrubToMiddle(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  // Move away first: like a real controlled range input, an unchanged thumb
  // does not emit onChanged. Returning to the middle also permits a retry.
  await tester.tap(find.text('First post'));
  await tester.pumpAndSettle();
  if (platform != TargetPlatform.macOS &&
      _panelFinder(platform).evaluate().isEmpty) {
    await _reopenProgress(tester);
  }
  await tester.tap(find.byType(DMultiSlider));
  await tester.pump();
}

const _user = DiscourseUser(id: 1, username: 'sam');
const _target = Post(
  id: 200,
  postNumber: 7,
  username: 'sam',
  cooked: '<p>Target</p>',
);

Future<ShellController> _loadShell(
  FakeDiscourseApi api, {
  bool cacheTarget = true,
}) async {
  final sites = [
    instance('meta.example').copyWith(user: _user),
    instance('other.example').copyWith(user: _user),
  ];
  final shell = ShellController(
    instanceStore: FakeInstanceStore(sites),
    api: api,
    authenticator: FakeAuthenticator()
      ..keys.addAll({for (final site in sites) site.url: 'key'}),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  for (final site in sites) {
    _storeTopics(shell, site.url, cacheTarget: cacheTarget);
  }
  _openTopic(shell);
  return shell;
}

void _storeTopics(
  ShellController shell,
  String siteUrl, {
  bool cacheTarget = true,
}) {
  for (final topicId in [1, 2]) {
    final firstId = topicId == 1 ? 100 : 400;
    shell.store
      ..put(
        siteUrl,
        TopicDetail(
          id: topicId,
          title: 'Topic $topicId',
          stream: [firstId, firstId + 100, firstId + 200],
          postsCount: 3,
          createdAt: DateTime(2026, 5, 17),
          lastPostedAt: DateTime(2026, 10, 14),
        ),
      )
      ..put(
        siteUrl,
        Post(
          id: firstId,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First</p>',
          createdAt: DateTime(2026, 5, 17),
        ),
      );
    if (cacheTarget) {
      shell.store.put(
        siteUrl,
        Post(
          id: firstId + 100,
          postNumber: _target.postNumber,
          username: 'sam',
          cooked: '<p>Target</p>',
          createdAt: DateTime(2026, 5, 17),
        ),
      );
    }
  }
}

void _openTopic(ShellController shell, {int topicId = 1}) => shell.pushContent(
  ContentRoute.topic(
    topicId: topicId,
    slug: 'topic-$topicId',
    title: 'Topic $topicId',
    postNumber: 1,
  ),
);

Future<NavigatorState> _openProgress(
  WidgetTester tester,
  ShellController shell,
  TargetPlatform platform, {
  bool dark = false,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  bool consumeSafeArea = false,
  TopicScrubViewport? viewport,
  int position = 2,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
        platform: platform,
        textTheme: (dark ? AppTheme.dark : AppTheme.light).textTheme.apply(
          fontFamily: 'Lato',
        ),
      ),
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('timeline-capture'),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(textDirection: direction, child: child!),
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          top: consumeSafeArea,
          bottom: consumeSafeArea,
          child: Align(
            alignment: Alignment.bottomRight,
            child: TopicProgressPopover(
              controller: shell,
              position: position,
              total: 3,
              floating: platform == TargetPlatform.macOS,
              viewport: viewport,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('topic-progress-button')));
  await tester.pumpAndSettle();
  expect(_selection('$position / 3'), findsOneWidget);
  expect(_panelFinder(platform), findsOneWidget);
  expect(find.byType(Dialog), findsNothing);
  expect(find.byType(BottomSheet), findsNothing);
  expect(
    tester.getRect(_panelFinder(platform)).bottom,
    platform == TargetPlatform.macOS
        ? lessThanOrEqualTo(
            tester
                .getRect(find.byKey(const ValueKey('topic-progress-button')))
                .top,
          )
        : lessThanOrEqualTo(
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
          ),
  );
  return navigatorKey.currentState!;
}

Finder _selection(String text) => find.descendant(
  of: find.byType(TopicProgressPanel),
  matching: find.text(text),
);

Finder _panelFinder(TargetPlatform platform) => platform == TargetPlatform.macOS
    ? find.byType(DPopoverContent)
    : find.byType(DSheetContent);

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['TOPIC_PROGRESS_CAPTURE_DIR'];
  if (output == null) return;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('timeline-capture')),
        )
        .toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
