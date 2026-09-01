import 'package:discourse_native/src/shell/composer_document/component.dart';
import 'package:discourse_native/src/shell/composer_document/document.dart';
import 'package:discourse_native/src/shell/composer_document/selection.dart';
import 'package:discourse_native/src/shell/composer_document/source.dart';
import 'package:discourse_native/src/shell/composer_surface/edit_translation.dart';
import 'package:discourse_native/src/shell/composer_surface/projection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _translator = ComposerSurfaceEditTranslator();
final _inlineKind = ComposerComponentKind('test.inline');
final _secondInlineKind = ComposerComponentKind('test.second-inline');
final _blockKind = ComposerComponentKind('test.block');

void main() {
  group('ordinary text around atoms', () {
    for (final atomLayout in _TestAtomLayout.values) {
      for (final side in _TestAtomSide.values) {
        for (final operation in _TestOperation.values) {
          test(
            '${operation.name} ${side.name} the ${atomLayout.name} atom',
            () {
              final fixture = _Fixture.standard();
              final originalSource = fixture.source;
              final atom = fixture.atom(atomLayout);
              final edit = _editAt(atom, side: side, operation: operation);
              final sourceRange = fixture.plan.sourceRangeForSurfaceRange(
                edit.oldRange,
              );
              final oldValue = TextEditingValue(
                text: fixture.projectedText,
                selection: TextSelection.collapsed(offset: edit.oldRange.start),
              );
              final newText = fixture.projectedText.replaceRange(
                edit.oldRange.start,
                edit.oldRange.end,
                edit.replacement,
              );
              final newValue = TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(
                  offset: edit.oldRange.start + edit.replacement.length,
                ),
              );

              final result = _translator.translate(
                snapshot: fixture.document.snapshot,
                plan: fixture.plan,
                oldValue: oldValue,
                newValue: newValue,
              );

              expect(result, isA<ComposerSurfaceTextEditTranslation>());
              final translated = result as ComposerSurfaceTextEditTranslation;
              expect(translated.changedSurfaceRange, edit.oldRange);
              expect(translated.replacement, edit.replacement);
              expect(translated.transaction.baseRevision, fixture.revision);
              expect(translated.transaction.edits, hasLength(1));
              final sourceEdit = translated.transaction.edits.single;
              expect(sourceEdit.range, sourceRange);
              expect(
                sourceEdit.expectedSource,
                sourceRange.capture(originalSource),
              );
              expect(sourceEdit.replacement, edit.replacement);
              expect(
                translated.transaction.selectionAfter,
                ComposerCaretSelection(
                  sourceRange.start + edit.replacement.length,
                ),
              );

              final commit = fixture.document.commit(translated.transaction);
              expect(commit, isA<ComposerCommitApplied>());
              expect(
                fixture.document.snapshot.source,
                originalSource.replaceRange(
                  sourceRange.start,
                  sourceRange.end,
                  edit.replacement,
                ),
              );
            },
          );
        }
      }
    }
  });

  test('maps a final directional selection through the edit and atom', () {
    final fixture = _Fixture.standard();
    final atom = fixture.atom(_TestAtomLayout.inline);
    final oldValue = TextEditingValue(
      text: fixture.projectedText,
      selection: TextSelection.collapsed(offset: atom.surfaceBefore),
    );
    final newText = fixture.projectedText.replaceRange(
      atom.surfaceBefore,
      atom.surfaceBefore,
      'Z',
    );
    final newValue = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: atom.surfaceAfter + 1,
        extentOffset: 1,
        isDirectional: true,
      ),
    );

    final result = _translator.translate(
      snapshot: fixture.document.snapshot,
      plan: fixture.plan,
      oldValue: oldValue,
      newValue: newValue,
    );

    final transaction =
        (result as ComposerSurfaceTextEditTranslation).transaction;
    expect(
      transaction.selectionAfter,
      ComposerRangeSelection(anchor: atom.sourceAfter + 1, focus: 1),
    );
  });

  test('returns a selection translation without creating a transaction', () {
    final fixture = _Fixture.standard();
    final atom = fixture.atom(_TestAtomLayout.block);
    final oldValue = TextEditingValue(
      text: fixture.projectedText,
      selection: TextSelection.collapsed(offset: atom.surfaceBefore),
    );
    final newValue = oldValue.copyWith(
      selection: TextSelection(
        baseOffset: atom.surfaceAfter,
        extentOffset: atom.surfaceBefore,
        isDirectional: true,
      ),
    );

    final result = _translator.translate(
      snapshot: fixture.document.snapshot,
      plan: fixture.plan,
      oldValue: oldValue,
      newValue: newValue,
    );

    expect(result, isA<ComposerSurfaceSelectionTranslation>());
    final selection = result as ComposerSurfaceSelectionTranslation;
    expect(selection.before, ComposerCaretSelection(atom.sourceBefore));
    expect(
      selection.after,
      ComposerRangeSelection(
        anchor: atom.sourceAfter,
        focus: atom.sourceBefore,
      ),
    );
    expect(selection.changed, isTrue);
  });

  test('translated transactions are rejected after the document advances', () {
    final fixture = _Fixture.standard();
    final oldValue = TextEditingValue(
      text: fixture.projectedText,
      selection: const TextSelection.collapsed(offset: 1),
    );
    final translated =
        _translator.translate(
              snapshot: fixture.document.snapshot,
              plan: fixture.plan,
              oldValue: oldValue,
              newValue: oldValue.copyWith(
                text: fixture.projectedText.replaceRange(1, 1, 'Z'),
                selection: const TextSelection.collapsed(offset: 2),
              ),
            )
            as ComposerSurfaceTextEditTranslation;
    final independentCommit = fixture.document.commit(
      ComposerTransaction(
        baseRevision: fixture.revision,
        edits: const [
          ComposerSourceEdit(
            range: ComposerSourceRange(0, 1),
            expectedSource: 'L',
            replacement: 'Q',
          ),
        ],
        selectionAfter: const ComposerCaretSelection(1),
      ),
    );
    expect(independentCommit, isA<ComposerCommitApplied>());

    final staleCommit = fixture.document.commit(translated.transaction);

    expect(staleCommit, isA<ComposerCommitRejected>());
    expect(
      (staleCommit as ComposerCommitRejected).failure.code,
      ComposerTransactionFailureCode.staleRevision,
    );
  });

  test('rejects native deletion of an atom for the semantic reducer', () {
    final fixture = _Fixture.standard();
    final atom = fixture.atom(_TestAtomLayout.inline);
    final oldValue = TextEditingValue(
      text: fixture.projectedText,
      selection: TextSelection.collapsed(offset: atom.surfaceAfter),
    );
    final newValue = TextEditingValue(
      text: fixture.projectedText.replaceRange(
        atom.surfaceBefore,
        atom.surfaceAfter,
        '',
      ),
      selection: TextSelection.collapsed(offset: atom.surfaceBefore),
    );

    expect(
      _rejectionReason(fixture, oldValue, newValue),
      ComposerSurfaceEditRejectionReason.changedRangeIntersectsAtom,
    );
  });

  group('adjacent atom deletion', () {
    const cases = [
      _AdjacentDeletionCase(
        name: 'forward-delete before the first atom',
        oldSelection: TextSelection.collapsed(offset: 1),
        newSelection: TextSelection.collapsed(offset: 1),
        intendedRange: ComposerSurfaceRange(1, 2),
      ),
      _AdjacentDeletionCase(
        name: 'backspace between atoms',
        oldSelection: TextSelection.collapsed(offset: 2),
        newSelection: TextSelection.collapsed(offset: 1),
        intendedRange: ComposerSurfaceRange(1, 2),
      ),
      _AdjacentDeletionCase(
        name: 'forward-delete between atoms',
        oldSelection: TextSelection.collapsed(offset: 2),
        newSelection: TextSelection.collapsed(offset: 2),
        intendedRange: ComposerSurfaceRange(2, 3),
      ),
      _AdjacentDeletionCase(
        name: 'backspace after the second atom',
        oldSelection: TextSelection.collapsed(offset: 3),
        newSelection: TextSelection.collapsed(offset: 2),
        intendedRange: ComposerSurfaceRange(2, 3),
      ),
      _AdjacentDeletionCase(
        name: 'explicit selection of both adjacent atoms',
        oldSelection: TextSelection(
          baseOffset: 3,
          extentOffset: 1,
          isDirectional: true,
        ),
        newSelection: TextSelection.collapsed(offset: 1),
        intendedRange: ComposerSurfaceRange(1, 3),
      ),
    ];

    for (final deletionCase in cases) {
      test('${deletionCase.name} retains the intended range', () {
        final fixture = _Fixture.adjacentInlineAtoms();
        expect(fixture.plan.atoms.map((atom) => atom.component.kind), [
          _inlineKind,
          _secondInlineKind,
        ]);
        final oldValue = TextEditingValue(
          text: fixture.projectedText,
          selection: deletionCase.oldSelection,
        );
        final newValue = TextEditingValue(
          text: fixture.projectedText.replaceRange(
            deletionCase.intendedRange.start,
            deletionCase.intendedRange.end,
            '',
          ),
          selection: deletionCase.newSelection,
        );

        final result = _translator.translate(
          snapshot: fixture.document.snapshot,
          plan: fixture.plan,
          oldValue: oldValue,
          newValue: newValue,
        );

        expect(result, isA<ComposerSurfaceEditRejected>());
        final rejected = result as ComposerSurfaceEditRejected;
        expect(
          rejected.reason,
          ComposerSurfaceEditRejectionReason.changedRangeIntersectsAtom,
        );
        expect(rejected.changedSurfaceRange, deletionCase.intendedRange);
      });
    }
  });

  group('explicit atom replacement', () {
    const cases = [
      _SelectedReplacementCase(
        name: 'replaces the first of two adjacent atoms',
        selectedRange: ComposerSurfaceRange(1, 2),
        replacement: 'first',
      ),
      _SelectedReplacementCase(
        name: 'replaces the second of two adjacent atoms',
        selectedRange: ComposerSurfaceRange(2, 3),
        replacement: 'second',
      ),
    ];

    for (final replacementCase in cases) {
      test(replacementCase.name, () {
        final fixture = _Fixture.adjacentInlineAtoms();
        final originalSource = fixture.source;
        final sourceRange = fixture.plan.sourceRangeForSurfaceRange(
          replacementCase.selectedRange,
        );
        final oldValue = TextEditingValue(
          text: fixture.projectedText,
          selection: TextSelection(
            baseOffset: replacementCase.selectedRange.start,
            extentOffset: replacementCase.selectedRange.end,
            isDirectional: true,
          ),
        );
        final newValue = TextEditingValue(
          text: fixture.projectedText.replaceRange(
            replacementCase.selectedRange.start,
            replacementCase.selectedRange.end,
            replacementCase.replacement,
          ),
          selection: TextSelection.collapsed(
            offset:
                replacementCase.selectedRange.start +
                replacementCase.replacement.length,
          ),
        );

        final result = _translator.translate(
          snapshot: fixture.document.snapshot,
          plan: fixture.plan,
          oldValue: oldValue,
          newValue: newValue,
        );

        expect(result, isA<ComposerSurfaceTextEditTranslation>());
        final translated = result as ComposerSurfaceTextEditTranslation;
        expect(translated.changedSurfaceRange, replacementCase.selectedRange);
        expect(translated.transaction.edits.single.range, sourceRange);
        expect(
          translated.transaction.edits.single.expectedSource,
          sourceRange.capture(originalSource),
        );
        expect(
          translated.transaction.selectionAfter,
          ComposerCaretSelection(
            sourceRange.start + replacementCase.replacement.length,
          ),
        );

        final commit = fixture.document.commit(translated.transaction);
        expect(commit, isA<ComposerCommitApplied>());
        expect(
          fixture.document.snapshot.source,
          originalSource.replaceRange(
            sourceRange.start,
            sourceRange.end,
            replacementCase.replacement,
          ),
        );
      });
    }
  });

  test(
    'replaces a selected range spanning text and inline and block atoms',
    () {
      final fixture = _Fixture.standard();
      final originalSource = fixture.source;
      final inlineAtom = fixture.atom(_TestAtomLayout.inline);
      final blockAtom = fixture.atom(_TestAtomLayout.block);
      final selectedRange = ComposerSurfaceRange(
        inlineAtom.surfaceBefore - 1,
        blockAtom.surfaceAfter + 1,
      );
      final sourceRange = fixture.plan.sourceRangeForSurfaceRange(
        selectedRange,
      );
      const replacement = 'xq';
      final oldValue = TextEditingValue(
        text: fixture.projectedText,
        selection: TextSelection(
          baseOffset: selectedRange.end,
          extentOffset: selectedRange.start,
          isDirectional: true,
        ),
      );
      final newValue = TextEditingValue(
        text: fixture.projectedText.replaceRange(
          selectedRange.start,
          selectedRange.end,
          replacement,
        ),
        selection: TextSelection.collapsed(
          offset: selectedRange.start + replacement.length,
        ),
      );

      final result = _translator.translate(
        snapshot: fixture.document.snapshot,
        plan: fixture.plan,
        oldValue: oldValue,
        newValue: newValue,
      );

      expect(result, isA<ComposerSurfaceTextEditTranslation>());
      final translated = result as ComposerSurfaceTextEditTranslation;
      expect(translated.changedSurfaceRange, selectedRange);
      expect(translated.replacement, replacement);
      expect(translated.transaction.edits.single.range, sourceRange);
      expect(
        translated.transaction.edits.single.expectedSource,
        sourceRange.capture(originalSource),
      );
      expect(
        translated.transaction.selectionAfter,
        ComposerCaretSelection(sourceRange.start + replacement.length),
      );
      final commit = fixture.document.commit(translated.transaction);
      expect(commit, isA<ComposerCommitApplied>());
      expect(
        fixture.document.snapshot.source,
        originalSource.replaceRange(
          sourceRange.start,
          sourceRange.end,
          replacement,
        ),
      );
    },
  );

  test('rejects collapsed replacement of an atom', () {
    final fixture = _Fixture.adjacentInlineAtoms();
    final oldValue = TextEditingValue(
      text: fixture.projectedText,
      selection: const TextSelection.collapsed(offset: 1),
    );
    final newValue = TextEditingValue(
      text: fixture.projectedText.replaceRange(1, 2, 'x'),
      selection: const TextSelection.collapsed(offset: 2),
    );

    final result =
        _translator.translate(
              snapshot: fixture.document.snapshot,
              plan: fixture.plan,
              oldValue: oldValue,
              newValue: newValue,
            )
            as ComposerSurfaceEditRejected;

    expect(
      result.reason,
      ComposerSurfaceEditRejectionReason.changedRangeIntersectsAtom,
    );
    expect(result.changedSurfaceRange, const ComposerSurfaceRange(1, 2));
  });

  test('rejects atom replacement not covered by the old selection', () {
    final fixture = _Fixture.adjacentInlineAtoms();
    final oldValue = TextEditingValue(
      text: fixture.projectedText,
      selection: const TextSelection(
        baseOffset: 0,
        extentOffset: 1,
        isDirectional: true,
      ),
    );
    final newValue = TextEditingValue(
      text: fixture.projectedText.replaceRange(1, 2, 'x'),
      selection: const TextSelection.collapsed(offset: 2),
    );

    final result =
        _translator.translate(
              snapshot: fixture.document.snapshot,
              plan: fixture.plan,
              oldValue: oldValue,
              newValue: newValue,
            )
            as ComposerSurfaceEditRejected;

    expect(
      result.reason,
      ComposerSurfaceEditRejectionReason.changedRangeIntersectsAtom,
    );
    expect(result.changedSurfaceRange, const ComposerSurfaceRange(1, 2));
  });

  test('rejects a replacement that introduces an object character', () {
    final fixture = _Fixture.standard();
    final oldValue = TextEditingValue(
      text: fixture.projectedText,
      selection: const TextSelection.collapsed(offset: 1),
    );
    final newValue = TextEditingValue(
      text: fixture.projectedText.replaceRange(
        1,
        1,
        composerSurfaceObjectReplacementCharacter,
      ),
      selection: const TextSelection.collapsed(offset: 2),
    );

    expect(
      _rejectionReason(fixture, oldValue, newValue),
      ComposerSurfaceEditRejectionReason
          .replacementContainsObjectReplacementCharacter,
    );
  });

  test('rejects active composition in ordinary text while IME is gated', () {
    final fixture = _Fixture.standard();
    final oldValue = TextEditingValue(
      text: fixture.projectedText,
      selection: const TextSelection.collapsed(offset: 1),
    );
    final newValue = TextEditingValue(
      text: fixture.projectedText.replaceRange(1, 1, 'z'),
      selection: const TextSelection.collapsed(offset: 2),
      composing: const TextRange(start: 1, end: 2),
    );

    expect(
      _rejectionReason(fixture, oldValue, newValue),
      ComposerSurfaceEditRejectionReason.activeComposition,
    );
  });

  test('reports composition that touches an atom separately', () {
    final fixture = _Fixture.standard();
    final atom = fixture.atom(_TestAtomLayout.block);
    final oldValue = TextEditingValue(
      text: fixture.projectedText,
      selection: TextSelection.collapsed(offset: atom.surfaceBefore),
    );
    final newValue = TextEditingValue(
      text: fixture.projectedText,
      selection: TextSelection.collapsed(offset: atom.surfaceAfter),
      composing: TextRange(start: atom.surfaceBefore, end: atom.surfaceAfter),
    );

    expect(
      _rejectionReason(fixture, oldValue, newValue),
      ComposerSurfaceEditRejectionReason.compositionTouchesAtom,
    );
  });

  test('rejects a projected base buffer that does not match its plan', () {
    final fixture = _Fixture.standard();
    const oldValue = TextEditingValue(
      text: 'different',
      selection: TextSelection.collapsed(offset: 0),
    );

    expect(
      _rejectionReason(fixture, oldValue, oldValue),
      ComposerSurfaceEditRejectionReason.projectedBaseTextMismatch,
    );
  });

  test('rejects invalid native selections and composing ranges', () {
    final fixture = _Fixture.standard();
    final valid = TextEditingValue(
      text: fixture.projectedText,
      selection: const TextSelection.collapsed(offset: 0),
    );
    final invalidOldSelection = valid.copyWith(
      selection: TextSelection.collapsed(
        offset: fixture.projectedText.length + 1,
      ),
    );
    expect(
      _rejectionReason(fixture, invalidOldSelection, valid),
      ComposerSurfaceEditRejectionReason.invalidOldSelection,
    );

    final invalidNewSelection = valid.copyWith(
      selection: TextSelection.collapsed(
        offset: fixture.projectedText.length + 1,
      ),
    );
    expect(
      _rejectionReason(fixture, valid, invalidNewSelection),
      ComposerSurfaceEditRejectionReason.invalidNewSelection,
    );

    final invalidComposing = valid.copyWith(
      composing: TextRange(start: 0, end: fixture.projectedText.length + 1),
    );
    expect(
      _rejectionReason(fixture, valid, invalidComposing),
      ComposerSurfaceEditRejectionReason.invalidNewComposingRange,
    );
  });

  test('uses UTF-16 offsets around surrogate pairs', () {
    final fixture = _Fixture.fromSource('😀a<I>b💡');
    expect('😀'.length, 2);
    final oldValue = TextEditingValue(
      text: fixture.projectedText,
      selection: const TextSelection.collapsed(offset: 2),
    );
    final newValue = oldValue.copyWith(
      text: fixture.projectedText.replaceRange(2, 2, 'Z'),
      selection: const TextSelection.collapsed(offset: 3),
    );

    final result = _translator.translate(
      snapshot: fixture.document.snapshot,
      plan: fixture.plan,
      oldValue: oldValue,
      newValue: newValue,
    );

    final transaction =
        (result as ComposerSurfaceTextEditTranslation).transaction;
    expect(transaction.edits.single.range, const ComposerSourceRange(2, 2));
    expect(transaction.selectionAfter, const ComposerCaretSelection(3));
    final commit = fixture.document.commit(transaction);
    expect(commit, isA<ComposerCommitApplied>());
    expect(fixture.document.snapshot.source, '😀Za<I>b💡');
  });

  test('infers a UTF-16 backspace range for a surrogate pair', () {
    final fixture = _Fixture.fromSource('😀a<I>b');
    final oldValue = TextEditingValue(
      text: fixture.projectedText,
      selection: const TextSelection.collapsed(offset: 2),
    );
    final newValue = TextEditingValue(
      text: fixture.projectedText.replaceRange(0, 2, ''),
      selection: const TextSelection.collapsed(offset: 0),
    );

    final result = _translator.translate(
      snapshot: fixture.document.snapshot,
      plan: fixture.plan,
      oldValue: oldValue,
      newValue: newValue,
    );

    final translated = result as ComposerSurfaceTextEditTranslation;
    expect(translated.changedSurfaceRange, const ComposerSurfaceRange(0, 2));
    expect(
      translated.transaction.edits.single.range,
      const ComposerSourceRange(0, 2),
    );
    expect(
      translated.transaction.selectionAfter,
      const ComposerCaretSelection(0),
    );
    final commit = fixture.document.commit(translated.transaction);
    expect(commit, isA<ComposerCommitApplied>());
    expect(fixture.document.snapshot.source, 'a<I>b');
  });
}

