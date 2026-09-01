import 'package:discourse_native/src/shell/composer_document/component.dart';
import 'package:discourse_native/src/shell/composer_document/projection.dart';
import 'package:discourse_native/src/shell/composer_document/selection.dart';
import 'package:discourse_native/src/shell/composer_document/source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const normalizer = ComposerSelectionNormalizer();
  late ComposerProjection projection;

  setUp(() {
    projection = const ComposerProjectionResolver().resolve(
      input: const ComposerParseInput(
        source: 'a[date]bc[poll]d',
        revision: ComposerRevision(0),
      ),
      definitions: [_definition('date', 1, 7), _definition('poll', 9, 15)],
    );
  });

  test('never leaves a collapsed caret inside an accepted component', () {
    expect(
      normalizer.normalize(const ComposerCaretSelection(3), projection),
      const ComposerCaretSelection(1),
    );
    expect(
      normalizer.normalize(
        const ComposerCaretSelection(3),
        projection,
        bias: ComposerSelectionBias.forward,
      ),
      const ComposerCaretSelection(7),
    );
  });

  test('snaps a forward range to every intersected atom boundary', () {
    final normalized = normalizer.normalize(
      ComposerRangeSelection(anchor: 3, focus: 12),
      projection,
    );

    expect(normalized, ComposerRangeSelection(anchor: 1, focus: 15));
  });

  test('preserves direction while snapping a dragged reverse range', () {
    final normalized = normalizer.normalize(
      ComposerRangeSelection(anchor: 12, focus: 3),
      projection,
    );

    expect(normalized, ComposerRangeSelection(anchor: 15, focus: 1));
  });

  test('invalid component selections degrade to a legal caret', () {
    final normalized = normalizer.normalize(
      ComposerComponentSelection(
        ComposerComponentToken(
          revision: const ComposerRevision(0),
          kind: ComposerComponentKind('gone'),
          range: const ComposerSourceRange(2, 4),
          source: 'da',
        ),
      ),
      projection,
    );

    expect(normalized, const ComposerCaretSelection(1));
  });
}

ComposerComponentDefinition<Object> _definition(
  String kind,
  int start,
  int end,
) {
  return ComposerComponentDefinition<Object>(
    kind: ComposerComponentKind(kind),
    layout: ComposerComponentLayout.inline,
    precedence: 0,
    parse: (_) => [
      ComposerComponentCandidate<Object>(
        range: ComposerSourceRange(start, end),
        value: kind,
      ),
    ],
  );
}
