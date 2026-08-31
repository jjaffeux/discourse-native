import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/composer_geometry_store.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('panel geometry and hit testing', () {
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
      expect(initial.height, 220);
      expect(initial.center.dx, 450);
      expect(initial.bottom, 634);

      await tester.drag(
        find.byKey(const ValueKey('composer-drag-handle')),
        const Offset(-48, -72),
      );
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

    testWidgets('shows private-message fields addressed to the target group', (
      tester,
    ) async {
      final composer = ComposerController(_privateMessageTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpFloatingPanel(tester, shell, composer);

      expect(find.text('Message tech-leads'), findsOneWidget);
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

    testWidgets('waits for restored geometry before showing the panel', (
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

    testWidgets('shows the default panel when geometry storage never answers', (
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
  ComposerGeometryStore geometryStore = const ComposerGeometryStore(),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: ShellScope(
        controller: shell,
        child: Scaffold(
          body: FloatingComposerPanel(
            composer: composer,
            geometryStore: geometryStore,
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
  void closeComposer() => closeCalls++;

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
