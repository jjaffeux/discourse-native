import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/plugin_api/composer_component.dart';
import 'package:discourse_native/src/plugin_api/composer_syntax.dart';
import 'package:discourse_native/src/shell/composer_document/selection.dart';
import 'package:discourse_native/src/shell/composer_hybrid/component_registration.dart';
import 'package:discourse_native/src/shell/composer_hybrid/field.dart';
import 'package:discourse_native/src/shell/composer_hybrid/session.dart';
import 'package:discourse_native/src/shell/composer_surface/composer_surface.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = PluginId('hybrid-field-test');
const _dateKind = ComposerSyntaxKind(owner: _owner, name: 'date');
const _gridKind = ComposerSyntaxKind(owner: _owner, name: 'grid');
const _markdown = 'a[date:x]b\n[grid:A|B]\nz';

void main() {
  testWidgets(
    'inline and block taps select atoms without exposing canonical syntax',
    (tester) async {
      final renderedValues = <Object>[];
      final session = _createSession(
        selection: const ComposerCaretSelection(0),
        onRender: renderedValues.add,
      );
      addTearDown(session.dispose);
      final surfaceController = ComposerSurfaceController();

      await tester.pumpWidget(
        _host(session, surfaceController: surfaceController),
      );
      await tester.pump();

      expect(surfaceController.snapshot!.projectedText, 'a\uFFFCb\n\uFFFC\nz');
      expect(
        surfaceController.snapshot!.projectedText,
        isNot(contains('[date:x]')),
      );
      expect(
        tester
            .widgetList<RichText>(find.byType(RichText))
            .map((text) => text.text.toPlainText())
            .join(),
        isNot(contains('[grid:A|B]')),
      );
      expect(
        renderedValues,
        containsAll(<Object>[
          'x',
          const _Grid(['A', 'B']),
        ]),
      );

      await tester.tap(find.text('Date x'));
      await tester.pump();
      expect(session.selection, isA<ComposerComponentSelection>());
      expect(
        (session.selection as ComposerComponentSelection).component.kind.value,
        _dateKind.id,
      );
      expect(session.markdown, _markdown);

      await tester.tapAt(_atomCenter(tester, surfaceOffset: 4));
      await tester.pump();
      expect(session.selection, isA<ComposerComponentSelection>());
      expect(
        (session.selection as ComposerComponentSelection).component.kind.value,
        _gridKind.id,
      );
      expect(session.markdown, _markdown);
    },
  );

  testWidgets('left and right traverse before, selected, and after', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final session = _createSession(selection: const ComposerCaretSelection(1));
    addTearDown(session.dispose);
    await tester.pumpWidget(
      _host(session, focusNode: focusNode, autofocus: true),
    );
    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(session.selection, isA<ComposerComponentSelection>());

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(session.selection, const ComposerCaretSelection(9));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(session.selection, isA<ComposerComponentSelection>());

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(session.selection, const ComposerCaretSelection(1));
  });

  testWidgets('backspace selects the boundary atom before deleting it', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final session = _createSession(selection: const ComposerCaretSelection(9));
    addTearDown(session.dispose);
    await tester.pumpWidget(
      _host(session, focusNode: focusNode, autofocus: true),
    );
    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    expect(session.selection, isA<ComposerComponentSelection>());
    expect(session.markdown, _markdown);

    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(session.markdown, 'ab\n[grid:A|B]\nz');
    expect(session.selection, const ComposerCaretSelection(1));
    expect(session.canUndo, isTrue);
  });

  testWidgets('forward delete treats a block as one verified transaction', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final session = _createSession(selection: const ComposerCaretSelection(11));
    addTearDown(session.dispose);
    await tester.pumpWidget(
      _host(session, focusNode: focusNode, autofocus: true),
    );
    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(session.selection, isA<ComposerComponentSelection>());
    expect(session.markdown, _markdown);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(session.markdown, 'a[date:x]b\n\nz');
    expect(session.selection, const ComposerCaretSelection(11));
  });

  testWidgets('Escape moves a selected component to its trailing boundary', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final session = _createSession(selection: const ComposerCaretSelection(0));
    addTearDown(session.dispose);
    await tester.pumpWidget(
      _host(session, focusNode: focusNode, autofocus: true),
    );
    focusNode.requestFocus();
    await tester.pump();

    await tester.tapAt(_atomCenter(tester, surfaceOffset: 4));
    await tester.pump();
    expect(session.selection, isA<ComposerComponentSelection>());

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(session.selection, const ComposerCaretSelection(21));
  });

  testWidgets(
    'native forward and reverse selections snap across the complete atom',
    (tester) async {
      final session = _createSession(
        selection: const ComposerCaretSelection(0),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(_host(session));
      await tester.pump();
      final editable = tester.widget<EditableText>(find.byType(EditableText));

      editable.controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
        isDirectional: true,
      );
      await tester.pump();
      expect(session.selection, ComposerRangeSelection(anchor: 0, focus: 9));
      expect(editable.controller.selection.baseOffset, 0);
      expect(editable.controller.selection.extentOffset, 2);

      editable.controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 0,
        isDirectional: true,
      );
      await tester.pump();
      expect(session.selection, ComposerRangeSelection(anchor: 9, focus: 0));
      expect(editable.controller.selection.baseOffset, 2);
      expect(editable.controller.selection.extentOffset, 0);
    },
  );

  testWidgets('a short precise-pointer drag ending on an atom is not a tap', (
    tester,
  ) async {
    final session = _createSession(selection: const ComposerCaretSelection(0));
    addTearDown(session.dispose);
    await tester.pumpWidget(_host(session));
    await tester.pump();
    final atomCenter = _atomCenter(tester, surfaceOffset: 1);
    final start = atomCenter - const Offset(2, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: start);
    addTearDown(mouse.removePointer);

    await mouse.down(start);
    await mouse.moveTo(atomCenter);
    await mouse.up();
    await tester.pump();

    expect(session.selection, isNot(isA<ComposerComponentSelection>()));
  });

  for (final atomFixture in _AtomFixture.values) {
    for (final operation in _OrdinaryEdit.values) {
      testWidgets(
        '${operation.name} ordinary text around the ${atomFixture.name} atom',
        (tester) async {
          final session = _createSession(
            selection: const ComposerCaretSelection(0),
          );
          addTearDown(session.dispose);
          await tester.pumpWidget(_host(session));
          await tester.pump();

          final plan = ComposerSurfaceProjectionPlan.fromProjection(
            session.snapshot.projection,
          );
          final atom = _atomFor(plan, atomFixture);
          final changedRange = operation.rangeFor(atom);
          final sourceRange = plan.sourceRangeForSurfaceRange(changedRange);
          final expectedMarkdown = _markdown.replaceRange(
            sourceRange.start,
            sourceRange.end,
            operation.replacement,
          );
          final controller = _editableController(tester);
          controller.selection = TextSelection(
            baseOffset: changedRange.start,
            extentOffset: changedRange.end,
          );
          final oldValue = controller.value;
          final proposedText = oldValue.text.replaceRange(
            changedRange.start,
            changedRange.end,
            operation.replacement,
          );

          controller.value = TextEditingValue(
            text: proposedText,
            selection: TextSelection.collapsed(
              offset: changedRange.start + operation.replacement.length,
            ),
          );

          expect(controller.value, oldValue);
          expect(session.markdown, expectedMarkdown);
          await tester.pump();
          expect(session.selection, isA<ComposerCaretSelection>());
          expect(
            _editableController(tester).text,
            isNot(anyOf(contains('[date:x]'), contains('[grid:A|B]'))),
          );
        },
      );
    }
  }

  testWidgets('completing syntax commits raw source then reprojects an atom', (
    tester,
  ) async {
    const incomplete = 'Start [date:x';
    final session = _createSession(
      markdown: incomplete,
      selection: const ComposerCaretSelection(incomplete.length),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(_host(session));
    await tester.pump();
    final controller = _editableController(tester);
    final oldValue = controller.value;

    controller.value = const TextEditingValue(
      text: '$incomplete]',
      selection: TextSelection.collapsed(offset: incomplete.length + 1),
    );

    expect(controller.value, oldValue);
    expect(session.markdown, '$incomplete]');
    await tester.pump();
    expect(_editableController(tester).text, 'Start \uFFFC');
    expect(_editableController(tester).text, isNot(contains('[date:x]')));
    expect(find.text('Date x'), findsOneWidget);
  });

  testWidgets(
    'typing over a selected inline atom replaces its exact source and undoes',
    (tester) async {
      final session = _createSession(
        selection: const ComposerCaretSelection(0),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(_host(session));
      await tester.pump();

      await tester.tap(find.text('Date x'));
      await tester.pump();
      await tester.pump();
      expect(session.selection, isA<ComposerComponentSelection>());
      final controller = _editableController(tester);
      final selectedValue = controller.value;
      expect(
        selectedValue.selection,
        const TextSelection(
          baseOffset: 1,
          extentOffset: 2,
          isDirectional: true,
        ),
      );

      const replacement = 'today';
      controller.value = TextEditingValue(
        text: selectedValue.text.replaceRange(1, 2, replacement),
        selection: const TextSelection.collapsed(
          offset: 1 + replacement.length,
        ),
      );

      expect(controller.value, selectedValue);
      expect(session.markdown, 'atodayb\n[grid:A|B]\nz');
      expect(session.revision.value, 1);
      expect(session.selection, const ComposerCaretSelection(6));
      expect(session.canUndo, isTrue);
      await tester.pump();
      expect(_editableController(tester).text, 'atodayb\n\uFFFC\nz');
      expect(
        _editableController(tester).text,
        isNot(anyOf(contains('[date:x]'), contains('[grid:A|B]'))),
      );

      Actions.invoke(
        tester.element(find.byType(ComposerSurface)),
        const UndoTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();

      expect(session.markdown, _markdown);
      expect(session.selection, isA<ComposerComponentSelection>());
      expect(_editableController(tester).text, 'a\uFFFCb\n\uFFFC\nz');
      expect(
        _editableController(tester).selection,
        const TextSelection(
          baseOffset: 1,
          extentOffset: 2,
          isDirectional: true,
        ),
      );
    },
  );

  testWidgets(
    'typing over a snapped text and atom range is one undoable transaction',
    (tester) async {
      final session = _createSession(
        selection: const ComposerCaretSelection(0),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(_host(session));
      await tester.pump();
      var controller = _editableController(tester);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
        isDirectional: true,
      );
      await tester.pump();
      controller = _editableController(tester);
      final selectedValue = controller.value;
      expect(session.selection, ComposerRangeSelection(anchor: 0, focus: 21));

      controller.value = TextEditingValue(
        text: selectedValue.text.replaceRange(0, 5, 'mix'),
        selection: const TextSelection.collapsed(offset: 3),
      );

      expect(controller.value, selectedValue);
      expect(session.markdown, 'mix\nz');
      expect(session.revision.value, 1);
      expect(session.selection, const ComposerCaretSelection(3));
      expect(session.canUndo, isTrue);
      await tester.pump();
      expect(_editableController(tester).text, 'mix\nz');
      expect(
        _editableController(tester).text,
        isNot(anyOf(contains('[date:x]'), contains('[grid:A|B]'))),
      );

      Actions.invoke(
        tester.element(find.byType(ComposerSurface)),
        const UndoTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();

      expect(session.markdown, _markdown);
      expect(session.selection, ComposerRangeSelection(anchor: 0, focus: 21));
      expect(_editableController(tester).text, 'a\uFFFCb\n\uFFFC\nz');
      expect(
        _editableController(tester).selection,
        const TextSelection(
          baseOffset: 0,
          extentOffset: 5,
          isDirectional: true,
        ),
      );
    },
  );

  testWidgets('collapsed and partial atom replacements remain vetoed', (
    tester,
  ) async {
    final session = _createSession(selection: const ComposerCaretSelection(1));
    addTearDown(session.dispose);
    await tester.pumpWidget(_host(session));
    await tester.pump();
    final controller = _editableController(tester);
    final collapsedValue = controller.value;

    controller.value = TextEditingValue(
      text: collapsedValue.text.replaceRange(1, 2, 'raw'),
      selection: const TextSelection.collapsed(offset: 4),
    );

    expect(controller.value, collapsedValue);
    expect(session.markdown, _markdown);
    expect(session.revision.value, 0);

    controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 1,
      isDirectional: true,
    );
    final partialValue = controller.value;
    controller.value = TextEditingValue(
      text: partialValue.text.replaceRange(0, 2, 'raw'),
      selection: const TextSelection.collapsed(offset: 3),
    );

    expect(controller.value, partialValue);
    expect(session.markdown, _markdown);
    expect(session.revision.value, 0);
  });

  for (final atomFixture in _AtomFixture.values) {
    for (final direction in _DeleteProposalDirection.values) {
      testWidgets('native ${direction.name} delete selects then removes the '
          '${atomFixture.name} atom', (tester) async {
        final probe = _createSession(
          selection: const ComposerCaretSelection(0),
        );
        final initialPlan = ComposerSurfaceProjectionPlan.fromProjection(
          probe.snapshot.projection,
        );
        final initialAtom = _atomFor(initialPlan, atomFixture);
        probe.dispose();
        final session = _createSession(
          selection: ComposerCaretSelection(
            direction == _DeleteProposalDirection.backward
                ? initialAtom.sourceAfter
                : initialAtom.sourceBefore,
          ),
        );
        addTearDown(session.dispose);
        await tester.pumpWidget(_host(session));
        await tester.pump();
        var controller = _editableController(tester);
        final oldValue = controller.value;
        final proposedDeletion = TextEditingValue(
          text: oldValue.text.replaceRange(
            initialAtom.surfaceBefore,
            initialAtom.surfaceAfter,
            '',
          ),
          selection: TextSelection.collapsed(offset: initialAtom.surfaceBefore),
        );

        controller.value = proposedDeletion;

        expect(controller.value, oldValue);
        expect(session.markdown, _markdown);
        expect(session.selection, isA<ComposerComponentSelection>());
        await tester.pump();
        controller = _editableController(tester);
        final selectedValue = controller.value;
        expect(selectedValue.selection.isCollapsed, isFalse);

        controller.value = TextEditingValue(
          text: selectedValue.text.replaceRange(
            initialAtom.surfaceBefore,
            initialAtom.surfaceAfter,
            '',
          ),
          selection: TextSelection.collapsed(offset: initialAtom.surfaceBefore),
        );

        expect(controller.value, selectedValue);
        expect(
          session.markdown,
          atomFixture == _AtomFixture.inline
              ? 'ab\n[grid:A|B]\nz'
              : 'a[date:x]b\n\nz',
        );
        await tester.pump();
        expect(
          _editableController(tester).text,
          atomFixture == _AtomFixture.inline
              ? 'ab\n\uFFFC\nz'
              : 'a\uFFFCb\n\nz',
        );
      });
    }
  }

  for (final deleteCase in _adjacentDeleteCases) {
    testWidgets(
      'adjacent atoms: ${deleteCase.name} selects and removes the exact atom',
      (tester) async {
        const adjacentMarkdown = '[date:a][date:b]';
        final session = _createSession(
          markdown: adjacentMarkdown,
          selection: ComposerCaretSelection(deleteCase.sourceCaret),
        );
        addTearDown(session.dispose);
        await tester.pumpWidget(_host(session));
        await tester.pump();
        var controller = _editableController(tester);
        final oldValue = controller.value;
        expect(oldValue.text, '\uFFFC\uFFFC');

        controller.value = TextEditingValue(
          text: '\uFFFC',
          selection: TextSelection.collapsed(
            offset: deleteCase.newSurfaceCaret,
          ),
        );

        expect(controller.value, oldValue);
        final selected = session.selection as ComposerComponentSelection;
        expect(selected.component.source, deleteCase.selectedSource);
        await tester.pump();
        controller = _editableController(tester);
        final selectedValue = controller.value;
        expect(
          selectedValue.selection,
          TextSelection(
            baseOffset: deleteCase.selectedSurfaceOffset,
            extentOffset: deleteCase.selectedSurfaceOffset + 1,
            isDirectional: true,
          ),
        );

        controller.value = TextEditingValue(
          text: selectedValue.text.replaceRange(
            deleteCase.selectedSurfaceOffset,
            deleteCase.selectedSurfaceOffset + 1,
            '',
          ),
          selection: TextSelection.collapsed(
            offset: deleteCase.selectedSurfaceOffset,
          ),
        );

        expect(controller.value, selectedValue);
        expect(session.markdown, deleteCase.remainingMarkdown);
        await tester.pump();
        expect(_editableController(tester).text, '\uFFFC');
      },
    );
  }

  testWidgets('native deletion of a snapped crossing range is canonical', (
    tester,
  ) async {
    final session = _createSession(selection: const ComposerCaretSelection(0));
    addTearDown(session.dispose);
    await tester.pumpWidget(_host(session));
    await tester.pump();
    final controller = _editableController(tester);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    final selectedValue = controller.value;
    expect(session.selection, isA<ComposerRangeSelection>());

    controller.value = TextEditingValue(
      text: selectedValue.text.replaceRange(0, 5, ''),
      selection: const TextSelection.collapsed(offset: 0),
    );

    expect(controller.value, selectedValue);
    expect(session.markdown, '\nz');
    expect(session.revision.value, 1);
    await tester.pump();
    expect(_editableController(tester).text, '\nz');
  });

  testWidgets('atom, object character, and composition proposals are vetoed', (
    tester,
  ) async {
    final session = _createSession(selection: const ComposerCaretSelection(0));
    addTearDown(session.dispose);
    await tester.pumpWidget(_host(session));
    await tester.pump();
    final controller = _editableController(tester);
    final oldValue = controller.value;

    controller.value = TextEditingValue(
      text: oldValue.text.replaceRange(1, 2, 'raw'),
      selection: const TextSelection.collapsed(offset: 4),
    );
    expect(controller.value, oldValue);

    controller.value = TextEditingValue(
      text: '$composerSurfaceObjectReplacementCharacter${oldValue.text}',
      selection: const TextSelection.collapsed(offset: 1),
    );
    expect(controller.value, oldValue);

    controller.value = TextEditingValue(
      text: 'q${oldValue.text}',
      selection: const TextSelection.collapsed(offset: 1),
      composing: const TextRange(start: 0, end: 1),
    );
    expect(controller.value, oldValue);
    expect(session.markdown, _markdown);
    expect(session.revision.value, 0);
  });

  testWidgets('alternate cut shortcut cannot edit the projected buffer', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final session = _createSession(selection: const ComposerCaretSelection(0));
    addTearDown(session.dispose);
    await tester.pumpWidget(
      _host(session, focusNode: focusNode, autofocus: true),
    );
    focusNode.requestFocus();
    await tester.pump();
    final controller = _editableController(tester);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(session.markdown, _markdown);
    expect(_editableController(tester).text, 'a\uFFFCb\n\uFFFC\nz');
  });

  testWidgets('undo and both redo chords use canonical session history', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final session = _createSession(selection: const ComposerCaretSelection(0));
    addTearDown(session.dispose);
    await tester.pumpWidget(
      _host(session, focusNode: focusNode, autofocus: true),
    );
    focusNode.requestFocus();
    await tester.pump();
    final controller = _editableController(tester);
    final oldValue = controller.value;

    controller.value = TextEditingValue(
      text: 'Q${oldValue.text}',
      selection: const TextSelection.collapsed(offset: 1),
    );
    expect(controller.value, oldValue);
    await tester.pump();
    expect(session.markdown, 'Q$_markdown');

    await _sendControlShortcut(tester, LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(session.markdown, _markdown);

    await _sendControlShortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
    await tester.pump();
    expect(session.markdown, 'Q$_markdown');

    await _sendControlShortcut(tester, LogicalKeyboardKey.keyZ);
    await tester.pump();
    await _sendControlShortcut(tester, LogicalKeyboardKey.keyY);
    await tester.pump();
    expect(session.markdown, 'Q$_markdown');

    final actionContext = tester.element(find.byType(ComposerSurface));
    Actions.invoke(
      actionContext,
      const UndoTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    expect(session.markdown, _markdown);
    Actions.invoke(
      actionContext,
      const RedoTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    expect(session.markdown, 'Q$_markdown');
    expect(_editableController(tester).text, 'Qa\uFFFCb\n\uFFFC\nz');
    expect(
      composerHybridFieldSurfaceGate.supported,
      containsAll(<ComposerSurfaceCapability>{
        ComposerSurfaceCapability.plainTextEditing,
        ComposerSurfaceCapability.revisionBoundComponentActions,
        ComposerSurfaceCapability.undoRedo,
      }),
    );
    expect(
      composerHybridFieldSurfaceGate.blockers,
      isNot(contains(ComposerSurfaceCapability.undoRedo)),
    );
    expect(
      composerHybridFieldSurfaceGate.blockers,
      isNot(contains(ComposerSurfaceCapability.revisionBoundComponentActions)),
    );
    expect(
      composerHybridFieldSurfaceGate.blockers.keys,
      containsAll(<ComposerSurfaceCapability>{
        ComposerSurfaceCapability.imeComposition,
        ComposerSurfaceCapability.clipboard,
        ComposerSurfaceCapability.accessibility,
      }),
    );
  });
}

const _gridWidgetKey = ValueKey<String>('grid-widget');

ComposerHybridEditingSession _createSession({
  required ComposerSelection selection,
  String markdown = _markdown,
  ValueChanged<Object>? onRender,
}) {
  return ComposerHybridEditingSession(
    markdown: markdown,
    selection: selection,
    registrations: [
      ComposerHybridComponentRegistration.from(
        ComposerComponent<String>.inline(
          kind: _dateKind,
          find: _findDates,
          builder: (context, component) {
            onRender?.call(component.value);
            return Text('Date ${component.value}');
          },
          semanticLabel: (context, component) => 'Date ${component.value}',
        ),
      ),
      ComposerHybridComponentRegistration.from(
        ComposerComponent<_Grid>.block(
          kind: _gridKind,
          find: _findGrids,
          builder: (context, component) {
            onRender?.call(component.value);
            return SizedBox(
              key: _gridWidgetKey,
              height: 80,
              child: Text('Grid ${component.value.cells.join(' / ')}'),
            );
          },
          semanticLabel: (context, component) =>
              'Grid with ${component.value.cells.length} cells',
        ),
      ),
    ],
  );
}

Iterable<ComposerComponentCandidate<String>> _findDates(String markdown) {
  return RegExp(r'\[date:([^\]]+)\]').allMatches(markdown).map((match) {
    return ComposerComponentCandidate<String>(
      range: TextRange(start: match.start, end: match.end),
      value: match.group(1)!,
    );
  });
}

Iterable<ComposerComponentCandidate<_Grid>> _findGrids(String markdown) {
  return RegExp(r'\[grid:([^\]]+)\]').allMatches(markdown).map((match) {
    return ComposerComponentCandidate<_Grid>(
      range: TextRange(start: match.start, end: match.end),
      value: _Grid(match.group(1)!.split('|')),
    );
  });
}

Widget _host(
  ComposerHybridEditingSession session, {
  ComposerSurfaceController? surfaceController,
  FocusNode? focusNode,
  bool autofocus = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 500,
        child: ComposerHybridField(
          session: session,
          surfaceController: surfaceController,
          focusNode: focusNode,
          autofocus: autofocus,
        ),
      ),
    ),
  );
}

Offset _atomCenter(WidgetTester tester, {required int surfaceOffset}) {
  final editable = tester.state<EditableTextState>(find.byType(EditableText));
  final boxes = editable.renderEditable.getBoxesForSelection(
    TextSelection(baseOffset: surfaceOffset, extentOffset: surfaceOffset + 1),
  );
  final box = boxes.reduce((largest, candidate) {
    final largestRect = largest.toRect();
    final candidateRect = candidate.toRect();
    return candidateRect.width * candidateRect.height >
            largestRect.width * largestRect.height
        ? candidate
        : largest;
  });
  return editable.renderEditable.localToGlobal(box.toRect().center);
}

TextEditingController _editableController(WidgetTester tester) {
  return tester.widget<EditableText>(find.byType(EditableText)).controller;
}

ComposerSurfaceAtomMapping _atomFor(
  ComposerSurfaceProjectionPlan plan,
  _AtomFixture fixture,
) {
  final expectedKind = switch (fixture) {
    _AtomFixture.inline => _dateKind.id,
    _AtomFixture.block => _gridKind.id,
  };
  return plan.atoms.singleWhere(
    (atom) => atom.component.kind.value == expectedKind,
  );
}

Future<void> _sendControlShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

enum _AtomFixture { inline, block }

enum _DeleteProposalDirection { backward, forward }

const _adjacentDeleteCases = <_AdjacentDeleteCase>[
  _AdjacentDeleteCase(
    name: 'forward delete before the first',
    sourceCaret: 0,
    newSurfaceCaret: 0,
    selectedSurfaceOffset: 0,
    selectedSource: '[date:a]',
    remainingMarkdown: '[date:b]',
  ),
  _AdjacentDeleteCase(
    name: 'backspace between atoms',
    sourceCaret: 8,
    newSurfaceCaret: 0,
    selectedSurfaceOffset: 0,
    selectedSource: '[date:a]',
    remainingMarkdown: '[date:b]',
  ),
  _AdjacentDeleteCase(
    name: 'forward delete between atoms',
    sourceCaret: 8,
    newSurfaceCaret: 1,
    selectedSurfaceOffset: 1,
    selectedSource: '[date:b]',
    remainingMarkdown: '[date:a]',
  ),
  _AdjacentDeleteCase(
    name: 'backspace after the second',
    sourceCaret: 16,
    newSurfaceCaret: 1,
    selectedSurfaceOffset: 1,
    selectedSource: '[date:b]',
    remainingMarkdown: '[date:a]',
  ),
];

final class _AdjacentDeleteCase {
  const _AdjacentDeleteCase({
    required this.name,
    required this.sourceCaret,
    required this.newSurfaceCaret,
    required this.selectedSurfaceOffset,
    required this.selectedSource,
    required this.remainingMarkdown,
  });

  final String name;
  final int sourceCaret;
  final int newSurfaceCaret;
  final int selectedSurfaceOffset;
  final String selectedSource;
  final String remainingMarkdown;
}

enum _OrdinaryEdit {
  insertion,
  deletion,
  replace;

  ComposerSurfaceRange rangeFor(ComposerSurfaceAtomMapping atom) {
    return switch (this) {
      _OrdinaryEdit.insertion => ComposerSurfaceRange(
        atom.surfaceBefore,
        atom.surfaceBefore,
      ),
      _OrdinaryEdit.deletion => ComposerSurfaceRange(
        atom.surfaceAfter,
        atom.surfaceAfter + 1,
      ),
      _OrdinaryEdit.replace => ComposerSurfaceRange(
        atom.surfaceBefore - 1,
        atom.surfaceBefore,
      ),
    };
  }

  String get replacement => switch (this) {
    _OrdinaryEdit.insertion => 'I',
    _OrdinaryEdit.deletion => '',
    _OrdinaryEdit.replace => 'R',
  };
}

final class _Grid {
  const _Grid(this.cells);

  final List<String> cells;

  @override
  bool operator ==(Object other) =>
      other is _Grid &&
      other.cells.length == cells.length &&
      Iterable.generate(
        cells.length,
        (index) => other.cells[index] == cells[index],
      ).every((matches) => matches);

  @override
  int get hashCode => Object.hashAll(cells);
}