enum _TestAtomLayout { inline, block }

enum _TestAtomSide { before, after }

enum _TestOperation { insert, delete, replace }

final class _Fixture {
  _Fixture.fromSource(String source)
    : document = ComposerDocument(
        source: source,
        definitions: [
          _inlineDefinition,
          _secondInlineDefinition,
          _blockDefinition,
        ],
      ) {
    plan = ComposerSurfaceProjectionPlan.fromProjection(
      document.snapshot.projection,
    );
  }

  factory _Fixture.standard() {
    return _Fixture.fromSource('Lx<I>yM\np<B>\nrow\n</B>q\nR');
  }

  factory _Fixture.adjacentInlineAtoms() {
    return _Fixture.fromSource('a<I><J>b');
  }

  final ComposerDocument document;
  late final ComposerSurfaceProjectionPlan plan;

  String get source => document.snapshot.source;
  String get projectedText => plan.snapshot.projectedText;
  ComposerRevision get revision => document.snapshot.revision;

  ComposerSurfaceAtomMapping atom(_TestAtomLayout layout) {
    return plan.atoms.singleWhere((atom) {
      return switch (layout) {
        _TestAtomLayout.inline =>
          atom.component.layout == ComposerComponentLayout.inline,
        _TestAtomLayout.block =>
          atom.component.layout == ComposerComponentLayout.block,
      };
    });
  }
}

