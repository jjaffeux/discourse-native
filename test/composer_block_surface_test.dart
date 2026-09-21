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
      textStyle: theme.textTheme.bodyLarge,
      expands: !mobile,
      autofocus: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: MediaQuery(
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
    );
    await tester.pumpAndSettle();
  }

  Future<void> arrange(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Arrange blocks'));
    await tester.pumpAndSettle();
  }

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
    expect(
      find.text('${composer.blocks.index.blocks.first.label} actions'),
      findsNothing,
    );
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

  testWidgets(
    '320px mobile Arrange retains the editor and supports arrows, undo and tap-to-place',
    (tester) async {
      await mount(tester, mobile: true, textScale: 1.3);
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      final original = composer.text.value;
      composer.focus.requestFocus();
      await tester.pump();
      await arrange(tester);
      expect(composer.focus.hasFocus, isFalse);
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.byTooltip('Move down'));
      await tester.pumpAndSettle();
      expect(
        composer.text.text,
        '## A heading\n\nFirst paragraph\n\nLast paragraph',
      );
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(composer.text.value, original);
      await tester.tap(find.text('Move to…'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('composer-block-place-3')),
      );
      await tester.tap(find.byKey(const ValueKey('composer-block-place-3')));
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
    await second.up();
    await tester.pumpAndSettle();
    expect(composer.text.text, '$original changed');
  });

  for (final mobile in [false, true]) {
    testWidgets(
      'handle menus move blocks and open destination selection ($mobile)',
      (tester) async {
        await mount(tester, mobile: mobile);
        if (mobile) await arrange(tester);
        final id = composer.blocks.index.blocks.first.id;
        final handle = find.byKey(ValueKey('composer-block-handle-$id'));
        await tester.tap(handle);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Move down'));
        await tester.pumpAndSettle();
        expect(
          composer.text.text,
          '## A heading\n\nFirst paragraph\n\nLast paragraph',
        );
        await tester.tap(handle);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Move to…').last);
        await tester.pumpAndSettle();
        expect(composer.blocks.arranging, isTrue);
        expect(composer.blocks.choosingDestination, isTrue);
        await tester.tap(find.byKey(const ValueKey('composer-block-place-0')));
        await tester.pumpAndSettle();
        expect(
          composer.text.text,
          'First paragraph\n\n## A heading\n\nLast paragraph',
        );
        expect(tester.takeException(), isNull);
      },
    );

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
