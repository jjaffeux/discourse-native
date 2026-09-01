import 'package:discourse_native/src/shell/composer_document/component.dart';
import 'package:discourse_native/src/shell/composer_document/document.dart';
import 'package:discourse_native/src/shell/composer_document/selection.dart';
import 'package:discourse_native/src/shell/composer_document/source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposerDocument transactions', () {
    test('validates every edit before committing any of them', () {
      final document = _plainDocument('abcdef');
      final result = document.commit(
        ComposerTransaction(
          baseRevision: document.snapshot.revision,
          edits: const [
            ComposerSourceEdit(
              range: ComposerSourceRange(0, 1),
              expectedSource: 'a',
              replacement: 'A',
            ),
            ComposerSourceEdit(
              range: ComposerSourceRange(4, 6),
              expectedSource: 'wrong',
              replacement: 'EF',
            ),
          ],
          selectionAfter: const ComposerCaretSelection(6),
        ),
      );

      expect(result, isA<ComposerCommitRejected>());
      expect(
        (result as ComposerCommitRejected).failure.code,
        ComposerTransactionFailureCode.sourceMismatch,
      );
      expect(document.snapshot.source, 'abcdef');
      expect(document.snapshot.revision, const ComposerRevision(0));
      expect(document.canUndo, isFalse);
    });

    test('applies disjoint verified edits as one revision', () {
      final document = _plainDocument('abcdef');
      final result = document.commit(
        ComposerTransaction(
          baseRevision: document.snapshot.revision,
          edits: const [
            ComposerSourceEdit(
              range: ComposerSourceRange(0, 1),
              expectedSource: 'a',
              replacement: 'A',
            ),
            ComposerSourceEdit(
              range: ComposerSourceRange(4, 6),
              expectedSource: 'ef',
              replacement: 'EF!',
            ),
          ],
          selectionAfter: const ComposerCaretSelection(7),
        ),
      );

      expect(result, isA<ComposerCommitApplied>());
      expect(document.snapshot.source, 'AbcdEF!');
      expect(document.snapshot.revision, const ComposerRevision(1));
      expect(document.snapshot.selection, const ComposerCaretSelection(7));
    });

    test('rejects stale revisions and overlapping ranges', () {
      final document = _plainDocument('abcdef');
      final stale = ComposerTransaction(
        baseRevision: const ComposerRevision(1),
        edits: const [
          ComposerSourceEdit(
            range: ComposerSourceRange(0, 1),
            expectedSource: 'a',
            replacement: 'A',
          ),
        ],
        selectionAfter: const ComposerCaretSelection(1),
      );
      expect(
        (document.commit(stale) as ComposerCommitRejected).failure.code,
        ComposerTransactionFailureCode.staleRevision,
      );

      final overlapping = ComposerTransaction(
        baseRevision: document.snapshot.revision,
        edits: const [
          ComposerSourceEdit(
            range: ComposerSourceRange(0, 3),
            expectedSource: 'abc',
            replacement: '',
          ),
          ComposerSourceEdit(
            range: ComposerSourceRange(2, 4),
            expectedSource: 'cd',
            replacement: '',
          ),
        ],
        selectionAfter: const ComposerCaretSelection(0),
      );
      expect(
        (document.commit(overlapping) as ComposerCommitRejected).failure.code,
        ComposerTransactionFailureCode.overlappingEdits,
      );
      expect(document.snapshot.source, 'abcdef');
    });

    test(
      'undo and redo restore source plus selection with fresh revisions',
      () {
        final document = _plainDocument(
          'abc',
          selection: const ComposerCaretSelection(1),
        );
        document.commit(
          ComposerTransaction(
            baseRevision: document.snapshot.revision,
            edits: const [
              ComposerSourceEdit(
                range: ComposerSourceRange(1, 2),
                expectedSource: 'b',
                replacement: 'B',
              ),
            ],
            selectionAfter: const ComposerCaretSelection(2),
          ),
        );

        final undone = document.undo();
        expect(undone?.source, 'abc');
        expect(undone?.selection, const ComposerCaretSelection(1));
        expect(undone?.revision, const ComposerRevision(2));

        final redone = document.redo();
        expect(redone?.source, 'aBc');
        expect(redone?.selection, const ComposerCaretSelection(2));
        expect(redone?.revision, const ComposerRevision(3));
      },
    );

    test('normalizes post-commit carets away from component interiors', () {
      final document = ComposerDocument(
        source: 'ab',
        definitions: [_bracketDefinition()],
      );
      document.commit(
        ComposerTransaction(
          baseRevision: document.snapshot.revision,
          edits: const [
            ComposerSourceEdit(
              range: ComposerSourceRange(1, 1),
              expectedSource: '',
              replacement: '[x]',
            ),
          ],
          selectionAfter: const ComposerCaretSelection(2),
        ),
      );

      expect(document.snapshot.source, 'a[x]b');
      expect(document.snapshot.selection, const ComposerCaretSelection(1));
    });
  });
}

ComposerDocument _plainDocument(String source, {ComposerSelection? selection}) {
  return ComposerDocument(
    source: source,
    definitions: const <ComposerComponentDefinition<Object>>[],
    selection: selection,
  );
}

ComposerComponentDefinition<Object> _bracketDefinition() {
  return ComposerComponentDefinition<Object>(
    kind: ComposerComponentKind('bracket'),
    layout: ComposerComponentLayout.inline,
    precedence: 1,
    parse: (input) sync* {
      final start = input.source.indexOf('[x]');
      if (start >= 0) {
        yield ComposerComponentCandidate<Object>(
          range: ComposerSourceRange(start, start + 3),
          value: 'x',
        );
      }
    },
  );
}