final _inlineDefinition = ComposerComponentDefinition<Object>(
  kind: _inlineKind,
  layout: ComposerComponentLayout.inline,
  precedence: 0,
  parse: (input) => RegExp(r'<I>').allMatches(input.source).map((match) {
    return ComposerComponentCandidate<Object>(
      range: ComposerSourceRange(match.start, match.end),
      value: 'inline',
    );
  }),
);

final _secondInlineDefinition = ComposerComponentDefinition<Object>(
  kind: _secondInlineKind,
  layout: ComposerComponentLayout.inline,
  precedence: 0,
  parse: (input) => RegExp(r'<J>').allMatches(input.source).map((match) {
    return ComposerComponentCandidate<Object>(
      range: ComposerSourceRange(match.start, match.end),
      value: 'second inline',
    );
  }),
);

final _blockDefinition = ComposerComponentDefinition<Object>(
  kind: _blockKind,
  layout: ComposerComponentLayout.block,
  precedence: 0,
  parse: (input) =>
      RegExp(r'<B>[\s\S]*?</B>').allMatches(input.source).map((match) {
        return ComposerComponentCandidate<Object>(
          range: ComposerSourceRange(match.start, match.end),
          value: 'block',
        );
      }),
);

final class _RequestedEdit {
  const _RequestedEdit({required this.oldRange, required this.replacement});

