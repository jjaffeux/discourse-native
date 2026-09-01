import 'package:discourse_native/src/shell/composer_document/component.dart';
import 'package:discourse_native/src/shell/composer_document/projection.dart';
import 'package:discourse_native/src/shell/composer_document/source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = ComposerProjectionResolver();
  const revision = ComposerRevision(7);

  group('ComposerProjectionResolver', () {
    test('captures exact source and builds a lossless segment partition', () {
      const source = 'a[date]b';
      final definition = ComposerComponentDefinition<_DateValue>(
        kind: ComposerComponentKind('date'),
        layout: ComposerComponentLayout.inline,
        precedence: 10,
        parse: (input) {
          expect(input.source, source);
          expect(input.revision, revision);
          return const [
            ComposerComponentCandidate(
              range: ComposerSourceRange(1, 7),
              value: _DateValue(42),
            ),
          ];
        },
      );

      final projection = resolver.resolve(
        input: const ComposerParseInput(source: source, revision: revision),
        definitions: [definition],
      );

      expect(projection.reconstructedSource, source);
      expect(projection.components, hasLength(1));
      expect(projection.components.single.source, '[date]');
      expect(projection.components.single.value, const _DateValue(42));
      expect(
        projection.components.single.layout,
        ComposerComponentLayout.inline,
      );
      expect(projection.segments.map((segment) => segment.source), [
        'a',
        '[date]',
        'b',
      ]);
      expect(projection.issues, isEmpty);
    });

    test('resolves exact conflicts by precedence then lexical kind', () {
      final low = _definition(kind: 'a-kind', precedence: 1, start: 0, end: 3);
      final high = _definition(kind: 'z-kind', precedence: 2, start: 0, end: 3);

      final byPrecedence = resolver.resolve(
        input: const ComposerParseInput(source: 'abc', revision: revision),
        definitions: [low, high],
      );
      expect(byPrecedence.components.single.kind.value, 'z-kind');
      expect(
        byPrecedence.issues.single.code,
        ComposerProjectionIssueCode.exactRangeConflict,
      );

      final lexicalWinner = resolver.resolve(
        input: const ComposerParseInput(source: 'abc', revision: revision),
        definitions: [
          _definition(kind: 'z-kind', precedence: 2, start: 0, end: 3),
          _definition(kind: 'a-kind', precedence: 2, start: 0, end: 3),
        ],
      );
      expect(lexicalWinner.components.single.kind.value, 'a-kind');
    });

    test('rejects and reports every participant in a partial overlap', () {
      final projection = resolver.resolve(
        input: const ComposerParseInput(source: 'abcdef', revision: revision),
        definitions: [
          _definition(kind: 'left', precedence: 10, start: 0, end: 4),
          _definition(kind: 'right', precedence: 20, start: 2, end: 6),
        ],
      );

      expect(projection.components, isEmpty);
      expect(projection.reconstructedSource, 'abcdef');
      expect(
        projection.issues.map((issue) => issue.code),
        everyElement(ComposerProjectionIssueCode.partialOverlap),
      );
      expect(projection.issues, hasLength(2));
    });

    test('keeps an outer atom and explicitly reports contained candidates', () {
      final projection = resolver.resolve(
        input: const ComposerParseInput(source: 'abcdef', revision: revision),
        definitions: [
          _definition(kind: 'inner', precedence: 100, start: 2, end: 4),
          _definition(kind: 'outer', precedence: 1, start: 0, end: 6),
        ],
      );

      expect(projection.components.single.kind.value, 'outer');
      expect(
        projection.issues.single.code,
        ComposerProjectionIssueCode.containedCandidate,
      );
      expect(projection.issues.single.kind.value, 'inner');
    });

    test('reports invalid candidates without losing source bookkeeping', () {
      final projection = resolver.resolve(
        input: const ComposerParseInput(source: 'abc', revision: revision),
        definitions: [
          _definition(kind: 'empty', precedence: 1, start: 1, end: 1),
          _definition(kind: 'outside', precedence: 1, start: -1, end: 2),
        ],
      );

      expect(projection.components, isEmpty);
      expect(projection.reconstructedSource, 'abc');
      expect(projection.issues, hasLength(2));
      expect(
        projection.issues.map((issue) => issue.code),
        everyElement(ComposerProjectionIssueCode.invalidRange),
      );
    });
  });
}

ComposerComponentDefinition<Object> _definition({
  required String kind,
  required int precedence,
  required int start,
  required int end,
}) {
  return ComposerComponentDefinition<Object>(
    kind: ComposerComponentKind(kind),
    layout: ComposerComponentLayout.block,
    precedence: precedence,
    parse: (_) => [
      ComposerComponentCandidate<Object>(
        range: ComposerSourceRange(start, end),
        value: kind,
      ),
    ],
  );
}

final class _DateValue {
  const _DateValue(this.epoch);

  final int epoch;

  @override
  bool operator ==(Object other) {
    return other is _DateValue && other.epoch == epoch;
  }

  @override
  int get hashCode => epoch.hashCode;
}
