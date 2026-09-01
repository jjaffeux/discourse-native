import 'package:discourse_native/src/shell/composer_document/component.dart';
import 'package:discourse_native/src/shell/composer_document/document.dart';
import 'package:discourse_native/src/shell/composer_document/interaction.dart';
import 'package:discourse_native/src/shell/composer_document/selection.dart';
import 'package:discourse_native/src/shell/composer_document/source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reducer = ComposerInteractionReducer();

  group('ComposerInteractionReducer atom traversal', () {
    test('moves before to selected to after, and back symmetrically', () {
      final document = _document(
        layout: ComposerComponentLayout.inline,
        selection: const ComposerCaretSelection(1),
      );

      _applySelection(
        document,
        reducer.reduce(
          document.snapshot,
          const ComposerMoveIntent(ComposerMoveDirection.right),
        ),
      );
      expect(document.snapshot.selection, isA<ComposerComponentSelection>());

      _applySelection(
        document,
        reducer.reduce(
          document.snapshot,
          const ComposerMoveIntent(ComposerMoveDirection.right),
        ),
      );
      expect(document.snapshot.selection, const ComposerCaretSelection(7));

      _applySelection(
        document,
        reducer.reduce(
          document.snapshot,
          const ComposerMoveIntent(ComposerMoveDirection.left),
        ),
      );
      expect(document.snapshot.selection, isA<ComposerComponentSelection>());

      _applySelection(
        document,
        reducer.reduce(
          document.snapshot,
          const ComposerMoveIntent(ComposerMoveDirection.left),
        ),
      );
      expect(document.snapshot.selection, const ComposerCaretSelection(1));
    });

    test('uses identical traversal for block atoms', () {
      final document = _document(
        layout: ComposerComponentLayout.block,
        selection: const ComposerCaretSelection(1),
      );
      final selected = reducer.reduce(
        document.snapshot,
        const ComposerMoveIntent(ComposerMoveDirection.right),
      );

      expect(
        (selected as ComposerInteractionSelection).selection,
        isA<ComposerComponentSelection>(),
      );
    });

    test('Escape leaves a selected atom at its after boundary', () {
      final document = _document(
        layout: ComposerComponentLayout.inline,
        selection: const ComposerCaretSelection(1),
      );
      _applySelection(
        document,
        reducer.reduce(
          document.snapshot,
          const ComposerMoveIntent(ComposerMoveDirection.right),
        ),
      );

      final escaped = reducer.reduce(
        document.snapshot,
        const ComposerEscapeIntent(),
      );

      expect(
        (escaped as ComposerInteractionSelection).selection,
        const ComposerCaretSelection(7),
      );
    });
  });

  group('ComposerInteractionReducer deletion', () {
    for (final direction in ComposerDeleteDirection.values) {
      test('selected ${direction.name} removes the whole atom atomically', () {
        final document = _document(
          layout: ComposerComponentLayout.inline,
          selection: const ComposerCaretSelection(1),
        );
        _applySelection(
          document,
          reducer.reduce(
            document.snapshot,
            const ComposerMoveIntent(ComposerMoveDirection.right),
          ),
        );

        final decision = reducer.reduce(
          document.snapshot,
          ComposerDeleteIntent(direction),
        );
        final result = document.commit(
          (decision as ComposerInteractionTransaction).transaction,
        );

        expect(result, isA<ComposerCommitApplied>());
        expect(document.snapshot.source, 'ab');
        expect(document.snapshot.selection, const ComposerCaretSelection(1));
        expect(document.undo()?.source, 'a[date]b');
        expect(document.snapshot.selection, isA<ComposerComponentSelection>());
      });
    }

    test(
      'Backspace after and Delete before first select the adjacent atom',
      () {
        final after = _document(
          layout: ComposerComponentLayout.inline,
          selection: const ComposerCaretSelection(7),
        );
        final backward = reducer.reduce(
          after.snapshot,
          const ComposerDeleteIntent(ComposerDeleteDirection.backward),
        );
        expect(
          (backward as ComposerInteractionSelection).selection,
          isA<ComposerComponentSelection>(),
        );
        expect(after.snapshot.source, 'a[date]b');

        final before = _document(
          layout: ComposerComponentLayout.inline,
          selection: const ComposerCaretSelection(1),
        );
        final forward = reducer.reduce(
          before.snapshot,
          const ComposerDeleteIntent(ComposerDeleteDirection.forward),
        );
        expect(
          (forward as ComposerInteractionSelection).selection,
          isA<ComposerComponentSelection>(),
        );
        expect(before.snapshot.source, 'a[date]b');
      },
    );

    test('either delete key removes a snapped range across an atom', () {
      for (final direction in ComposerDeleteDirection.values) {
        final document = _document(
          layout: ComposerComponentLayout.inline,
          selection: const ComposerCaretSelection(0),
        );
        final selectionDecision = reducer.reduce(
          document.snapshot,
          const ComposerSelectIntent(anchor: 3, focus: 8),
        );
        _applySelection(document, selectionDecision);
        expect(
          document.snapshot.selection,
          ComposerRangeSelection(anchor: 1, focus: 8),
        );

        final deleteDecision = reducer.reduce(
          document.snapshot,
          ComposerDeleteIntent(direction),
        );
        document.commit(
          (deleteDecision as ComposerInteractionTransaction).transaction,
        );
        expect(document.snapshot.source, 'a');
      }
    });
  });

  test(
    'a collapsed surface hit inside an atom selects it, never raw source',
    () {
      final document = _document(
        layout: ComposerComponentLayout.inline,
        selection: const ComposerCaretSelection(0),
      );

      final decision = reducer.reduce(
        document.snapshot,
        const ComposerSelectIntent(anchor: 4, focus: 4),
      );

      expect(
        (decision as ComposerInteractionSelection).selection,
        isA<ComposerComponentSelection>(),
      );
    },
  );

  test('an exact component hit selects even a one-code-unit atom', () {
    final document = ComposerDocument(
      source: 'axb',
      definitions: [
        ComposerComponentDefinition<Object>(
          kind: ComposerComponentKind('single'),
          layout: ComposerComponentLayout.inline,
          precedence: 1,
          parse: (_) => const [
            ComposerComponentCandidate<Object>(
              range: ComposerSourceRange(1, 2),
              value: 'x',
            ),
          ],
        ),
      ],
      selection: const ComposerCaretSelection(1),
    );
    final token = document.snapshot.projection.components.single.token;

    final decision = reducer.reduce(
      document.snapshot,
      ComposerSelectComponentIntent(token),
    );

    expect(
      (decision as ComposerInteractionSelection).selection,
      ComposerComponentSelection(token),
    );
  });

  test('a component hit token cannot survive a source revision', () {
    final document = ComposerDocument(
      source: 'axb',
      definitions: [
        ComposerComponentDefinition<Object>(
          kind: ComposerComponentKind('single'),
          layout: ComposerComponentLayout.inline,
          precedence: 1,
          parse: (_) => const [
            ComposerComponentCandidate<Object>(
              range: ComposerSourceRange(1, 2),
              value: 'x',
            ),
          ],
        ),
      ],
    );
    final staleToken = document.snapshot.projection.components.single.token;
    document.commit(
      ComposerTransaction(
        baseRevision: document.snapshot.revision,
        edits: const [
          ComposerSourceEdit(
            range: ComposerSourceRange(2, 3),
            expectedSource: 'b',
            replacement: 'c',
          ),
        ],
        selectionAfter: const ComposerCaretSelection(2),
      ),
    );

    final decision = reducer.reduce(
      document.snapshot,
      ComposerSelectComponentIntent(staleToken),
    );

    expect(decision, isA<ComposerInteractionPassThrough>());
    expect(
      document.snapshot.projection.components.single.token.revision,
      const ComposerRevision(1),
    );
  });
}

ComposerDocument _document({
  required ComposerComponentLayout layout,
  required ComposerSelection selection,
}) {
  return ComposerDocument(
    source: 'a[date]b',
    definitions: [
      ComposerComponentDefinition<Object>(
        kind: ComposerComponentKind('date'),
        layout: layout,
        precedence: 1,
        parse: (_) => const [
          ComposerComponentCandidate<Object>(
            range: ComposerSourceRange(1, 7),
            value: 'date',
          ),
        ],
      ),
    ],
    selection: selection,
  );
}

void _applySelection(
  ComposerDocument document,
  ComposerInteractionDecision decision,
) {
  document.setSelection((decision as ComposerInteractionSelection).selection);
}
