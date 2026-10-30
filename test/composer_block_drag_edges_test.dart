import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/composer/block_surface.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/composer/presentation.dart';
import 'package:discourse_native/src/shell/composer/presentation_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _capture = ValueKey('composer-drag-capture');

void main() => composerBlockDragEdgesTests();

void composerBlockDragEdgesTests({bool native = false}) {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final above in [true, false]) {
    for (final long in [false, true]) {
      testWidgets(
        'full mobile composer paints its ${above ? 'top' : 'bottom'} drop edge through side padding, long=$long',
        (tester) async {
          final shell = await _mount(tester, native: native);
          final composer = shell.visibleComposer!;
          composer.text.value = TextEditingValue(
            text: long
                ? List.generate(30, (i) => 'Paragraph $i').join('\n\n')
                : 'test\n\nok',
            selection: const TextSelection.collapsed(offset: 0),
          );
          composer.focus.unfocus();
          await tester.pumpAndSettle();
          composer.history.reset();
          final original = composer.text.value;
          final surface = tester.widget<ComposerBlockSurface>(
            find.byType(ComposerBlockSurface),
          );
          final blocks = composer.blocks.index.blocks;
          final sources = blocks.map((block) => block.source).toList();
          final sourceIndex = above ? (long ? 8 : 1) : 0;
          if (above && long) {
            surface.editorScroll()!.jumpTo(200);
            await tester.pump();
            await tester.pump();
          }
          final gesture = await tester.startGesture(
            surface.blockRect(blocks[sourceIndex])!.center,
          );
          await tester.pump(
            kLongPressTimeout + const Duration(milliseconds: 50),
          );
          await tester.pump();
          final panel = tester.getRect(find.byType(ComposerPanel));
          final destinationY = tester
              .getCenter(
                find.byKey(
                  ValueKey(above ? 'composer-close' : 'composer-toolbar-bar'),
                ),
              )
              .dy;
          for (final x in [panel.center.dx, panel.left + 8, panel.right - 8]) {
            await gesture.moveTo(Offset(x, destinationY));
            await tester.pump();
            await tester.pump();
            await _expectPaintedIndicator(tester, above: above);
            for (var frame = 0; frame < 120; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            await _expectPaintedIndicator(tester, above: above);
            expect(composer.text.value, original);
          }
          final edge = surface.blockRect(above ? blocks.first : blocks.last)!;
          expect(
            tester.getCenter(find.byType(DDropIndicator)).dy,
            closeTo(above ? edge.top : edge.bottom, .01),
          );
          await gesture.up();
          await tester.pumpAndSettle();
          final moved = sources.removeAt(sourceIndex);
          sources.insert(above ? 0 : sources.length, moved);
          expect(
            composer.blocks.index.blocks.map((block) => block.source),
            sources,
          );
          expect(find.byType(DDropIndicator), findsNothing);
          composer.history.undo();
          await tester.pumpAndSettle();
          expect(composer.text.value, original);
          expect(composer.history.canUndo, isFalse);
          await tester.runAsync(composer.finishDraftSaves);
          await tester.pump();
        },
      );
    }
  }
  for (final above in [true, false]) {
    testWidgets(
      'full mobile drop line keeps two points at the exact ${above ? 'top' : 'bottom'} viewport edge',
      (tester) async {
        final shell = await _mount(tester, native: native);
        final composer = shell.visibleComposer!;
        composer.text.value = TextEditingValue(
          text: List.generate(30, (i) => 'Paragraph $i').join('\n\n'),
          selection: const TextSelection.collapsed(offset: 0),
        );
        composer.focus.unfocus();
        await tester.pumpAndSettle();
        final surface = tester.widget<ComposerBlockSurface>(
          find.byType(ComposerBlockSurface),
        );
        final blocks = composer.blocks.index.blocks;
        final gesture = await tester.startGesture(
          surface.blockRect(blocks.first)!.center,
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();
        final header = tester.renderObject<RenderSliver>(
          find.byType(SliverPersistentHeader),
        );
        final headerRect = MatrixUtils.transformRect(
          header.getTransformTo(null),
          header.paintBounds,
        );
        final viewport = tester.getRect(
          find.byKey(const ValueKey('composer-mobile-scroll')),
        );
        final edge = above ? headerRect.bottom : viewport.bottom;
        final gap = above ? 4 : 20;
        final y =
            (surface.blockRect(blocks[gap - 1])!.bottom +
                surface.blockRect(blocks[gap])!.top) /
            2;
        surface.editorScroll()!.jumpTo(y - edge);
        await tester.pump();
        await tester.pump();
        await gesture.moveTo(Offset(viewport.center.dx, edge));
        await tester.pump();
        await tester.pump();
        final indicator = tester.getRect(find.byType(DDropIndicator));
        expect(above ? indicator.top : indicator.bottom, closeTo(edge, .01));
        await _expectPaintedIndicator(tester, above: above);
        await gesture.cancel();
        await tester.pumpAndSettle();
        await tester.runAsync(composer.finishDraftSaves);
        await tester.pump();
      },
    );
  }
}

Future<ShellController> _mount(
  WidgetTester tester, {
  required bool native,
}) async {
  if (native) {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
  }
  tester.view.physicalSize =
      const Size(390, 844) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  const user = DiscourseUser(id: 7, username: 'writer', canCreateTopic: true);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      feeds: const {'/latest.json': []},
      creatableFeedPaths: const {'/latest.json'},
    ),
    authenticator: FakeAuthenticator()
      ..keys['https://meta.discourse.org'] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  final presentation = ComposerPresentationController();
  addTearDown(shell.dispose);
  addTearDown(presentation.dispose);
  await shell.load();
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => DToaster(child: child!),
        home: RepaintBoundary(
          key: _capture,
          child: ComposerPresentationHost(
            controller: presentation,
            child: const Scaffold(body: ComposerDock(child: SizedBox.expand())),
          ),
        ),
      ),
    ),
  );
  await shell.openNewTopicFromSidebar();
  await tester.pumpAndSettle();
  return shell;
}

Future<void> _expectPaintedIndicator(
  WidgetTester tester, {
  required bool above,
}) async {
  final indicator = find.byType(DDropIndicator);
  expect(indicator, findsOneWidget);
  final rect = tester.getRect(indicator);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  final primary = DTokens.of(tester.element(indicator)).primary;
  final coverage = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final point = boundary.globalToLocal(
        Offset(rect.right - 4, rect.center.dy),
      );
      final x = point.dx.floor();
      final backgroundY = point.dy.floor() + (above ? 4 : -4);
      final background = bytes.getUint8(
        (backgroundY * image.width + x) * 4 + 2,
      );
      final blue = primary.toARGB32() & 0xff;
      var painted = 0.0;
      for (var y = point.dy.floor() - 3; y <= point.dy.ceil() + 3; y++) {
        if (y < 0 || y >= image.height) continue;
        final pixel = bytes.getUint8((y * image.width + x) * 4 + 2);
        painted += ((pixel - background) / (blue - background)).clamp(0, 1);
      }
      return painted;
    } finally {
      image.dispose();
    }
  });
  expect(
    coverage,
    closeTo(2, .03),
    reason: 'The edge placeholder must keep its full painted thickness',
  );
}
