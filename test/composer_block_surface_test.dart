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
      platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
    );
    final editor = ComposerEditor(
      composer: composer,
      hintText: 'Write a reply…',
      hintStyle: theme.textTheme.bodyLarge,
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
                      ComposerArrangeButton(composer: composer),
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

  Future<void> arrange(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Arrange blocks'));
    await tester.pumpAndSettle();
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
    composer.history.undo();
    await tester.pumpAndSettle();
    expect(composer.text.value, original);
    expect(composer.history.canUndo, isFalse);
    await tester.tap(find.byTooltip('Add block'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heading 2'));
    await tester.pumpAndSettle();
    expect(
      composer.text.text,
      'First paragraph\n\n## \n\n## A heading\n\nLast paragraph',
    );
  });

  testWidgets(
    'accessibility activation opens commands without keyboard input',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester);
      for (var attempt = 0; attempt < 2; attempt++) {
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
      final offset = source.startsWith('Before') ? 'Before\n'.length : 0;
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
      expect(handle, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
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
    final blank = editable.getLocalRectForCaret(const TextPosition(offset: 6));
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
    expect(composer.text.text, 'First\n/\n\nLast');
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
      expect(add().onPressed, isNull);
    },
  );

  testWidgets('add leaves Arrange mode and opens the editor commands', (
    tester,
  ) async {
    await mount(tester, mobile: true, textScale: 1.3);
    await arrange(tester);
    expect(find.byTooltip('Add block'), findsNWidgets(3));
    await tester.tap(find.byTooltip('Add block').first);
    await tester.pumpAndSettle();
    expect(composer.blocks.arranging, isFalse);
    expect(find.text('Type to search'), findsOneWidget);
    expect(composer.focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('mobile arrangement exposes each to-do as a separate row', (
    tester,
  ) async {
    composer.text.value = const TextEditingValue(
      text: '[ ] First\n[x] Second\n[ ] ',
      selection: TextSelection.collapsed(offset: 4),
    );
    composer.history.reset();
    await mount(tester, mobile: true, textScale: 1.5);
    await arrange(tester);
    final blocks = composer.blocks.index.blocks;
    expect(blocks, hasLength(3));
    for (final block in blocks) {
      expect(
        find.byKey(ValueKey('composer-block-handle-${block.id}')),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.byKey(ValueKey('composer-block-handle-${blocks.first.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();
    expect(composer.text.text, '[x] Second\n[ ] First\n[ ] ');
    composer.history.undo();
    await tester.pumpAndSettle();
    expect(composer.text.text, '[ ] First\n[x] Second\n[ ] ');
    expect(tester.takeException(), isNull);
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
    final first = lineAt('First paragraph\n'.length);
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
          expect(sourceTint.bottom, lessThan(before.top));
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

  testWidgets(
    '320px mobile Arrange retains the editor and supports arrows and undo',
    (tester) async {
      await mount(tester, mobile: true, textScale: 1.3);
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      final original = composer.text.value;
      composer.focus.requestFocus();
      await tester.pump();
      await arrange(tester);
      expect(composer.focus.hasFocus, isFalse);
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('Move to…'), findsNothing);
      await tester.tap(find.byTooltip('Move down'));
      await tester.pumpAndSettle();
      expect(
        composer.text.text,
        '## A heading\n\nFirst paragraph\n\nLast paragraph',
      );
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(composer.text.value, original);
      await tester.tap(find.byTooltip('Move down'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Move down'));
      await tester.pumpAndSettle();
      expect(
        composer.text.text,
        '## A heading\n\nLast paragraph\n\nFirst paragraph',
      );
      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(editor),
      );
      expect(composer.focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

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

  for (final mobile in [false, true]) {
    testWidgets('handle menus move blocks up and down ($mobile)', (
      tester,
    ) async {
      await mount(tester, mobile: mobile);
      if (mobile) await arrange(tester);
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
      await tester.tap(handle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      expect(
        composer.text.text,
        'First paragraph\n\n## A heading\n\nLast paragraph',
      );
      expect(composer.blocks.arranging, mobile);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'handle drag scrolls a long draft at the viewport edge ($mobile)',
      (tester) async {
        final original = List.generate(
          60,
          (index) => 'Paragraph $index',
        ).join('\n\n');
        composer.text.value = TextEditingValue(
          text: original,
          selection: const TextSelection.collapsed(offset: 0),
        );
        await mount(tester, mobile: mobile);
        if (mobile) await arrange(tester);
        final handle = find.byKey(
          ValueKey(
            'composer-block-handle-${composer.blocks.index.blocks.first.id}',
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(handle),
          kind: mobile ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
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
      },
    );
  }
}
