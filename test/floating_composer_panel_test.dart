import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/composer_geometry_store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_link.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('panel geometry and hit testing', () {
    testWidgets('formatting menu applies a mark to the selected text', (
      tester,
    ) async {
      final composer = ComposerController(_replyTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.value = const TextEditingValue(
        text: 'One word',
        selection: TextSelection(baseOffset: 4, extentOffset: 8),
      );
      await _pumpFloatingPanel(tester, shell, composer);
      await tester.tap(find.byKey(const ValueKey('composer-formatting')));
      await tester.pump();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Italic'));
      await tester.pumpAndSettle();
      expect(composer.raw, 'One *word*');
      expect(find.widgetWithText(MenuItemButton, 'Italic'), findsNothing);
    });

    testWidgets('the focused grip moves the composer with arrow keys', (
      tester,
    ) async {
      final composer = ComposerController(_replyTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);
      final before = tester.getRect(find.byType(ComposerPanel));
      final grip = find.byKey(const ValueKey('composer-move-control'));
      Focus.of(tester.element(grip)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        tester.getRect(find.byType(ComposerPanel)),
        before.shift(const Offset(-8, -8)),
      );
    });

    testWidgets('Linux formatting hints match their keyboard actions', (
      tester,
    ) async {
      await _withTargetPlatform(TargetPlatform.linux, () async {
        final composer = ComposerController(_replyTarget);
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpFloatingPanel(tester, shell, composer);
        await tester.tap(find.byKey(const ValueKey('composer-formatting')));
        await tester.pump();

        const actions = [
          ('Bold', LogicalKeyboardKey.keyB, '**format** me'),
          ('Italic', LogicalKeyboardKey.keyI, '*format* me'),
          ('Inline code', LogicalKeyboardKey.keyE, '`format` me'),
          ('Link', LogicalKeyboardKey.keyL, null),
        ];
        double? shortcutRight;
        for (final (label, key, _) in actions) {
          final item = find.widgetWithText(MenuItemButton, label);
          final hint = find.descendant(
            of: item,
            matching: find.text('Ctrl+${key.keyLabel}'),
          );
          expect(hint, findsOneWidget);
          final bounds = tester.getRect(hint);
          shortcutRight ??= bounds.right;
          expect(bounds.right, closeTo(shortcutRight, 0.1));
          expect(
            bounds.left,
            greaterThan(tester.getRect(find.text(label)).right),
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        composer.focus.requestFocus();

        for (final (_, key, raw) in actions) {
          composer.text.value = const TextEditingValue(
            text: 'format me',
            selection: TextSelection(baseOffset: 0, extentOffset: 6),
          );
          await tester.pump();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(key);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          if (raw != null) {
            expect(composer.raw, raw);
          } else {
            expect(
              find.byKey(const ValueKey('composer-link-dialog')),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('composer-link-anchor')),
                  )
                  .controller!
                  .text,
              'format',
            );
          }
        }
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets(
      'reply context expands without covering the editor and follows post visibility',
      (tester) async {
        final composer = ComposerController(_replyTarget);
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        const post = Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First paragraph.</p><p>Second paragraph.</p>',
        );
        shell.store.put(_replyTarget.siteUrl, post);
        shell.store.put(
          _replyTarget.siteUrl,
          const TopicDetail(id: 7, title: 'A topic', stream: [1]),
        );
        await _pumpFloatingPanel(tester, shell, composer);
        final context = find.byKey(const ValueKey('composer-reply-context'));
        final excerpt = find.byKey(const ValueKey('composer-context-excerpt'));
        expect(find.text('Replying to '), findsOneWidget);
        expect(find.text('@sam'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('composer-reply-avatar')),
          findsOneWidget,
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('composer-title'))).top,
          greaterThan(tester.getRect(find.text('@sam')).bottom),
        );
        expect(excerpt, findsNothing);
        await tester.tap(context);
        await tester.pump();
        expect(find.text('First paragraph. Second paragraph.'), findsOneWidget);
        expect(
          tester.getRect(excerpt).bottom,
          lessThan(tester.getRect(find.byType(ComposerEditor)).top),
        );
        expect(
          tester.getSize(find.byType(ComposerEditor)).height,
          greaterThan(30),
        );

        shell.store.put(_replyTarget.siteUrl, post.copyWith(hidden: true));
        await tester.pump();
        expect(excerpt, findsNothing);
        expect(find.text('First paragraph. Second paragraph.'), findsNothing);
        await tester.tap(context);
        await tester.pump();
        expect(excerpt, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('reply identity and excerpt follow the selected post', (
      tester,
    ) async {
      final composer = ComposerController(_replyTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      final client = MockClient((_) async => http.Response('', 404));
      addTearDown(client.close);
      final pipeline = installTestMediaPipeline(client: client);
      const first = Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        avatarUrl: 'https://meta.discourse.org/sam.png',
        cooked: '<p>The original message.</p>',
      );
      const second = Post(
        id: 4,
        postNumber: 2,
        username: 'alex',
        avatarUrl: 'https://meta.discourse.org/alex.png',
        cooked: '<p>The selected message.</p>',
      );
      await Future.wait([
        pipeline.avatars.load(first.avatarUrl!),
        pipeline.avatars.load(second.avatarUrl!),
      ]);
      shell.store.putAll(_replyTarget.siteUrl, const [first, second]);
      shell.store.put(
        _replyTarget.siteUrl,
        const TopicDetail(
          id: 7,
          title: 'A topic',
          stream: [1, 4],
          participants: [
            TopicParticipant(
              username: 'alex',
              avatarUrl: 'https://meta.discourse.org/alex.png',
            ),
          ],
        ),
      );
      await _pumpFloatingPanel(tester, shell, composer);
      final avatar = find.byKey(const ValueKey('composer-reply-avatar'));
      final context = find.byKey(const ValueKey('composer-reply-context'));
      expect(tester.widget<AvatarImage>(avatar).url, first.avatarUrl);
      await tester.tap(context);
      await tester.pump();
      expect(find.text('The original message.'), findsOneWidget);

      composer.retarget(replyToPostNumber: 2, replyToUsername: 'alex');
      await tester.pump();
      expect(find.text('@alex'), findsOneWidget);
      expect(find.text('@sam'), findsNothing);
      expect(tester.widget<AvatarImage>(avatar).url, second.avatarUrl);
      expect(find.text('The original message.'), findsNothing);
      await tester.tap(context);
      await tester.pump();
      expect(find.text('The selected message.'), findsOneWidget);

      shell.store.remove<Post>(_replyTarget.siteUrl, second.id);
      await tester.pump();
      expect(find.text('@alex'), findsOneWidget);
      expect(tester.widget<AvatarImage>(avatar).url, second.avatarUrl);
      expect(find.text('The selected message.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'long reply identities fit a narrow composer with larger text',
      (tester) async {
        final composer = ComposerController(
          _replyTarget.replyingTo(2, 'a_very_long_reply_recipient_username'),
        );
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        final semantics = tester.ensureSemantics();
        try {
          await _pumpFloatingPanel(
            tester,
            shell,
            composer,
            size: const Size(320, 650),
            textScaler: const TextScaler.linear(1.5),
          );

          final frame = tester.getRect(find.byType(ComposerPanel));
          final context = tester.getRect(
            find.byKey(const ValueKey('composer-reply-context')),
          );
          final avatar = tester.getRect(
            find.byKey(const ValueKey('composer-reply-avatar')),
          );
          final username = tester.getRect(
            find.byKey(const ValueKey('composer-reply-username')),
          );
          expect(avatar.left, greaterThan(frame.left));
          expect(avatar.right, lessThan(username.left));
          expect(username.right, lessThan(frame.right));
          expect(
            context.bottom,
            lessThan(tester.getRect(find.byType(ComposerEditor)).top),
          );
          expect(
            find.bySemanticsLabel(
              'Replying to @a_very_long_reply_recipient_username, A topic',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('reports its actual painted bounds after moving', (
      tester,
    ) async {
      final composer = ComposerController(_replyTarget);
      final shell = await _shell();
      final reports = <Rect?>[];
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(
        tester,
        shell,
        composer,
        onGeometryChanged: reports.add,
      );
      await tester.pump();

      expect(reports, isNotEmpty);
      expect(reports.last, tester.getRect(find.byType(ComposerPanel)));

      await tester.drag(
        find.byKey(const ValueKey('composer-drag-handle')),
        const Offset(-48, -72),
      );
      await tester.pump();

      expect(reports.last, tester.getRect(find.byType(ComposerPanel)));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(reports.last, isNull);
    });

    testWidgets('starts at the bottom and stays in bounds while moving', (
      tester,
    ) async {
      final composer = ComposerController(_replyTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);

      final initial = tester.getRect(find.byType(ComposerPanel));
      expect(initial.width, 760);
      expect(initial.height, 280);
      expect(initial.center.dx, 450);
      expect(initial.bottom, 634);

      final moveControl = find.byKey(const ValueKey('composer-move-control'));
      expect(find.byTooltip('Drag composer'), findsOneWidget);
      expect(
        tester.getRect(moveControl).right,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('composer-minimize'))).left,
        ),
      );
      await tester.drag(moveControl, const Offset(-48, -72));
      await tester.pump();

      final moved = tester.getRect(find.byType(ComposerPanel));
      expect(moved.left, closeTo(initial.left - 48, 1));
      expect(moved.top, closeTo(initial.top - 72, 1));

      await tester.drag(
        find.byKey(const ValueKey('composer-drag-handle')),
        const Offset(-1000, -1000),
      );
      await tester.pump();

      final constrained = tester.getRect(find.byType(ComposerPanel));
      expect(constrained.left, 16);
      expect(constrained.top, 16);
    });

    testWidgets('exposes border-aligned edge and corner resize targets', (
      tester,
    ) async {
      final composer = ComposerController(_replyTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);

      final initial = tester.getRect(find.byType(ComposerPanel));
      expect(find.byIcon(Icons.open_in_full), findsNothing);

      final top = tester.getRect(
        find.byKey(const ValueKey('composer-resize-top')),
      );
      final right = tester.getRect(
        find.byKey(const ValueKey('composer-resize-right')),
      );
      final bottom = tester.getRect(
        find.byKey(const ValueKey('composer-resize-bottom')),
      );
      final left = tester.getRect(
        find.byKey(const ValueKey('composer-resize-left')),
      );
      expect(top.height, 16);
      expect(top.center.dy, initial.top);
      expect(right.width, 16);
      expect(right.center.dx, initial.right);
      expect(bottom.height, 16);
      expect(bottom.center.dy, initial.bottom);
      expect(left.width, 16);
      expect(left.center.dx, initial.left);
      expect(top.contains(initial.topCenter + const Offset(0, 1)), isTrue);

      final corners = {
        'composer-resize-top-left': initial.topLeft,
        'composer-resize-top-right': initial.topRight,
        'composer-resize-bottom-left': initial.bottomLeft,
        'composer-resize-bottom-right': initial.bottomRight,
      };
      for (final MapEntry(:key, :value) in corners.entries) {
        final corner = tester.getRect(find.byKey(ValueKey(key)));
        expect(corner.size, const Size.square(38));
        expect(corner.contains(value), isTrue);
      }

      final frame = tester.widget<Container>(
        find.byKey(const ValueKey('composer-frame')),
      );
      final border = (frame.decoration! as BoxDecoration).border! as Border;
      expect(border.top.width, 1);

      await tester.drag(
        find.byKey(const ValueKey('composer-resize-left')),
        const Offset(40, 0),
      );
      await tester.pump();
      final fromLeft = tester.getRect(find.byType(ComposerPanel));
      expect(fromLeft.left, closeTo(initial.left + 40, 1));
      expect(fromLeft.right, closeTo(initial.right, 1));

      await tester.drag(
        find.byKey(const ValueKey('composer-resize-right')),
        const Offset(-40, 0),
      );
      await tester.pump();
      final fromRight = tester.getRect(find.byType(ComposerPanel));
      expect(fromRight.left, closeTo(fromLeft.left, 1));
      expect(fromRight.right, closeTo(fromLeft.right - 40, 1));

      await tester.drag(
        find.byKey(const ValueKey('composer-resize-top')),
        const Offset(0, -80),
      );
      await tester.pump();
      final fromTop = tester.getRect(find.byType(ComposerPanel));
      expect(fromTop.top, closeTo(initial.top - 80, 1));
      expect(fromTop.bottom, closeTo(initial.bottom, 1));

      await tester.drag(
        find.byKey(const ValueKey('composer-resize-bottom')),
        const Offset(0, -40),
      );
      await tester.pump();
      final fromBottom = tester.getRect(find.byType(ComposerPanel));
      expect(fromBottom.top, closeTo(fromTop.top, 1));
      expect(fromBottom.bottom, closeTo(fromTop.bottom - 40, 1));
    });

    testWidgets('uses visible macOS cursors across every rounded resize corner', (
      tester,
    ) async {
      await _withTargetPlatform(TargetPlatform.macOS, () async {
        final composer = ComposerController(_replyTarget);
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpFloatingPanel(tester, shell, composer);

        final frameFinder = find.byKey(const ValueKey('composer-frame'));
        final theme = Theme.of(tester.element(frameFinder));
        Container frame() => tester.widget<Container>(frameFinder);
        final restingDecoration = frame().decoration! as BoxDecoration;
        final restingBorder = restingDecoration.border! as Border;
        expect(restingBorder.top.color, theme.shell.divider);
        expect(restingBorder.top.width, 1);
        expect(frame().foregroundDecoration, isNull);

        final panel = tester.getRect(find.byType(ComposerPanel));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);

        await mouse.moveTo(panel.topCenter + const Offset(0, 1));
        await tester.pump();

        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.resizeUpDown,
        );
        expect(frame().decoration, restingDecoration);
        expect(frame().foregroundDecoration, isNull);

        await mouse.moveTo(panel.center);
        await tester.pump();

        expect(frame().decoration, restingDecoration);
        expect(frame().foregroundDecoration, isNull);

        // The frame has a 22-pixel radius. Sampling from one tangent, through the
        // midpoint, to the other tangent catches gaps that one center point misses.
        const topLeftArc = [
          Offset(21, 1),
          Offset(14, 2),
          Offset(7, 7),
          Offset(2, 14),
          Offset(1, 21),
        ];
        final corners = [
          (
            origin: panel.topLeft,
            arc: topLeftArc,
            cursor: SystemMouseCursors.resizeLeft,
          ),
          (
            origin: panel.topRight,
            arc: [for (final point in topLeftArc) Offset(-point.dx, point.dy)],
            cursor: SystemMouseCursors.resizeRight,
          ),
          (
            origin: panel.bottomLeft,
            arc: [for (final point in topLeftArc) Offset(point.dx, -point.dy)],
            cursor: SystemMouseCursors.resizeLeft,
          ),
          (
            origin: panel.bottomRight,
            arc: [for (final point in topLeftArc) -point],
            cursor: SystemMouseCursors.resizeRight,
          ),
        ];
        for (final corner in corners) {
          for (final point in corner.arc) {
            await mouse.moveTo(corner.origin + point);
            await tester.pump();

            expect(
              RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
              corner.cursor,
              reason: 'The visible rounded border at ${corner.origin + point}',
            );
            expect(frame().decoration, restingDecoration);
            expect(frame().foregroundDecoration, isNull);
          }
        }

        await mouse.moveTo(Offset.zero);
        await tester.pump();

        expect(frame().decoration, restingDecoration);
        expect(frame().foregroundDecoration, isNull);
        expect(tester.getRect(find.byType(ComposerPanel)), panel);
      });
    });

    testWidgets(
      'keeps diagonal resize cursors where the platform supports them',
      (tester) async {
        await _withTargetPlatform(TargetPlatform.linux, () async {
          final composer = ComposerController(_replyTarget);
          final shell = await _shell();
          addTearDown(composer.dispose);
          addTearDown(shell.dispose);
          await _pumpFloatingPanel(tester, shell, composer);

          final panel = tester.getRect(find.byType(ComposerPanel));
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);

          await mouse.moveTo(panel.topLeft + const Offset(7, 7));
          await tester.pump();
          expect(
            RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
            SystemMouseCursors.resizeUpLeftDownRight,
          );

          await mouse.moveTo(panel.topRight + const Offset(-7, 7));
          await tester.pump();
          expect(
            RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
            SystemMouseCursors.resizeUpRightDownLeft,
          );
        });
      },
    );

    testWidgets(
      'keeps the visible close target usable beneath the top-right corner',
      (tester) async {
        final composer = ComposerController(_replyTarget);
        final shell = await _InteractionTrackingShellController.create();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpFloatingPanel(tester, shell, composer);

        final close = tester.getRect(find.byTooltip('Close composer'));
        final corner = tester.getRect(
          find.byKey(const ValueKey('composer-resize-top-right')),
        );
        final overlap = close.intersect(corner);
        expect(overlap.isEmpty, isFalse);

        final visibleClosePoint = overlap.center;
        await tester.tapAt(visibleClosePoint);
        await tester.pump();

        expect(
          shell.closeCalls,
          1,
          reason:
              'Close $close must win the hit test at its visible overlap '
              '$visibleClosePoint with resize corner $corner.',
        );
      },
    );

    testWidgets(
      'keeps the visible submit target usable beneath the bottom-right corner',
      (tester) async {
        final composer = ComposerController(_replyTarget);
        composer.text.text = 'A reply';
        final shell = await _InteractionTrackingShellController.create();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpFloatingPanel(tester, shell, composer);

        final submitFinder = find.widgetWithText(FilledButton, 'Reply');
        expect(tester.widget<FilledButton>(submitFinder).onPressed, isNotNull);
        final submit = tester.getRect(submitFinder);
        final corner = tester.getRect(
          find.byKey(const ValueKey('composer-resize-bottom-right')),
        );
        final overlap = submit.intersect(corner);
        expect(overlap.isEmpty, isFalse);

        final visibleSubmitPoint = overlap.center;
        await tester.tapAt(visibleSubmitPoint);
        await tester.pump();

        expect(
          shell.submitCalls,
          1,
          reason:
              'Submit $submit must win the hit test at its visible overlap '
              '$visibleSubmitPoint with resize corner $corner.',
        );
      },
    );

    testWidgets('resizes diagonally from opposite corners', (tester) async {
      final composer = ComposerController(_replyTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);

      final initial = tester.getRect(find.byType(ComposerPanel));
      await tester.drag(
        find.byKey(const ValueKey('composer-resize-top-left')),
        const Offset(40, -40),
      );
      await tester.pump();

      final fromTopLeft = tester.getRect(find.byType(ComposerPanel));
      expect(fromTopLeft.left, closeTo(initial.left + 40, 1));
      expect(fromTopLeft.top, closeTo(initial.top - 40, 1));
      expect(fromTopLeft.right, closeTo(initial.right, 1));
      expect(fromTopLeft.bottom, closeTo(initial.bottom, 1));

      await tester.drag(
        find.byKey(const ValueKey('composer-resize-bottom-right')),
        const Offset(-40, -40),
      );
      await tester.pump();

      final fromBottomRight = tester.getRect(find.byType(ComposerPanel));
      expect(fromBottomRight.left, closeTo(fromTopLeft.left, 1));
      expect(fromBottomRight.top, closeTo(fromTopLeft.top, 1));
      expect(fromBottomRight.right, closeTo(fromTopLeft.right - 40, 1));
      expect(fromBottomRight.bottom, closeTo(fromTopLeft.bottom - 40, 1));
    });
  });

  group('composer presentation and controls', () {
    testWidgets('minimizes and restores a topic without losing its work', (
      tester,
    ) async {
      final composer = ComposerController(_newTopicTarget);
      composer.title.text = 'A draft topic';
      composer.text.text = 'The draft body';
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);

      await tester.drag(
        find.byKey(const ValueKey('composer-drag-handle')),
        const Offset(-48, -72),
      );
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('composer-resize-top')),
        const Offset(0, -40),
      );
      await tester.pump();
      final expanded = tester.getRect(find.byType(ComposerPanel));

      composer.focus.requestFocus();
      await tester.pump();
      expect(composer.focus.hasFocus, isTrue);

      await tester.tap(find.byTooltip('Minimize composer'));
      await tester.pump();

      final minimized = tester.getRect(find.byType(ComposerPanel));
      expect(minimized, Rect.fromLTWH(expanded.left, 588, expanded.width, 46));
      expect(composer.focus.hasFocus, isFalse);
      expect(find.byKey(const ValueKey('composer-minimize')), findsNothing);
      expect(find.byKey(const ValueKey('composer-restore')), findsOneWidget);
      expect(find.byType(ComposerEditor), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Create topic'), findsNothing);
      expect(
        find.byKey(const ValueKey('composer-resize-bottom-right')),
        findsNothing,
      );
      expect(composer.title.text, 'A draft topic');
      expect(composer.text.text, 'The draft body');

      await tester.tap(find.byTooltip('Restore composer'));
      await tester.pump();

      expect(tester.getRect(find.byType(ComposerPanel)), expanded);
      expect(find.byKey(const ValueKey('composer-minimize')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-restore')), findsNothing);
      expect(find.byType(ComposerEditor), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create topic'), findsOneWidget);
      expect(composer.title.text, 'A draft topic');
      expect(composer.text.text, 'The draft body');
    });

    testWidgets('Command-E wraps the selected topic body in backticks', (
      tester,
    ) async {
      final composer = ComposerController(_newTopicTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);

      composer.text.value = const TextEditingValue(
        text: 'format me',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );
      composer.focus.requestFocus();
      await tester.pump();

      await _pressCommandE(tester);

      expect(composer.text.text, '`format` me');
      expect(
        composer.text.selection,
        const TextSelection(baseOffset: 1, extentOffset: 7),
      );
    });

    testWidgets('Command-L links the selected topic body text', (tester) async {
      final composer = ComposerController(_newTopicTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);

      composer.text.value = const TextEditingValue(
        text: 'format me',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );
      composer.focus.requestFocus();
      await tester.pump();

      await _pressCommandL(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-link-dialog')),
        findsOneWidget,
      );
      final anchor = tester.widget<TextField>(
        find.byKey(const ValueKey('composer-link-anchor')),
      );
      expect(anchor.controller!.text, 'format');

      await tester.enterText(
        find.byKey(const ValueKey('composer-link-url')),
        'https://example.com',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
      await tester.pumpAndSettle();

      expect(composer.text.text, '[format](https://example.com) me');
      expect(find.byType(ComposerLinkPill), findsOneWidget);

      await tester.tapAt(tester.getCenter(find.byType(ComposerLinkPill)));
      await tester.pumpAndSettle();

      final existingAnchor = tester.widget<TextField>(
        find.byKey(const ValueKey('composer-link-anchor')),
      );
      final existingUrl = tester.widget<TextField>(
        find.byKey(const ValueKey('composer-link-url')),
      );
      expect(existingAnchor.controller!.text, 'format');
      expect(existingUrl.controller!.text, 'https://example.com');

      await tester.enterText(
        find.byKey(const ValueKey('composer-link-url')),
        'https://meta.discourse.org',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
      await tester.pumpAndSettle();

      expect(composer.text.text, '[format](https://meta.discourse.org) me');
      expect(find.byType(ComposerLinkPill), findsOneWidget);
    });

    testWidgets('a typed domain becomes an editable link in the topic body', (
      tester,
    ) async {
      final composer = ComposerController(_newTopicTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);

      composer.text.value = const TextEditingValue(
        text: 'google.fr',
        selection: TextSelection.collapsed(offset: 9),
      );
      await tester.pump();

      final link = find.byType(ComposerLinkPill);
      expect(link, findsOneWidget);
      expect(composer.text.text, 'google.fr');

      await tester.tapAt(tester.getCenter(link));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('composer-link-url')))
            .controller!
            .text,
        'http://google.fr',
      );
    });

    testWidgets('shows working formatting controls only for selected text', (
      tester,
    ) async {
      final composer = ComposerController(_newTopicTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);

      expect(find.byTooltip('Bold'), findsNothing);
      expect(find.byTooltip('Italic'), findsNothing);

      composer.text.value = const TextEditingValue(
        text: 'format me',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );
      composer.focus.requestFocus();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-selection-toolbar')),
        findsOneWidget,
      );
      expect(find.byTooltip('Bold'), findsOneWidget);
      expect(find.byTooltip('Italic'), findsOneWidget);

      final click = await tester.startGesture(
        tester.getCenter(find.byTooltip('Bold')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await click.up();
      await tester.pump();

      expect(composer.text.text, '**format** me');
    });

    testWidgets(
      'keeps the primary action in the bottom row when formatting controls appear',
      (tester) async {
        final composer = ComposerController(_newTopicTarget);
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpFloatingPanel(tester, shell, composer);

        composer.text.value = const TextEditingValue(
          text: 'format me',
          selection: TextSelection(baseOffset: 0, extentOffset: 6),
        );
        composer.focus.requestFocus();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('composer-selection-toolbar')),
          findsOneWidget,
        );
        final create = tester.getCenter(
          find.widgetWithText(FilledButton, 'Create topic'),
        );
        final panel = tester.getRect(find.byType(ComposerPanel));

        expect(create.dy, greaterThan(panel.bottom - 52));
      },
    );

    testWidgets('uses the available width in a narrow content pane', (
      tester,
    ) async {
      final composer = ComposerController(_replyTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(
        tester,
        shell,
        composer,
        size: const Size(340, 600),
      );

      final panel = tester.getRect(find.byType(ComposerPanel));
      expect(panel.left, 16);
      expect(panel.right, 324);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'keeps writing tools and submit visible without discard in the footer',
      (tester) async {
        final composer = ComposerController(
          _newTopicTarget,
          imageUploader:
              (file, {required onProgress, required abortTrigger}) async =>
                  throw StateError('The picker is not invoked by this test.'),
        );
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpFloatingPanel(
          tester,
          shell,
          composer,
          size: const Size(440, 600),
        );
        await tester.pump();

        final upload = tester.getCenter(
          find.byKey(const ValueKey('composer-upload')),
        );
        final format = tester.getCenter(
          find.byKey(const ValueKey('composer-formatting')),
        );
        final create = tester.getCenter(
          find.widgetWithText(FilledButton, 'Create topic'),
        );
        expect(upload.dy, closeTo(format.dy, 1));
        expect(format.dy, closeTo(create.dy, 1));
        expect(
          find.byKey(const ValueKey('composer-toolbar-scroll-forward')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('composer-discard')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('composer-options')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('composer-discard')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final (name, target, whisper, label, icon) in [
      ('reply', _replyTarget, false, 'Reply', DIcons.reply),
      ('whisper', _replyTarget, true, 'Whisper', DIcons.reply),
      (
        'edit',
        const ComposerTarget(
          siteUrl: 'https://meta.discourse.org',
          topicId: 7,
          slug: 'a-topic',
          topicTitle: 'A topic',
          editingPostId: 8,
          editingPostNumber: 2,
        ),
        false,
        'Save',
        DIcons.reply,
      ),
      (
        'new topic',
        _newTopicTarget,
        false,
        'Create topic',
        DIcons.farPenToSquare,
      ),
    ]) {
      testWidgets('narrow $name footer submits from its labeled icon', (
        tester,
      ) async {
        final composer = ComposerController(target)..setWhisper(whisper);
        final shell = await _InteractionTrackingShellController.create();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpFloatingPanel(
          tester,
          shell,
          composer,
          size: const Size(340, 650),
          textScaler: const TextScaler.linear(1.5),
        );

        final submit = find.byKey(const ValueKey('composer-submit'));
        expect(
          find.descendant(of: submit, matching: find.text(label)),
          findsNothing,
        );
        expect(
          tester
              .widget<DIcon>(
                find.descendant(of: submit, matching: find.byType(DIcon)),
              )
              .icon,
          icon,
        );
        expect(find.byTooltip(label), findsOneWidget);
        expect(tester.widget<FilledButton>(submit).onPressed, isNull);
        final semantics = tester.ensureSemantics();
        try {
          expect(tester.getSemantics(submit).label, label);
        } finally {
          semantics.dispose();
        }
        expect(
          tester.getCenter(submit).dy,
          closeTo(
            tester
                .getCenter(find.byKey(const ValueKey('composer-formatting')))
                .dy,
            1,
          ),
        );

        composer.title.text = 'A title';
        composer.text.text = 'A message ready to submit.';
        await tester.pump();
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        await tester.tap(submit);
        await tester.pump();
        expect(shell.submitCalls, 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('does not show toolbar chevrons when all tools fit', (
      tester,
    ) async {
      final composer = ComposerController(
        _newTopicTarget,
        imageUploader:
            (file, {required onProgress, required abortTrigger}) async =>
                throw StateError('The picker is not invoked by this test.'),
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('composer-toolbar-scroll-forward')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('composer-toolbar-scroll-backward')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('left aligns the toolbar when all tools fit', (tester) async {
      final composer = ComposerController(
        _newTopicTarget,
        imageUploader:
            (file, {required onProgress, required abortTrigger}) async =>
                throw StateError('The picker is not invoked by this test.'),
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);
      await tester.pump();

      final panel = tester.getRect(find.byType(ComposerPanel));
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('composer-toolbar-scroll')),
      );

      expect(toolbar.left, closeTo(panel.left + 8, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows private-message fields addressed to the target group', (
      tester,
    ) async {
      final composer = ComposerController(_privateMessageTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);

      expect(find.text('New message'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('composer-private-message-recipients')),
        findsOneWidget,
      );
      expect(find.text('tech-leads'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Send message'), findsOneWidget);
      expect(find.text('Category'), findsNothing);
      expect(find.text('Tags'), findsNothing);
      expect(find.text('Write your message…'), findsOneWidget);
    });
  });

  group('geometry persistence and loading', () {
    testWidgets('restores the last completed move and resize', (tester) async {
      final firstComposer = ComposerController(_replyTarget);
      final shell = await _shell();
      addTearDown(firstComposer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, firstComposer);

      await tester.drag(
        find.byKey(const ValueKey('composer-drag-handle')),
        const Offset(-48, -72),
      );
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('composer-resize-top')),
        const Offset(0, -80),
      );
      await tester.pump();
      final preferred = tester.getRect(find.byType(ComposerPanel));
      final stored = await const ComposerGeometryStore().read();
      expect(stored, isNotNull);
      expect(stored!.width, closeTo(preferred.width, 1));
      expect(stored.height, closeTo(preferred.height, 1));
      expect(
        stored.horizontalPosition,
        closeTo((preferred.left - 16) / (900 - preferred.width - 32), 0.001),
      );
      expect(
        stored.verticalPosition,
        closeTo((preferred.top - 16) / (650 - preferred.height - 32), 0.001),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      final reopenedComposer = ComposerController(_replyTarget);
      addTearDown(reopenedComposer.dispose);
      await _pumpFloatingPanel(tester, shell, reopenedComposer);
      await tester.pumpAndSettle();

      final restored = tester.getRect(find.byType(ComposerPanel));
      expect(restored, preferred);
    });

    testWidgets('waits for restored geometry before painting the panel', (
      tester,
    ) async {
      final persistence = _DelayedComposerGeometryPersistence();
      final composer = ComposerController(_newTopicTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(
        tester,
        shell,
        composer,
        geometryStore: ComposerGeometryStore(persistence: persistence),
      );

      expect(find.byType(ComposerPanel), findsNothing);

      const preference = ComposerGeometryPreference(
        width: 640,
        height: 360,
        horizontalPosition: 0,
        verticalPosition: 0.5,
      );
      persistence.complete(preference);
      await tester.pumpAndSettle();

      final restored = tester.getRect(find.byType(ComposerPanel));
      expect(restored, const Rect.fromLTWH(16, 145, 640, 360));
    });

    testWidgets('uses default geometry when storage does not answer in time', (
      tester,
    ) async {
      final persistence = _DelayedComposerGeometryPersistence();
      final composer = ComposerController(_newTopicTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(
        tester,
        shell,
        composer,
        geometryStore: ComposerGeometryStore(persistence: persistence),
      );

      expect(find.byType(ComposerPanel), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ComposerPanel), findsOneWidget);
    });
  });
}

Future<void> _pressCommandE(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

Future<void> _pressCommandL(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

Future<T> _withTargetPlatform<T>(
  TargetPlatform platform,
  Future<T> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    return await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

Future<ShellController> _shell() async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  return shell;
}

Future<void> _pumpFloatingPanel(
  WidgetTester tester,
  ShellController shell,
  ComposerController composer, {
  Size size = const Size(900, 650),
  TextScaler textScaler = TextScaler.noScaling,
  ComposerGeometryStore geometryStore = const ComposerGeometryStore(),
  ValueChanged<Rect?>? onGeometryChanged,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: ShellScope(
        controller: shell,
        child: Scaffold(
          body: FloatingComposerPanel(
            composer: composer,
            geometryStore: geometryStore,
            onGeometryChanged: onGeometryChanged,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _InteractionTrackingShellController extends ShellController {
  _InteractionTrackingShellController()
    : super(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );

  int closeCalls = 0;
  int submitCalls = 0;

  static Future<_InteractionTrackingShellController> create() async {
    final shell = _InteractionTrackingShellController();
    await shell.load();
    return shell;
  }

  @override
  void closeComposer({ComposerController? composer}) => closeCalls++;

  @override
  Future<void> submitComposer() async => submitCalls++;
}

final class _DelayedComposerGeometryPersistence
    implements ComposerGeometryPersistence {
  final Completer<String?> _read = Completer<String?>();

  @override
  Future<String?> readGeometry() => _read.future;

  @override
  Future<bool> writeGeometry(String encoded) async => true;

  void complete(ComposerGeometryPreference preference) {
    _read.complete(jsonEncode(preference.toJson()));
  }
}

const _replyTarget = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);

const _newTopicTarget = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 0,
  slug: '',
  topicTitle: '',
  mode: ComposerMode.newTopic,
);

const _privateMessageTarget = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 0,
  slug: '',
  topicTitle: 'New message',
  mode: ComposerMode.privateMessage,
  targetRecipients: 'tech-leads',
);
