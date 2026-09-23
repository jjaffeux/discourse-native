import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_block_surface.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late ComposerController composer;
  late ShellController shell;
  setUp(() async {
    composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.example',
        topicId: 7,
        slug: 'topic',
        topicTitle: 'A topic',
      ),
    );
    composer.text.value = const TextEditingValue(
      text: 'First paragraph\n\n## A heading\n\nLast paragraph',
      selection: TextSelection.collapsed(offset: 2),
    );
    composer.history.reset();
    shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await shell.load();
  });
  tearDown(() {
    composer.dispose();
    shell.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    bool mobile = false,
    TargetPlatform? platform,
    bool dark = false,
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
    TextStyle? textStyle,
  }) async {
    tester.view.reset();
    tester.view.physicalSize = Size(mobile ? 320 : 800, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = (dark ? AppTheme.dark : AppTheme.light).copyWith(
      platform:
          platform ?? (mobile ? TargetPlatform.iOS : TargetPlatform.macOS),
    );
    final editor = ComposerEditor(
      composer: composer,
      hintText: 'Write a reply…',
      hintStyle: textStyle ?? theme.textTheme.bodyLarge,
      textStyle: textStyle ?? theme.textTheme.bodyLarge,
      expands: !mobile,
      autofocus: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(mobile ? 320 : 800, 720),
              textScaler: TextScaler.linear(textScale),
            ),
            child: ShellScope(
              controller: shell,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Expanded(
                        child: mobile
                            ? SingleChildScrollView(child: editor)
                            : editor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> hoverAt(WidgetTester tester, Offset position) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(position);
    await tester.pumpAndSettle();
    await mouse.removePointer();
  }

  Future<void> hoverSelection(WidgetTester tester) async {
    final surface = tester.widget<ComposerBlockSurface>(
      find.byType(ComposerBlockSurface),
    );
    final rect =
        surface.emptyLineAt(null)?.rect ??
        surface.blockActionRect(composer.blocks.selected!)!;
    await hoverAt(tester, rect.center);
  }

  void expectActionsHidden() {
    expect(find.byTooltip('Add block'), findsNothing);
    expect(find.byTooltip('Drag to move or click to open menu'), findsNothing);
    expect(find.byTooltip('Empty paragraph actions'), findsNothing);
  }

  for (final dark in [false, true]) {
    testWidgets('typing hides block actions until the mouse moves ($dark)', (
      tester,
    ) async {
      await mount(tester, dark: dark);
      final surface = tester.widget<ComposerBlockSurface>(
        find.byType(ComposerBlockSurface),
      );
      final last = composer.blocks.index.blocks.last;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(surface.blockRect(last)!.center);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('composer-block-handle-${last.id}')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(EditableText),
        '${composer.text.text} typed',
      );
      await tester.pumpAndSettle();
      expectActionsHidden();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(seconds: 1));
      expectActionsHidden();
      await mouse.moveTo(surface.blockRect(last)!.center);
      await tester.pump();
      expectActionsHidden();

      final first = composer.blocks.index.blocks.first;
      await mouse.moveTo(surface.blockRect(first)!.center);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add block'), findsOneWidget);
      expect(
        find.byKey(ValueKey('composer-block-handle-${first.id}')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expectActionsHidden();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Enter hides new empty block actions until mouse movement', (
    tester,
  ) async {
    await mount(tester);
    composer.text.selection = TextSelection.collapsed(
      offset: composer.text.text.length,
    );
    composer.focus.requestFocus();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add block'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(composer.text.text, endsWith('\n\n'));
    expectActionsHidden();
    final surface = tester.widget<ComposerBlockSurface>(
      find.byType(ComposerBlockSurface),
    );
    await hoverAt(tester, surface.emptyLineAt(null)!.rect.center);
    expect(find.byTooltip('Add block'), findsOneWidget);
    expect(find.byTooltip('Empty paragraph actions'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    for (final multiline in [false, true]) {
      testWidgets(
        'drop line splits the visible paragraph gap (scale: $scale, multiline: $multiline)',
        (tester) async {
          await (FontLoader(
            'DropLineSans',
          )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
          final paragraph = multiline
              ? '${'A paragraph that wraps across the editor. ' * 5}\nA soft line break'
              : 'dazdzad';
          composer.text.value = TextEditingValue(
            text: '$paragraph\n\ndzad azdz a\n\ndzadzad\n\ndazdazd',
            selection: const TextSelection.collapsed(offset: 0),
          );
          await mount(
            tester,
            textScale: scale,
            textStyle: AppTheme.light.textTheme.bodyLarge!.copyWith(
              fontFamily: 'DropLineSans',
            ),
          );
          await hoverSelection(tester);
          final editable = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;
          final blocks = composer.blocks.index.blocks;
          final origin = editable.localToGlobal(Offset.zero);
          final lineHeight = editable.preferredLineHeight;
          final before = editable.getLocalRectForCaret(
            TextPosition(offset: blocks[0].end - 1),
          );
          final after = editable.getLocalRectForCaret(
            TextPosition(offset: blocks[1].start),
          );
          final bottom = origin.dy + before.center.dy + lineHeight / 2;
          final top = origin.dy + after.center.dy - lineHeight / 2;
          expect(top, greaterThan(bottom));
          final middle = (bottom + top) / 2;
          final gesture = await tester.startGesture(
            tester.getCenter(
              find.byKey(ValueKey('composer-block-handle-${blocks.first.id}')),
            ),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, 20));
          await tester.pump();
          await gesture.moveTo(Offset(origin.dx + 20, middle));
          await tester.pumpAndSettle();
          final indicator = tester.getRect(find.byType(DDropIndicator));
          expect(indicator.center.dy, closeTo(middle, .01));
          expect(indicator.top - bottom, closeTo(top - indicator.bottom, .01));
          await gesture.cancel();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final scale in [1.0, 1.5]) {
    for (final prefix in ['', '[ ] First task\n[ ] Second task\n\n']) {
      testWidgets(
        'paragraph actions align with production text after "$prefix" at $scale',
        (tester) async {
          await (FontLoader(
            'AlignmentSans',
          )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
          composer.text.value = TextEditingValue(
            text: '${prefix}dzadzadza',
            selection: TextSelection.collapsed(offset: prefix.length),
          );
          await mount(
            tester,
            textScale: scale,
            textStyle: AppTheme.light.textTheme.bodyLarge!.copyWith(
              fontFamily: 'AlignmentSans',
            ),
          );
          final editable = tester
              .state<EditableTextState>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is EditableText &&
                      identical(widget.controller, composer.text),
                ),
              )
              .renderEditable;
          final line = editable
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: prefix.length,
                  extentOffset: composer.text.text.length,
                ),
              )
              .first
              .toRect()
              .shift(editable.localToGlobal(Offset.zero));
          final add = tester.getRect(find.byTooltip('Add block'));
          final handle = tester.getRect(
            find.byTooltip('Drag to move or click to open menu'),
          );
          // Allow pixel snapping and the real font's fractional leading.
          expect(add.center.dy, closeTo(line.center.dy, 2));
          expect(handle.center.dy, add.center.dy);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }

  for (final newline in ['\n', '\r\n']) {
    testWidgets('Enter creates a compact, atomic block gap ($newline)', (
      tester,
    ) async {
      final before = newline == '\n' ? 'First' : 'Earlier\r\nsoft\r\n\r\nFirst';
      composer.text.value = TextEditingValue(
        text: before,
        selection: TextSelection.collapsed(offset: before.length),
      );
      await mount(tester);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final end = before.length + newline.length * 2;
      expect(composer.text.text, '$before$newline$newline');
      expect(composer.text.selection.extentOffset, end);
      final surface = tester.widget<ComposerBlockSurface>(
        find.byType(ComposerBlockSurface),
      );
      expect(surface.emptyLineAt(null)?.range.start, end);

      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final render = editable.renderEditable;
      final first = render.getLocalRectForCaret(
        TextPosition(offset: before.length),
      );
      final next = render.getLocalRectForCaret(TextPosition(offset: end));
      expect(
        next.top - first.top,
        // The paragraph line and caret each snap to physical pixels.
        closeTo(render.preferredLineHeight * 1.5, 2),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(composer.text.selection.extentOffset, before.length);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(composer.text.selection.extentOffset, end);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(composer.raw, before);
      expect(composer.text.selection.extentOffset, before.length);
      composer.history.undo();
      expect(composer.text.text, '$before$newline$newline');
    });
  }

  for (final newline in ['\n', '\r\n']) {
    testWidgets('Enter continues compact todo rows ($newline)', (tester) async {
      final source = '[ ] First$newline[x] Second';
      composer.text.value = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
      );
      await mount(tester);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(composer.text.text, '$source$newline[ ] ');
      final surface = tester.widget<ComposerBlockSurface>(
        find.byType(ComposerBlockSurface),
      );
      final blocks = composer.blocks.index.blocks;
      expect(blocks, hasLength(3));
      for (var i = 1; i < blocks.length; i++) {
        expect(
          surface.blockRect(blocks[i])!.top -
              surface.blockRect(blocks[i - 1])!.bottom,
          closeTo(0, .01),
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(
        composer.text.selection.extentOffset,
        inInclusiveRange(source.indexOf('Second'), source.length),
      );
      await tester.enterText(
        find.byType(EditableText),
        '[ ] First$newline$newline[ ] Second',
      );
      await tester.pumpAndSettle();
      final spaced = composer.blocks.index.blocks;
      expect(
        surface.blockRect(spaced.last)!.top -
            surface.blockRect(spaced.first)!.bottom,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('required separator offers no empty block controls', (
    tester,
  ) async {
    composer.text.value = const TextEditingValue(
      text: 'First\n\nSecond',
      selection: TextSelection.collapsed(offset: 0),
    );
    await mount(tester);
    final surface = tester.widget<ComposerBlockSurface>(
      find.byType(ComposerBlockSurface),
    );
    final render = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final rect = render.getLocalRectForCaret(const TextPosition(offset: 6));
    expect(surface.emptyLineAt(render.localToGlobal(rect.center)), isNull);
    composer.text.selection = const TextSelection.collapsed(offset: 6);
    expect(composer.text.selection.extentOffset, 7);
    composer.text.selection = const TextSelection.collapsed(offset: 5);
    composer.focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(composer.raw, 'FirstSecond');
  });

  for (final mobile in [false, true]) {
    if (mobile) {
      testWidgets('on-screen Enter creates a paragraph gap', (tester) async {
        composer.text.value = const TextEditingValue(
          text: 'First',
          selection: TextSelection.collapsed(offset: 5),
        );
        await mount(tester, mobile: mobile);
        await tester.showKeyboard(find.byType(EditableText));
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'First\n',
            selection: TextSelection.collapsed(offset: 6),
          ),
        );
        await tester.pumpAndSettle();
        expect(composer.text.text, 'First\n\n');
        expect(composer.text.selection.extentOffset, 7);
        final render = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        expect(
          render.getLocalRectForCaret(const TextPosition(offset: 7)).top -
              render.getLocalRectForCaret(const TextPosition(offset: 0)).top,
          closeTo(render.preferredLineHeight * 1.5, 2),
        );
      });
    }
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'soft lines stay inside spaced blocks ($mobile, $textScale)',
        (tester) async {
          composer.text.value = const TextEditingValue(
            text: 'First',
            selection: TextSelection.collapsed(offset: 5),
          );
          await mount(tester, mobile: mobile, textScale: textScale);
          composer.focus.requestFocus();
          await tester.pump();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pumpAndSettle();
          expect(composer.text.text, 'First\n');
          expect(composer.blocks.index.blocks, hasLength(1));
          await tester.enterText(find.byType(EditableText), 'First\nsoft');
          await tester.pumpAndSettle();
          final render = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;
          final first = render.getLocalRectForCaret(
            const TextPosition(offset: 0),
          );
          final soft = render.getLocalRectForCaret(
            const TextPosition(offset: 6),
          );
          expect(
            soft.top - first.top,
            closeTo(render.preferredLineHeight, .01),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          final empty = render.getLocalRectForCaret(
            TextPosition(offset: composer.text.text.length),
          );
          expect(
            empty.top - soft.top,
            closeTo(render.preferredLineHeight * 1.5, 2),
          );
          await tester.enterText(
            find.byType(EditableText),
            'First\nsoft\n\nNext',
          );
          await tester.pumpAndSettle();
          expect(composer.blocks.index.blocks.map((block) => block.source), [
            'First\nsoft',
            'Next',
          ]);
          final next = render.getLocalRectForCaret(
            const TextPosition(offset: 12),
          );
          expect(next.top, closeTo(empty.top, 1));
        },
      );
    }
  }

  for (final newline in ['\n', '\r\n']) {
    testWidgets(
      'block gaps keep sibling todos compact without changing Markdown ($newline)',
      (tester) async {
        final source =
            'First$newline## Heading$newline[ ] Task$newline[ ] Another';
        composer.text.value = TextEditingValue(
          text: source,
          selection: const TextSelection.collapsed(offset: 0),
        );
        await mount(tester);
        final surface = tester.widget<ComposerBlockSurface>(
          find.byType(ComposerBlockSurface),
        );
        final render = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        final blocks = composer.blocks.index.blocks;
        expect(blocks, hasLength(4));
        for (var i = 1; i < blocks.length; i++) {
          final before = surface.blockRect(blocks[i - 1])!;
          final after = surface.blockRect(blocks[i])!;
          expect(
            after.top - before.bottom,
            i == 3
                ? closeTo(0, .01)
                : greaterThanOrEqualTo(render.preferredLineHeight * .9),
          );
          expect(
            surface.emptyLineAt(
              Offset(after.left, (before.bottom + after.top) / 2),
            ),
            isNull,
          );
        }
        composer.focus.requestFocus();
        composer.text.selection = TextSelection.collapsed(
          offset: blocks[1].start,
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        expect(composer.text.selection.extentOffset, blocks.first.end);
        expect(composer.text.selection.affinity, TextAffinity.upstream);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        expect(composer.text.selection.extentOffset, blocks[1].start);
        expect(composer.text.text, source);
      },
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('mobile long press moves a block on $platform', (tester) async {
      await mount(tester, mobile: true, platform: platform);
      final original = composer.text.value;
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      final blocks = composer.blocks.index.blocks;
      final surface = tester.widget<ComposerBlockSurface>(
        find.byType(ComposerBlockSurface),
      );
      final first = surface.blockRect(blocks.first)!;
      final second = surface.blockRect(blocks[1])!;
      final last = surface.blockRect(blocks.last)!;
      final gesture = await tester.startGesture(first.center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.byType(DDragHighlight), findsOneWidget);
      await gesture.moveTo(
        Offset(first.center.dx, (second.bottom + last.top) / 2),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(DDropIndicator), findsOneWidget);
      expect(tester.getRect(find.byType(DDropIndicator)).left, 16);
      expect(composer.text.text, original.text);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        composer.text.text,
        '## A heading\n\nFirst paragraph\n\nLast paragraph',
      );
      expect(composer.blocks.index.blocks[1].id, blocks.first.id);
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(editor),
      );
      expect(find.byType(DDragHighlight), findsNothing);
      expect(find.byType(DDropIndicator), findsNothing);
      composer.history.undo();
      await tester.pumpAndSettle();
      expect(composer.text.value, original);
      expect(composer.history.canUndo, isFalse);
    });
  }

  for (final cancellation in ['pointer', 'outside', 'revision']) {
    testWidgets('mobile block drag cancels on $cancellation', (tester) async {
      await mount(tester, mobile: true);
      final source = composer.text.text;
      final surface = tester.widget<ComposerBlockSurface>(
        find.byType(ComposerBlockSurface),
      );
      final blocks = composer.blocks.index.blocks;
      final gesture = await tester.startGesture(
        surface.blockRect(blocks.first)!.center,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(surface.blockRect(blocks.last)!.bottomCenter);
      await tester.pump();
      if (cancellation == 'pointer') {
        await gesture.cancel();
      } else {
        if (cancellation == 'outside') {
          await gesture.moveTo(const Offset(0, 0));
        } else {
          composer.text.text = '$source!';
        }
        await gesture.up();
      }
      await tester.pumpAndSettle();
      expect(
        composer.text.text,
        cancellation == 'revision' ? '$source!' : source,
      );
      expect(find.byType(DDragHighlight), findsNothing);
      expect(find.byType(DDropIndicator), findsNothing);
    });
  }

  testWidgets('mobile swipe scrolls without moving blocks', (tester) async {
    composer.text.text = List.generate(40, (i) => 'Paragraph $i').join('\n\n');
    await mount(tester, mobile: true);
    final source = composer.text.text;
    final surface = tester.widget<ComposerBlockSurface>(
      find.byType(ComposerBlockSurface),
    );
    final start = surface.blockRect(composer.blocks.index.blocks[8])!.center;
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -150));
    await tester.pump(kLongPressTimeout);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(surface.editorScroll()!.pixels, greaterThan(0));
    expect(composer.text.text, source);
    expect(find.byType(DDragHighlight), findsNothing);
  });

  testWidgets('mobile long press scrolls at the viewport edge', (tester) async {
    composer.text.text = List.generate(40, (i) => 'Paragraph $i').join('\n\n');
    await mount(tester, mobile: true);
    final source = composer.text.text;
    final surface = tester.widget<ComposerBlockSurface>(
      find.byType(ComposerBlockSurface),
    );
    final gesture = await tester.startGesture(
      surface.blockRect(composer.blocks.index.blocks.first)!.center,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(const Offset(150, 694));
    await tester.pump(const Duration(seconds: 1));
    expect(surface.editorScroll()!.pixels, greaterThan(0));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(composer.text.text, source);
    expect(find.byType(DDragHighlight), findsNothing);
  });

  testWidgets(
    'mobile tapping still focuses the editor without moving a block',
    (tester) async {
      await mount(tester, mobile: true);
      final source = composer.text.text;
      final surface = tester.widget<ComposerBlockSurface>(
        find.byType(ComposerBlockSurface),
      );
      await tester.tapAt(
        surface.blockRect(composer.blocks.index.blocks.last)!.center,
      );
      await tester.pumpAndSettle();
      expect(composer.focus.hasFocus, isTrue);
      expect(composer.text.selection.isCollapsed, isTrue);
      expect(
        composer.text.selection.extentOffset,
        greaterThan(source.indexOf('Last')),
      );
      expect(composer.text.text, source);
      expect(find.byType(DDragHighlight), findsNothing);
    },
  );

  for (final scale in [1.0, 2.0]) {
    for (final source in [
      'A paragraph',
      'First line\nSecond line\nThird line',
      '[ ] First task\n[x] Second task',
      '```\nfirst\nsecond\nthird\n```',
    ]) {
      testWidgets('actions align to a top text line at $scale in "$source"', (
        tester,
      ) async {
        composer.text.value = TextEditingValue(
          text: source,
          selection: const TextSelection.collapsed(offset: 0),
        );
        await mount(
          tester,
          textScale: scale,
          textStyle: const TextStyle(fontSize: 16, height: 1.5),
        );
        final surface = tester.widget<ComposerBlockSurface>(
          find.byType(ComposerBlockSurface),
        );
        final block = composer.blocks.index.blocks.first;
        final blockRect = surface.blockRect(block)!;
        final add = tester.getRect(find.byTooltip('Add block'));
        final handle = tester.getRect(
          find.byKey(ValueKey('composer-block-handle-${block.id}')),
        );
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        final caret = editable.getLocalRectForCaret(
          TextPosition(offset: block.start),
        );
        final expectedCenter = source.startsWith('[ ]')
            ? tester
                  .getRect(
                    find.descendant(
                      of: find.byType(DCheckbox).first,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .center
                  .dy
            : source.startsWith('```')
            ? blockRect.top + surface.lineHeight / 2
            : editable.localToGlobal(caret.center).dy;
        expect(add.center.dy, closeTo(expectedCenter, .01));
        expect(handle.center.dy, closeTo(add.center.dy, .01));
        expect(
          handle.top,
          greaterThanOrEqualTo(tester.getRect(find.byType(ComposerEditor)).top),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final prefix in ['#', '###']) {
    testWidgets(
      'wrapped $prefix heading aligns actions to its first heading line',
      (tester) async {
        composer.text.value = TextEditingValue(
          text: '$prefix ${List.filled(35, 'Heading').join(' ')}',
          selection: const TextSelection.collapsed(offset: 0),
        );
        await mount(tester);
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        final boxes = editable.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: composer.text.text.length),
        );
        expect(boxes.length, greaterThan(1));
        final first = boxes.first.toRect().shift(
          editable.localToGlobal(Offset.zero),
        );
        final add = tester.getRect(find.byTooltip('Add block'));
        expect(add.center.dy, closeTo(first.center.dy, .01));
        final surface = tester.widget<ComposerBlockSurface>(
          find.byType(ComposerBlockSurface),
        );
        final block = composer.blocks.index.blocks.first;
        expect(surface.blockRect(block)!.height, greaterThan(first.height));
        expect(
          tester
              .getRect(
                find.byKey(ValueKey('composer-block-handle-${block.id}')),
              )
              .center
              .dy,
          closeTo(first.center.dy, .01),
        );
      },
    );
  }

  testWidgets('drag handle shows grab across its entire hit area', (
    tester,
  ) async {
    await mount(tester);
    final id = composer.blocks.index.blocks.first.id;
    final handle = find.byKey(ValueKey('composer-block-handle-$id'));
    final rect = tester.getRect(handle);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(790, 710));
    for (final x in [1.0, rect.width / 2, rect.width - 1]) {
      for (final y in [1.0, rect.height / 2, rect.height - 1]) {
        await mouse.moveTo(rect.topLeft + Offset(x, y));
        await tester.pumpAndSettle();
        expect(handle, findsOneWidget);
        expect(
          tester.binding.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.grab,
          reason: 'Handle offset $x, $y',
        );
      }
    }
    await mouse.removePointer();
  });

  testWidgets('add opens commands below a populated block and can be undone', (
    tester,
  ) async {
    await mount(tester);
    final original = composer.text.value;
    final id = composer.blocks.index.blocks.first.id;
    final add = find.byKey(ValueKey('composer-block-add-$id'));
    final handle = find.byKey(ValueKey('composer-block-handle-$id'));
    expect(tester.getSize(add), const Size(20, 34));
    expect(tester.getSize(handle), const Size(20, 34));
    expect(tester.getRect(add).right, tester.getRect(handle).left);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(
      composer.text.text,
      'First paragraph\n\n/\n\n## A heading\n\nLast paragraph',
    );
    expect(find.text('Type to search'), findsOneWidget);
    expect(find.text('Heading 2'), findsOneWidget);
    expect(composer.focus.hasFocus, isTrue);
    expectActionsHidden();
    composer.history.undo();
    await tester.pumpAndSettle();
    expect(composer.text.value, original);
    expect(composer.history.canUndo, isFalse);
    expectActionsHidden();
    await hoverSelection(tester);
    await tester.tap(find.byTooltip('Add block'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heading 2'));
    await tester.pumpAndSettle();
    expect(
      composer.text.text,
      'First paragraph\n\n## \n\n## A heading\n\nLast paragraph',
    );
    expectActionsHidden();
    await hoverSelection(tester);
    expect(find.byTooltip('Add block'), findsOneWidget);
    expect(
      find.byTooltip('Drag to move or click to open menu'),
      findsOneWidget,
    );
  });

  testWidgets(
    'accessibility activation opens commands without keyboard input',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester);
      for (var attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) await hoverSelection(tester);
        final button = tester.getSemantics(find.byTooltip('Add block'));
        button.owner!.performAction(button.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(find.text('Close menu'), findsOneWidget);
        expect(find.text('Heading 2'), findsOneWidget);
        expect(composer.focus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      expect(
        composer.text.text,
        'First paragraph\n\n\n\n## A heading\n\nLast paragraph',
      );
      semantics.dispose();
    },
  );

  for (final source in ['', '  ', 'Before\n\n\nAfter', 'Before\n\n']) {
    testWidgets('add uses the current empty line in "$source"', (tester) async {
      final offset = source.startsWith('Before') ? 'Before\n\n'.length : 0;
      composer.text.value = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: offset),
      );
      await mount(tester);
      expect(find.byTooltip('Empty paragraph actions'), findsOneWidget);
      await tester.tap(find.byTooltip('Add block'));
      await tester.pumpAndSettle();
      expect(
        composer.text.text,
        source.trim().isEmpty ? '/' : source.replaceRange(offset, offset, '/'),
      );
      expect(composer.text.selection.extentOffset, offset + 1);
      expect(find.text('Type to search'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(composer.text.text, source.trim().isEmpty ? '' : source);
      expect(find.text('Close menu'), findsNothing);
      expectActionsHidden();
      await hoverSelection(tester);
      await tester.tap(find.byTooltip('Add block'));
      await tester.pumpAndSettle();
      expect(find.text('Close menu'), findsOneWidget);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('empty editor keeps both controls before typing ($dark)', (
      tester,
    ) async {
      await (FontLoader(
            'EmptyEditorMono',
          )..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf')))
          .load();
      composer.text.value = TextEditingValue.empty;
      await mount(
        tester,
        dark: dark,
        textStyle: const TextStyle(fontFamily: 'EmptyEditorMono', fontSize: 16),
      );
      final add = find.byTooltip('Add block');
      final handle = find.byTooltip('Empty paragraph actions');
      expect(add, findsOneWidget);
      expect(handle, findsOneWidget);
      expect(composer.focus.hasFocus, isFalse);
      expect(tester.getRect(add).right, tester.getRect(handle).left);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      addTearDown(mouse.removePointer);
      final editor = tester.getRect(find.byType(ComposerEditor));
      expect(tester.getRect(handle).top, greaterThanOrEqualTo(editor.top));
      await mouse.moveTo(editor.bottomRight - const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(add, findsOneWidget);
      expect(handle, findsOneWidget);
      expect(composer.text.text, isEmpty);

      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(composer.text.text, '/');
      expect(composer.text.selection.extentOffset, 1);
      expect(find.text('Close menu'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(composer.text.text, isEmpty);
      expectActionsHidden();
      await mouse.moveBy(const Offset(-1, 0));
      await tester.pumpAndSettle();
      expect(handle, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final textScale in [1.0, 1.5]) {
    for (final source in ['', '\n\n', 'First paragraph\n\n']) {
      testWidgets(
        'typing keeps paragraph geometry stable at $textScale scale in "$source"',
        (tester) async {
          await (FontLoader('StableEditorMono')..addFont(
                rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'),
              ))
              .load();
          composer.text.value = TextEditingValue(
            text: source,
            selection: TextSelection.collapsed(offset: source.length),
          );
          await mount(
            tester,
            textScale: textScale,
            textStyle: const TextStyle(
              fontFamily: 'StableEditorMono',
              fontSize: 16,
              height: 1.5,
            ),
          );
          final editable = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;
          final hint = source.isEmpty
              ? tester.renderObject<RenderBox>(find.text('Write a reply…'))
              : null;
          final hintBaseline = hint?.getDryBaseline(
            hint.constraints,
            TextBaseline.alphabetic,
          );
          final add = tester.getRect(find.byTooltip('Add block'));
          final handle = tester.getRect(
            find.byTooltip('Empty paragraph actions'),
          );
          final caretPosition = TextPosition(offset: source.length);
          final caret = editable.getLocalRectForCaret(caretPosition);
          final editorBounds = tester.getRect(find.byType(ComposerEditor));

          await tester.enterText(find.byType(EditableText), '${source}d');
          await tester.pumpAndSettle();
          expectActionsHidden();
          expect(editable.getLocalRectForCaret(caretPosition), caret);
          expect(tester.getRect(find.byType(ComposerEditor)), editorBounds);
          await hoverSelection(tester);
          expect(tester.getRect(find.byTooltip('Add block')), add);
          expect(
            tester.getRect(
              find.byTooltip('Drag to move or click to open menu'),
            ),
            handle,
          );
          expect(editable.getLocalRectForCaret(caretPosition), caret);
          expect(tester.getRect(find.byType(ComposerEditor)), editorBounds);
          if (hintBaseline != null) {
            expect(
              editable.getDryBaseline(
                editable.constraints,
                TextBaseline.alphabetic,
              ),
              closeTo(hintBaseline, .001),
            );
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pumpAndSettle();
          expect(composer.text.text, source);
          expectActionsHidden();
          expect(tester.getRect(find.byType(ComposerEditor)), editorBounds);
          await hoverSelection(tester);
          expect(tester.getRect(find.byTooltip('Add block')), add);
          expect(
            tester.getRect(find.byTooltip('Empty paragraph actions')),
            handle,
          );
          expect(tester.getRect(find.byType(ComposerEditor)), editorBounds);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }

  testWidgets('hovering an empty line targets it independently of the caret', (
    tester,
  ) async {
    composer.text.value = const TextEditingValue(
      text: 'First\n\n\nLast',
      selection: TextSelection.collapsed(offset: 0),
    );
    await mount(tester);
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final blank = editable.getLocalRectForCaret(const TextPosition(offset: 7));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      editable.localToGlobal(blank.center + const Offset(20, 0)),
    );
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(find.byTooltip('Add block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add block'));
    await tester.pumpAndSettle();
    expect(composer.text.text, 'First\n\n/\nLast');
    expect(find.text('Type to search'), findsOneWidget);
  });

  for (final source in [
    'First\nsoft-wrapped paragraph',
    '## Heading',
    '```dart\ncode\n```',
    '![picture](upload://picture.png)',
    'First\r\nsecond line',
  ]) {
    testWidgets('add inserts after the complete block: $source', (
      tester,
    ) async {
      composer.text.value = TextEditingValue(
        text: source,
        selection: const TextSelection.collapsed(offset: 0),
      );
      await mount(tester);
      await tester.tap(find.byTooltip('Add block'));
      await tester.pumpAndSettle();
      final newline = source.contains('\r\n') ? '\r\n' : '\n';
      expect(composer.text.text, '$source$newline$newline/');
      expect(find.text('Type to search'), findsOneWidget);
      expect(composer.focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('add separates adjacent headings without changing their source', (
    tester,
  ) async {
    composer.text.value = const TextEditingValue(
      text: '# First\n## Second',
      selection: TextSelection.collapsed(offset: 0),
    );
    await mount(tester);
    await tester.tap(find.byTooltip('Add block'));
    await tester.pumpAndSettle();
    expect(composer.text.text, '# First\n\n/\n\n## Second');
    expect(find.text('Type to search'), findsOneWidget);
  });

  testWidgets('block actions leave room for the editor at 200% text', (
    tester,
  ) async {
    await mount(tester, textScale: 2);
    final block = composer.blocks.index.blocks.first;
    final surface = tester.widget<ComposerBlockSurface>(
      find.byType(ComposerBlockSurface),
    );
    expect(
      tester
          .getRect(find.byKey(ValueKey('composer-block-handle-${block.id}')))
          .right,
      lessThanOrEqualTo(surface.blockRect(block)!.left),
    );
    await tester.tap(find.byTooltip('Add block'));
    await tester.pumpAndSettle();
    expect(find.text('Type to search'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'add is disabled during composition and in an unclosed code block',
    (tester) async {
      composer.text.value = const TextEditingValue(
        text: '```\ncode',
        selection: TextSelection.collapsed(offset: 4),
      );
      await mount(tester);
      DButton add() => tester.widget<DButton>(
        find.byWidgetPredicate(
          (widget) => widget is DButton && widget.tooltip == 'Add block',
        ),
      );
      expect(add().onPressed, isNull);
      composer.text.value = const TextEditingValue(
        text: 'Text',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      );
      await tester.pumpAndSettle();
      expectActionsHidden();
      await hoverSelection(tester);
      expect(add().onPressed, isNull);
    },
  );

  testWidgets('desktop handle drag moves a paragraph as one undoable edit', (
    tester,
  ) async {
    await mount(tester);
    final original = composer.text.value;
    final id = composer.blocks.index.blocks.first.id;
    final handle = find.byKey(ValueKey('composer-block-handle-$id'));
    expect(handle, findsOneWidget);
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final bottom = editable
        .getBoxesForSelection(
          TextSelection(
            baseOffset: composer.blocks.index.blocks.last.start,
            extentOffset: composer.text.text.length,
          ),
        )
        .last
        .toRect()
        .bottom;
    final gesture = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 12));
    await tester.pump();
    await gesture.moveTo(editable.localToGlobal(Offset(100, bottom + 12)));
    await tester.pump();
    await tester.pump();
    expect(find.byType(DDropIndicator), findsOneWidget);
    expect(find.text('Drag to move or click to open menu'), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      composer.text.text,
      '## A heading\n\nLast paragraph\n\nFirst paragraph',
    );
    composer.history.undo();
    await tester.pumpAndSettle();
    expect(composer.text.value, original);
    expect(composer.history.canUndo, isFalse);
  });

  testWidgets('empty-line drop indicator follows a steady downward drag', (
    tester,
  ) async {
    const source = 'First paragraph\n\n\n\n\n## A heading\n\nLast paragraph';
    composer.text.value = const TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: source.length),
    );
    composer.history.reset();
    await mount(tester, textStyle: const TextStyle(fontSize: 16, height: 1.8));
    final original = composer.text.value;
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    Rect lineAt(int offset) => editable
        .getLocalRectForCaret(TextPosition(offset: offset))
        .shift(editable.localToGlobal(Offset.zero));
    final first = lineAt('First paragraph\n\n'.length);
    final last = lineAt(source.indexOf('##') - 1);
    final id = composer.blocks.index.blocks.last.id;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('composer-block-handle-$id'))),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 16));
    await tester.pump();
    final x = tester.getCenter(find.byType(EditableText)).dx;
    double? previous;
    for (var y = first.top + 1; y < last.bottom; y += 1) {
      await gesture.moveTo(Offset(x, y));
      await tester.pump();
      await tester.pump();
      final current = tester.getCenter(find.byType(DDropIndicator)).dy;
      if (previous != null) {
        expect(
          current,
          greaterThanOrEqualTo(previous - .01),
          reason: 'The line moved backward at pointer y=$y',
        );
      }
      previous = current;
    }
    expect(composer.text.value, original);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('drop indicator holds its destination through pointer jitter', (
    tester,
  ) async {
    await mount(tester);
    final original = composer.text.value;
    final blocks = composer.blocks.index.blocks;
    final surface = tester.widget<ComposerBlockSurface>(
      find.byType(ComposerBlockSurface),
    );
    final before = surface.blockRect(blocks[1])!;
    final last = surface.blockRect(blocks.last)!;
    final gap = (before.bottom + last.top) / 2;
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(ValueKey('composer-block-handle-${blocks.first.id}')),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 16));
    await tester.pump();

    Future<void> move(double y, double expected) async {
      await gesture.moveTo(Offset(last.center.dx, y));
      await tester.pump();
      await tester.pump();
      expect(
        tester.getCenter(find.byType(DDropIndicator)).dy,
        closeTo(expected, .01),
      );
      expect(composer.text.value, original);
    }

    await move(last.center.dy - 10, gap);
    for (final delta in [-1.0, 1.0, -2.0, 2.0]) {
      await move(last.center.dy + delta, gap);
    }
    await move(last.center.dy + 10, last.bottom);
    for (final delta in [1.0, -1.0, 2.0, -2.0]) {
      await move(last.center.dy + delta, last.bottom);
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      composer.text.text,
      '## A heading\n\nLast paragraph\n\nFirst paragraph',
    );
    composer.history.undo();
    await tester.pumpAndSettle();
    expect(composer.text.value, original);
    expect(composer.history.canUndo, isFalse);
  });

  for (final direction in TextDirection.values) {
    for (final leading in [false, true]) {
      testWidgets(
        'dragging between individual empty lines ($direction, leading: $leading)',
        (tester) async {
          const paragraph = 'Move this paragraph';
          final source = leading ? '\n\n\n\n$paragraph' : '$paragraph\n\n\n\n';
          composer.text.value = TextEditingValue(
            text: source,
            selection: TextSelection.collapsed(
              offset: source.indexOf(paragraph) + 3,
            ),
          );
          composer.history.reset();
          await mount(tester, direction: direction, dark: leading);
          final original = composer.text.value;
          final editorState = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          final editable = editorState.renderEditable;
          final id = composer.blocks.index.blocks.single.id;
          final handle = find.byKey(ValueKey('composer-block-handle-$id'));
          final gesture = await tester.startGesture(
            tester.getCenter(handle),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, 16));
          await tester.pump();

          final secondEmpty = leading ? 1 : paragraph.length + 2;
          final line = editable
              .getLocalRectForCaret(TextPosition(offset: secondEmpty))
              .shift(editable.localToGlobal(Offset.zero));
          final x = tester.getCenter(find.byType(EditableText)).dx;
          for (final after in [false, true]) {
            await gesture.moveTo(
              Offset(x, line.top + line.height * (after ? .75 : .25)),
            );
            await tester.pump();
            await tester.pump();
            expect(
              tester.getCenter(find.byType(DDropIndicator)).dy,
              closeTo(after ? line.bottom : line.top, .01),
            );
            for (final delta in [1.0, -1.0, .5, -.5]) {
              await gesture.moveTo(Offset(x, line.center.dy + delta));
              await tester.pump();
              await tester.pump();
              expect(
                tester.getCenter(find.byType(DDropIndicator)).dy,
                closeTo(after ? line.bottom : line.top, .01),
              );
            }
            expect(composer.text.value, original);
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(composer.text.text, '\n\n$paragraph\n\n');
          expect(composer.text.selection.extentOffset, 5);
          expect(composer.blocks.index.blocks.single.id, id);
          expect(
            tester.state<EditableTextState>(find.byType(EditableText)),
            same(editorState),
          );
          expect(find.byType(DDropIndicator), findsNothing);
          final moved = composer.text.value;
          composer.history.undo();
          await tester.pumpAndSettle();
          expect(composer.text.value, original);
          expect(composer.history.canUndo, isFalse);
          composer.history.redo();
          await tester.pumpAndSettle();
          expect(composer.text.value, moved);
        },
      );
    }
  }

  for (final dark in [false, true]) {
    testWidgets(
      'each to-do has its own hover handle and drag boundary ($dark)',
      (tester) async {
        const source = '[ ] First\n[x] Second\n[ ] Third\n[ ] ';
        composer.text.value = const TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: 16),
        );
        composer.history.reset();
        await mount(tester, dark: dark);
        final original = composer.text.value;
        final blocks = composer.blocks.index.blocks;
        expect(blocks, hasLength(4));
        final surface = tester.widget<ComposerBlockSurface>(
          find.byType(ComposerBlockSurface),
        );
        final rects = blocks.map((block) => surface.blockRect(block)!).toList();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        for (var i = 0; i < blocks.length; i++) {
          if (i > 0) {
            expect(rects[i].top, greaterThanOrEqualTo(rects[i - 1].bottom));
          }
          await mouse.moveTo(rects[i].center);
          await tester.pumpAndSettle();
          expect(
            find.byKey(ValueKey('composer-block-handle-${blocks[i].id}')),
            findsOneWidget,
          );
        }
        await mouse.moveTo(rects[1].center);
        await tester.pumpAndSettle();
        final handle = find.byKey(
          ValueKey('composer-block-handle-${blocks[1].id}'),
        );
        final drag = await tester.startGesture(
          tester.getCenter(handle),
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveBy(const Offset(0, 12));
        await tester.pump();
        final gap = (rects[2].bottom + rects[3].top) / 2;
        await drag.moveTo(Offset(rects[2].center.dx, gap));
        await tester.pumpAndSettle();
        expect(
          tester.getCenter(find.byType(DDropIndicator)).dy,
          closeTo(gap, .01),
        );
        expect(composer.text.value, original);
        await drag.up();
        await tester.pumpAndSettle();
        expect(composer.text.text, '[ ] First\n[ ] Third\n[x] Second\n[ ] ');
        expect(composer.blocks.index.blocks[2].id, blocks[1].id);
        expect(composer.text.selection.extentOffset, 26);
        expect(composer.text.todos.map((todo) => todo.checked), [
          false,
          false,
          true,
          false,
        ]);
        composer.history.undo();
        await tester.pumpAndSettle();
        expect(composer.text.value, original);
        expect(composer.history.canUndo, isFalse);
        composer.history.redo();
        await tester.pumpAndSettle();
        expect(composer.text.text, '[ ] First\n[ ] Third\n[x] Second\n[ ] ');
        expect(tester.takeException(), isNull);
      },
    );

    for (final direction in TextDirection.values) {
      testWidgets(
        'leading handle moves blocks with a centered insertion line ($dark, $direction)',
        (tester) async {
          await mount(tester, direction: direction, dark: dark);
          final original = composer.text.value;
          final blocks = composer.blocks.index.blocks;
          final start = find.byKey(
            ValueKey('composer-block-handle-${blocks.first.id}'),
          );
          final add = find.byKey(
            ValueKey('composer-block-add-${blocks.first.id}'),
          );
          final end = find.byKey(
            ValueKey('composer-block-handle-${blocks.first.id}-end'),
          );
          final surface = tester.widget<ComposerBlockSurface>(
            find.byType(ComposerBlockSurface),
          );
          final first = surface.blockRect(blocks.first)!;
          final before = surface.blockRect(blocks[1])!;
          final after = surface.blockRect(blocks[2])!;
          expect(end, findsNothing);
          if (direction == TextDirection.ltr) {
            expect(tester.getRect(add).right, tester.getRect(start).left);
            expect(tester.getRect(start).right, lessThanOrEqualTo(first.left));
          } else {
            expect(tester.getRect(add).left, tester.getRect(start).right);
            expect(
              tester.getRect(start).left,
              greaterThanOrEqualTo(first.right),
            );
          }

          final gesture = await tester.startGesture(
            tester.getCenter(start),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, 20));
          await tester.pump();
          final highlight = find.byType(DDragHighlight);
          expect(highlight, findsOneWidget);
          final sourceTint = tester.getRect(highlight);
          expect(sourceTint.top, lessThanOrEqualTo(first.top));
          expect(sourceTint.bottom, greaterThanOrEqualTo(first.bottom));
          expect(
            sourceTint.bottom,
            lessThanOrEqualTo(before.top + 1),
            reason:
                'Compact adjacent line boxes can overlap by a fractional pixel',
          );
          final gapCenter = (before.bottom + after.top) / 2;
          await gesture.moveTo(Offset(first.center.dx, gapCenter));
          await tester.pump();
          await tester.pump();
          expect(
            tester.getCenter(find.byType(DDropIndicator)).dy,
            closeTo(gapCenter, .01),
          );
          expect(start, findsOneWidget);
          expect(end, findsNothing);
          expect(tester.getRect(highlight), sourceTint);
          expect(composer.text.value, original);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(
            composer.text.text,
            '## A heading\n\nFirst paragraph\n\nLast paragraph',
          );
          expect(find.byType(DDropIndicator), findsNothing);
          expect(highlight, findsNothing);
          composer.history.undo();
          await tester.pumpAndSettle();
          expect(composer.text.value, original);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('the original gap shows feedback without adding an undo edit', (
    tester,
  ) async {
    await mount(tester);
    final original = composer.text.value;
    final blocks = composer.blocks.index.blocks;
    final surface = tester.widget<ComposerBlockSurface>(
      find.byType(ComposerBlockSurface),
    );
    final before = surface.blockRect(blocks[0])!;
    final after = surface.blockRect(blocks[1])!;
    final midpoint = (before.bottom + after.top) / 2;
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(ValueKey('composer-block-handle-${blocks.first.id}')),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(Offset(before.center.dx, midpoint));
    await tester.pump();
    await tester.pump();
    expect(
      tester.getCenter(find.byType(DDropIndicator)).dy,
      closeTo(midpoint, .01),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(composer.text.value, original);
    expect(composer.history.canUndo, isFalse);
  });

  testWidgets('rapid moves remain separate for keyboard and native actions', (
    tester,
  ) async {
    await mount(tester);
    composer.focus.requestFocus();
    await tester.pump();
    final original = composer.text.text;
    final id = composer.blocks.index.blocks.first.id;
    composer.blocks.moveTo(
      2,
      blockId: id,
      expectedRevision: composer.blocks.revision,
    );
    final once = composer.text.text;
    composer.blocks.moveTo(
      3,
      blockId: id,
      expectedRevision: composer.blocks.revision,
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(composer.text.text, once);
    Actions.invoke(
      tester.element(find.byType(EditableText)),
      const UndoTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    expect(composer.text.text, original);
    Actions.invoke(
      tester.element(find.byType(EditableText)),
      const RedoTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    expect(composer.text.text, once);
    UndoManager.client!.handlePlatformUndo(UndoDirection.undo);
    await tester.pump();
    expect(composer.text.text, original);
  });

  testWidgets('Escape and edits during a drag do not reorder source', (
    tester,
  ) async {
    await mount(tester);
    composer.focus.requestFocus();
    await tester.pump();
    final original = composer.text.text;
    final handle = find.byKey(
      ValueKey(
        'composer-block-handle-${composer.blocks.index.blocks.first.id}',
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(40, 90));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(DDragHighlight), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(composer.text.text, original);
    final second = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.mouse,
    );
    await second.moveBy(const Offset(40, 90));
    await tester.pump();
    composer.text.text = '$original changed';
    await tester.pump();
    expect(find.byType(DDragHighlight), findsNothing);
    await second.up();
    await tester.pumpAndSettle();
    expect(composer.text.text, '$original changed');
  });

  testWidgets('handle menus move blocks up and down', (tester) async {
    await mount(tester);
    final id = composer.blocks.index.blocks.first.id;
    final handle = find.byKey(ValueKey('composer-block-handle-$id'));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(find.text('Move to…'), findsNothing);
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();
    expect(
      composer.text.text,
      '## A heading\n\nFirst paragraph\n\nLast paragraph',
    );
    await hoverSelection(tester);
    await tester.tap(handle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();
    expect(
      composer.text.text,
      'First paragraph\n\n## A heading\n\nLast paragraph',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('handle drag scrolls a long draft at the viewport edge', (
    tester,
  ) async {
    final original = List.generate(
      60,
      (index) => 'Paragraph $index',
    ).join('\n\n');
    composer.text.value = TextEditingValue(
      text: original,
      selection: const TextSelection.collapsed(offset: 0),
    );
    await mount(tester);
    final handle = find.byKey(
      ValueKey(
        'composer-block-handle-${composer.blocks.index.blocks.first.id}',
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    await gesture.moveTo(const Offset(150, 694));
    await tester.pump(const Duration(seconds: 1));
    final positions = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((state) => state.position.pixels);
    expect(positions.any((pixels) => pixels > 0), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(composer.text.text, original);
  });
}
