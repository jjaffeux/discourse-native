import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_table.dart';
import 'package:discourse_native/src/shell/composer_tables.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _source =
    'Before\n\n| Name | Cost |\n| :--- | ---: |\n| Tea | 12 |\n| Cake | 30 |\n\nAfter';
const _target = ComposerTarget(
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'topic',
  topicTitle: 'Topic',
);

Finder _cell(int row, int column) => find.descendant(
  of: find.byKey(ValueKey('table-cell-$row-$column')),
  matching: find.byType(EditableText),
);
Finder _action(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is DButton && widget.tooltip == tooltip,
);

Future<ComposerController> _pump(
  WidgetTester tester, {
  String source = _source,
  bool dark = false,
  double width = 760,
  double scale = 1,
}) async {
  final composer = ComposerController(_target);
  addTearDown(composer.dispose);
  composer.text.value = TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: source.length),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(
              width: width,
              child: ComposerEditor(
                composer: composer,
                hintText: 'Write a reply',
                textStyle: const TextStyle(fontSize: 16, height: 1.5),
                hintStyle: null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return composer;
}

Future<void> _menu(WidgetTester tester, String label, String action) async {
  await tester.tap(_action(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

Future<ComposerController> _pumpPanel(
  WidgetTester tester,
  String source,
) async {
  final composer = ComposerController(_target);
  composer.text.value = TextEditingValue(
    text: source,
    selection: const TextSelection.collapsed(offset: 0),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(composer.dispose);
  addTearDown(shell.dispose);
  await shell.load();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ShellScope(
        controller: shell,
        child: Scaffold(body: ComposerPanel(composer: composer, height: 550)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return composer;
}

void main() {
  for (final row in [0, 1]) {
    testWidgets(
      'typing in a large table rebuilds only the edited input (row $row)',
      (tester) async {
        final source = [
          '| Name | Place | Arrival | Notes |',
          '| --- | --- | --- | --- |',
          for (var i = 0; i < 14; i++)
            '| Member $i | Madrid | Saturday | Notes $i |',
        ].join('\n');
        final composer = await _pump(tester, source: source);
        await tester.showKeyboard(_cell(row, 0));
        await tester.pumpAndSettle();
        var otherInputs = 0;
        var builds = 0;
        final previous = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          builds++;
          if (element.widget is DInput &&
              element.widget.key != ValueKey('table-cell-$row-0')) {
            otherInputs++;
          }
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previous);
        final watch = Stopwatch()..start();
        for (var i = 1; i <= 5; i++) {
          tester.testTextInput.enterText('Member 0${'x' * i}');
          expect(
            parseComposerTables(composer.raw).single.cell(row, 0),
            'Member 0${'x' * i}',
          );
          await tester.pump();
        }
        watch.stop();
        debugPrint(
          'TABLE TYPING: ${watch.elapsedMilliseconds}ms, $builds builds, $otherInputs unrelated input rebuilds',
        );
        expect(
          parseComposerTables(composer.raw).single.cell(row, 0),
          'Member 0xxxxx',
        );
        expect(otherInputs, 0);
        debugOnRebuildDirtyWidget = previous;
        // Cached menus must remain usable after edits to their cells.
        composer.text.imageScrollController!.jumpTo(0);
        await tester.pumpAndSettle();
        await _menu(tester, 'Column 1 actions', 'Insert column after');
        expect(parseComposerTables(composer.raw).single.columnCount, 5);
        expect(
          parseComposerTables(composer.raw).single.cell(row, 0),
          'Member 0xxxxx',
        );
      },
    );
  }

  for (final action in ['Insert row above', 'Insert row below', 'Delete row']) {
    for (final padding in [false, true]) {
      testWidgets('right-click row: $action (padding: $padding)', (
        tester,
      ) async {
        final composer = await _pump(tester);
        final before = composer.value.selection;
        final input = _cell(1, 0);
        final cell = find
            .ancestor(
              of: input,
              matching: find.byWidgetPredicate((w) => w is DTableCell),
            )
            .first;
        final point = padding
            ? tester.getRect(cell).topLeft + const Offset(2, 2)
            : tester.getCenter(input);
        await tester.tapAt(
          point,
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(find.text('Insert row above'), findsOneWidget);
        expect(find.text('Insert row below'), findsOneWidget);
        expect(find.text('Delete row'), findsOneWidget);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
        expect(composer.value.selection, before);
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        final table = parseComposerTables(composer.raw).single;
        switch (action) {
          case 'Delete row':
            expect(table.rowCount, 1);
            expect(table.cell(1, 0), 'Cake');
          case 'Insert row above':
            expect(table.rowCount, 3);
            expect(table.cell(1, 0), '');
            expect(table.cell(2, 0), 'Tea');
          case 'Insert row below':
            expect(table.rowCount, 3);
            expect(table.cell(1, 0), 'Tea');
            expect(table.cell(2, 0), '');
        }
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }
  }

  for (final dark in [false, true]) {
    testWidgets('cell padding focuses the editor (dark: $dark)', (
      tester,
    ) async {
      final composer = await _pump(
        tester,
        dark: dark,
        source: _source.replaceFirst('Cake', ''),
      );
      for (final row in [0, 1, 2]) {
        final input = _cell(row, 0);
        final cell = find
            .ancestor(
              of: input,
              matching: find.byWidgetPredicate(
                (widget) => widget is DTableCell,
              ),
            )
            .first;
        final rect = tester.getRect(cell);
        final points = [
          rect.topLeft + const Offset(2, 2),
          rect.bottomLeft + const Offset(2, -2),
          Offset(rect.center.dx, rect.top + 2),
          Offset(rect.center.dx, rect.bottom - 2),
          if (row > 0) ...[
            rect.topRight + const Offset(-2, 2),
            rect.bottomRight + const Offset(-2, -2),
          ],
        ];
        for (final point in points) {
          await tester.tap(_cell(row, 1));
          await tester.pump();
          await tester.tapAt(point, kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
          expect(
            tester.widget<EditableText>(input).focusNode.hasFocus,
            isTrue,
            reason: 'Row $row at $point',
          );
          expect(composer.text.selection.isCollapsed, isTrue);
        }
        tester.testTextInput.enterText('Edited $row');
        await tester.pump();
        expect(
          parseComposerTables(composer.raw).single.cell(row, 0),
          'Edited $row',
        );
      }
      final handle = find.byType(DResizableHandle).first;
      final widthBefore = tester.widget<DResizableHandle>(handle).value;
      await tester.drag(handle, const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DResizableHandle>(handle).value,
        greaterThan(widthBefore),
      );
      await _menu(tester, 'Column 1 actions', 'Insert column after');
      expect(parseComposerTables(composer.raw).single.columnCount, 3);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'cell edits retain authored padding without accumulating typed spaces',
    (tester) async {
      final source = _source.replaceFirst(' Tea ', '   Tea ');
      final composer = await _pump(tester, source: source);
      await tester.enterText(_cell(1, 0), ' Tea');
      await tester.pump();
      expect(composer.raw, source.replaceFirst('Tea', ' Tea'));
      await tester.enterText(_cell(1, 0), ' Tea ');
      await tester.pump();
      expect(composer.raw, source.replaceFirst('Tea', ' Tea '));
      await tester.enterText(_cell(1, 0), '');
      await tester.pump();
      expect(composer.raw, source.replaceFirst('Tea', ''));
      await tester.enterText(_cell(1, 0), 'Tea');
      await tester.pump();
      expect(composer.raw, source);
    },
  );

  testWidgets('select-all, delete, arrows and undo belong to the active cell', (
    tester,
  ) async {
    final composer = await _pump(tester);
    await tester.showKeyboard(_cell(1, 0));
    final controller = tester.widget<EditableText>(_cell(1, 0)).controller;
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    expect(composer.text.selection.isCollapsed, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.text, '');
    expect(composer.raw, _source.replaceFirst('Tea', ''));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(controller.text, 'Tea');
    expect(composer.raw, _source);
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.extentOffset, 2);
    expect(composer.text.keyboardSelectedSyntax, isNull);
  });

  testWidgets(
    'deleting rows, columns and a whole table preserves surrounding prose',
    (tester) async {
      final composer = await _pump(tester);
      await _menu(tester, 'Row 1 actions', 'Delete row');
      expect(parseComposerTables(composer.raw).single.cell(1, 0), 'Cake');
      await _menu(tester, 'Column 1 actions', 'Delete column');
      expect(parseComposerTables(composer.raw).single.cell(1, 0), '30');
      await _menu(tester, 'Row 1 actions', 'Delete row');
      expect(find.text('Add a row to start writing.'), findsOneWidget);
      await tester.tap(find.text('Add row'));
      await tester.pumpAndSettle();
      await tester.enterText(_cell(1, 0), 'New');
      await tester.pump();
      expect(parseComposerTables(composer.raw).single.cell(1, 0), 'New');
      await tester.tap(_action('Remove table'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerTableEditor), findsNothing);
      expect(composer.raw, 'Before\n\n\n\nAfter');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a source replacement invalidates stale cell callbacks', (
    tester,
  ) async {
    final composer = await _pump(tester);
    final onChanged = tester
        .widget<DInput>(find.byKey(const ValueKey('table-cell-1-0')))
        .onChanged!;
    composer.text.value = const TextEditingValue(
      text: 'Replacement draft',
      selection: TextSelection.collapsed(offset: 17),
    );
    onChanged('Stale cell edit');
    await tester.pumpAndSettle();
    expect(composer.raw, 'Replacement draft');
    expect(find.byType(ComposerTableEditor), findsNothing);
  });

  testWidgets('a retained column action cannot edit a replaced table', (
    tester,
  ) async {
    final composer = await _pump(tester);
    await tester.tap(_action('Column 2 actions'));
    await tester.pumpAndSettle();
    final delete = tester
        .widget<DDropdownMenuItem>(
          find.ancestor(
            of: find.text('Delete column'),
            matching: find.byType(DDropdownMenuItem),
          ),
        )
        .onPressed!;
    const replacement = 'Before\n\n| Heading |\n| --- |\n| New cell |\n\nAfter';
    composer.text.value = const TextEditingValue(
      text: replacement,
      selection: TextSelection.collapsed(offset: replacement.length),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete column'), findsNothing);
    delete();
    await tester.pumpAndSettle();
    expect(composer.raw, replacement);
    expect(tester.takeException(), isNull);
  });

  for (final suffix in ['', '\n', '\n\n', '\n\nExisting body']) {
    testWidgets(
      'typing after clicking below a table inserts body text (${suffix.length})',
      (tester) async {
        final source = '| Name | Cost |\n| --- | --- |\n| Tea | 12 |$suffix';
        final composer = await _pump(tester, source: source);
        await tester.tap(_cell(1, 0), kind: PointerDeviceKind.mouse);
        await tester.pump();
        final table = tester.getRect(find.byType(ComposerTableEditor));
        await tester.tapAt(
          Offset(table.left + 2, table.bottom + 12),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        expect(composer.focus.hasPrimaryFocus, isTrue);
        expect(
          composer.text.selection.extentOffset,
          greaterThanOrEqualTo(parseComposerTables(source).single.end),
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
        final caret = editable.getLocalRectForCaret(
          composer.text.selection.extent,
        );
        expect(
          editable.localToGlobal(caret.center).dy,
          closeTo(table.bottom + 12, 12),
        );
        final value = composer.text.value;
        final offset = value.selection.extentOffset;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: value.text.replaceRange(offset, offset, 'After'),
            selection: TextSelection.collapsed(offset: offset + 5),
          ),
        );
        await tester.pump();
        expect(
          composer.text.text,
          '${parseComposerTables(source).single.source}\nAfter${suffix.isEmpty ? '' : suffix.substring(1)}',
        );
        expect(
          parseComposerTables(composer.raw).single.source,
          parseComposerTables(source).single.source,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets('mouse clicks retain cell focus on macOS', (tester) async {
    final composer = await _pump(tester);
    await tester.tap(_cell(1, 0), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(
      tester.widget<EditableText>(_cell(1, 0)).focusNode.hasPrimaryFocus,
      isTrue,
    );
    await tester.enterText(_cell(1, 0), 'Mouse edit');
    await tester.pump();
    expect(composer.raw, _source.replaceFirst('Tea', 'Mouse edit'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('scrolling to an existing table preserves cell pointer ownership', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final source =
        '${'Paragraph before the table with [a link](https://example.test).\n\n> Quoted text\n\n' * 20}${'| Name | Count | Delegate | People | Activity |\n| :--- | ---: | --- | --- | --- |\n| Tea | 2 | @host | @one, @two | |\n'}${'| Other group | 3 | @host | @one, @two, @three |\n' * 15}\n\n${'Paragraph after the table.\n\n' * 30}'
            .trimRight();
    final composer = await _pumpPanel(tester, source);
    final scroll = composer.text.imageScrollController!;
    final editorTop = tester.getTopLeft(find.byType(ComposerEditor)).dy;
    final cellTop = tester.getTopLeft(_cell(1, 0)).dy;
    scroll.jumpTo(
      (cellTop - editorTop - 150).clamp(0, scroll.position.maxScrollExtent),
    );
    await tester.pumpAndSettle();
    final scrollBefore = scroll.offset;
    final point = tester.getCenter(_cell(1, 0));
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final cell = tester.widget<EditableText>(_cell(1, 0));
    expect(cell.focusNode.hasPrimaryFocus, isTrue);
    expect(composer.focus.hasFocus, isFalse);
    expect(scroll.offset, closeTo(scrollBefore, 1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(
      cell.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    expect(composer.text.selection.isCollapsed, isTrue);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Clicked cell',
        selection: TextSelection.collapsed(offset: 12),
      ),
    );
    await tester.pumpAndSettle();
    expect(composer.raw, source.replaceFirst('Tea', 'Clicked cell'));
    expect(find.byType(ComposerTableEditor), findsOneWidget);
    semantics.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'keyboard-selected tables open a cell and leave source selection safe',
    (tester) async {
      final composer = await _pump(tester);
      final table = parseComposerTables(composer.raw).single;
      composer.text.selection = TextSelection.collapsed(offset: table.start);
      composer.requestFocus();
      await tester.pump();
      expect(
        composer.text.keyboardSelectedSyntax?.kind,
        composerTableSyntaxKind,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(_cell(0, 0)).focusNode.hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(composer.text.keyboardSelectedSyntax, isNull);
      expect(composer.text.selection.extentOffset, table.end);
    },
  );

  testWidgets('paste and formatting shortcuts edit only the active cell', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => {'text': 'Coffee | Cake'},
        'Clipboard.hasStrings' => {'value': true},
        _ => null,
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final composer = await _pump(tester);
    await tester.showKeyboard(_cell(1, 0));
    final controller = tester.widget<EditableText>(_cell(1, 0)).controller;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(controller.text, 'Coffee | Cake');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(composer.raw, _source.replaceFirst('Tea', r'**Coffee** \| Cake'));
    expect(controller.text, '**Coffee** | Cake');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'table fields and actions are not descendants of the main text-field semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      final field = tester.getSemantics(
        find.byKey(const ValueKey('table-cell-1-0')),
      );
      final button = tester.getSemantics(_action('Row 1 actions'));
      final found = <int>{};
      void visit(SemanticsNode node, bool insideField) {
        if (node.id == field.id || node.id == button.id) {
          expect(insideField, isFalse);
          found.add(node.id);
        }
        for (final child in node.debugListChildrenInOrder(
          DebugSemanticsDumpOrder.traversalOrder,
        )) {
          visit(
            child,
            insideField || node.getSemanticsData().flagsCollection.isTextField,
          );
        }
      }

      visit(tester.getSemantics(find.byType(Scaffold)), false);
      expect(found, {field.id, button.id});
      semantics.dispose();
    },
  );
  testWidgets('Insert menu offers a table without installed composer plugins', (
    tester,
  ) async {
    final composer = ComposerController(_target);
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    await shell.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ShellScope(
          controller: shell,
          child: Scaffold(body: ComposerPanel(composer: composer, height: 550)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-insert')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposerTableEditor), findsOneWidget);
    expect(parseComposerTables(composer.raw).single.rowCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cell composition and selection survive consecutive source updates',
    (tester) async {
      final composer = await _pump(tester);
      await tester.showKeyboard(_cell(1, 0));
      const value = TextEditingValue(
        text: 'あいう',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 3),
      );
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
      expect(tester.widget<EditableText>(_cell(1, 0)).controller.value, value);
      expect(parseComposerTables(composer.raw).single.cell(1, 0), value.text);
      await tester.enterText(_cell(1, 0), 'one | two');
      await tester.pump();
      expect(
        tester.widget<EditableText>(_cell(1, 0)).controller.text,
        'one | two',
      );
      expect(
        parseComposerTables(composer.raw).single.cell(1, 0),
        r'one \| two',
      );
    },
  );

  testWidgets(
    'composer undo and redo restore exact cell and structural changes',
    (tester) async {
      final composer = await _pump(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(_cell(1, 0), 'Coffee');
      await tester.pump(const Duration(seconds: 1));
      final edited = composer.raw;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(composer.raw, _source);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(composer.raw, edited);
      await _menu(tester, 'Row 2 actions', 'Move row up');
      await tester.pump(const Duration(seconds: 1));
      composer.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(composer.raw, edited);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multiple tables and inline Markdown keep independent editing owners',
    (tester) async {
      const first =
          '[Site](https://example.test) | `Code`\n--- | ---\ntext | x';
      final composer = await _pump(tester, source: '$first\n\n$_source');
      expect(find.byType(ComposerTableEditor), findsNWidgets(2));
      expect(
        composer.text.syntaxBlocks.where(
          (block) => block.kind == composerTableSyntaxKind,
        ),
        hasLength(2),
      );
      await tester.enterText(_cell(1, 0).first, 'New');
      await tester.pump();
      expect(composer.raw, '${first.replaceFirst('text', 'New')}\n\n$_source');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'edits existing cells in the real composer without losing focus or source',
    (tester) async {
      final composer = await _pump(tester);
      expect(find.byType(DDataTable<int>), findsOneWidget);
      expect(find.byType(DTable), findsOneWidget);
      await tester.tap(_cell(1, 0));
      await tester.pump();
      final editable = tester.widget<EditableText>(_cell(1, 0));
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.enterText(_cell(1, 0), 'Coffee');
      await tester.pump();
      expect(
        tester.widget<EditableText>(_cell(1, 0)).focusNode,
        same(editable.focusNode),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(composer.raw, _source.replaceFirst('Tea', 'Coffee'));
      expect(composer.draft.reply, composer.raw);
      await tester.enterText(_cell(0, 1), 'Price');
      await tester.pump();
      expect(composer.raw, contains('| Name | Price |'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('moves and inserts rows and columns using their menus', (
    tester,
  ) async {
    final composer = await _pump(tester);
    await _menu(tester, 'Row 2 actions', 'Move row up');
    var table = parseComposerTables(composer.raw).single;
    expect(table.cell(1, 0), 'Cake');
    expect(table.cell(2, 0), 'Tea');
    await _menu(tester, 'Column 1 actions', 'Move column later');
    table = parseComposerTables(composer.raw).single;
    expect(table.cell(0, 0), 'Cost');
    expect(table.cell(1, 0), '30');
    expect(table.source, contains('| ---: | :--- |'));
    await _menu(tester, 'Row 1 actions', 'Insert row below');
    await _menu(tester, 'Column 1 actions', 'Insert column after');
    table = parseComposerTables(composer.raw).single;
    expect(table.rowCount, 3);
    expect(table.columnCount, 3);
    expect(table.cell(2, 1), '');
    expect(table.cell(3, 2), 'Tea');
    expect(composer.raw, startsWith('Before\n\n'));
    expect(composer.raw, endsWith('\n\nAfter'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Tab navigates cells, appends a last row, and Escape returns to composer',
    (tester) async {
      final composer = await _pump(tester);
      await tester.tap(_cell(1, 0));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(_cell(1, 1)).focusNode.hasFocus,
        isTrue,
      );
      await tester.tap(_cell(2, 1));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(parseComposerTables(composer.raw).single.rowCount, 3);
      expect(
        tester.widget<EditableText>(_cell(3, 0)).focusNode.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(composer.focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('insertion uses block separation and can be edited immediately', (
    tester,
  ) async {
    final composer = await _pump(tester, source: 'Intro');
    insertComposerTable(composer);
    await tester.pumpAndSettle();
    expect(composer.raw, startsWith('Intro\n\n| Column 1'));
    await tester.enterText(_cell(1, 0), 'First');
    await tester.pump();
    expect(parseComposerTables(composer.raw).single.cell(1, 0), 'First');
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('narrow large-text table scrolls without overflowing ($dark)', (
      tester,
    ) async {
      final composer = await _pump(tester, dark: dark, width: 320, scale: 2);
      final scroll = composer.text.imageScrollController!;
      scroll.jumpTo(
        (scroll.offset + tester.getCenter(find.text('Add row')).dy - 400).clamp(
          0,
          scroll.position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add row'));
      await tester.pumpAndSettle();
      expect(parseComposerTables(composer.raw).single.rowCount, 3);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'submission disables inputs and ignores a previously opened menu',
    (tester) async {
      final composer = await _pump(tester);
      await tester.tap(_action('Row 1 actions'));
      await tester.pumpAndSettle();
      final insert = tester
          .widget<DDropdownMenuItem>(
            find.ancestor(
              of: find.text('Insert row below'),
              matching: find.byType(DDropdownMenuItem),
            ),
          )
          .onPressed!;
      composer.beginSubmit();
      await tester.pump();
      expect(find.text('Insert row below'), findsNothing);
      insert();
      await tester.pumpAndSettle();
      expect(composer.raw, _source);
      expect(
        tester
            .widget<DInput>(find.byKey(const ValueKey('table-cell-1-0')))
            .enabled,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