  final ComposerSurfaceRange oldRange;
  final String replacement;
}

final class _AdjacentDeletionCase {
  const _AdjacentDeletionCase({
    required this.name,
    required this.oldSelection,
    required this.newSelection,
    required this.intendedRange,
  });

  final String name;
  final TextSelection oldSelection;
  final TextSelection newSelection;
  final ComposerSurfaceRange intendedRange;
}

final class _SelectedReplacementCase {
  const _SelectedReplacementCase({
    required this.name,
    required this.selectedRange,
    required this.replacement,
  });

  final String name;
  final ComposerSurfaceRange selectedRange;
  final String replacement;
}

_RequestedEdit _editAt(
  ComposerSurfaceAtomMapping atom, {
  required _TestAtomSide side,
  required _TestOperation operation,
}) {
  final boundary = switch (side) {
    _TestAtomSide.before => atom.surfaceBefore,
    _TestAtomSide.after => atom.surfaceAfter,
  };
  final adjacentRange = switch (side) {
    _TestAtomSide.before => ComposerSurfaceRange(boundary - 1, boundary),
    _TestAtomSide.after => ComposerSurfaceRange(boundary, boundary + 1),
  };
  return switch (operation) {
    _TestOperation.insert => _RequestedEdit(
      oldRange: ComposerSurfaceRange(boundary, boundary),
      replacement: 'Z',
    ),
    _TestOperation.delete => _RequestedEdit(
      oldRange: adjacentRange,
      replacement: '',
    ),
    _TestOperation.replace => _RequestedEdit(
      oldRange: adjacentRange,
      replacement: 'Z',
    ),
  };
}

ComposerSurfaceEditRejectionReason _rejectionReason(
  _Fixture fixture,
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  final result = _translator.translate(
    snapshot: fixture.document.snapshot,
    plan: fixture.plan,
    oldValue: oldValue,
    newValue: newValue,
  );
  expect(result, isA<ComposerSurfaceEditRejected>());
  return (result as ComposerSurfaceEditRejected).reason;
}
