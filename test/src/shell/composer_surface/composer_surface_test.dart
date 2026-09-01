import 'package:discourse_native/src/shell/composer_document/component.dart';
import 'package:discourse_native/src/shell/composer_document/projection.dart';
import 'package:discourse_native/src/shell/composer_document/source.dart';
import 'package:discourse_native/src/shell/composer_surface/composer_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _dateKind = ComposerComponentKind('core.date');
final _gridKind = ComposerComponentKind('core.grid');
final _oneCodeUnitKind = ComposerComponentKind('test.one-code-unit');

void main() {
  testWidgets('raw component source never enters the projected surface', (
    tester,
  ) async {
    const rawComponent = '{{date:2026-09-01}}';
    const source = 'Before $rawComponent after';
    final controller = ComposerSurfaceController();

    await tester.pumpWidget(
      _surfaceHost(
        projection: _resolve(source, includeDate: true),
        controller: controller,
      ),
    );
    await tester.pump();

    final snapshot = controller.snapshot!;
    expect(snapshot.projectedText, 'Before \uFFFC after');
    expect(snapshot.projectedText, isNot(contains(rawComponent)));

    final renderedText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join();
    expect(renderedText, isNot(contains(rawComponent)));
    expect(find.text('September 1'), findsOneWidget);
  });

  testWidgets('one inline component occupies one logical surface position', (
    tester,
  ) async {
    const rawComponent = '{{date:2026-09-01}}';
    const prefix = 'Before ';
    const suffix = ' after';
    const source = '$prefix$rawComponent$suffix';
    final controller = ComposerSurfaceController();

    await tester.pumpWidget(
      _surfaceHost(
        projection: _resolve(source, includeDate: true),
        controller: controller,
      ),
    );

    final snapshot = controller.snapshot!;
    expect(snapshot.inlineComponentCount, 1);
    expect(snapshot.blockComponentCount, 0);
    expect(snapshot.projectedText, '$prefix\uFFFC$suffix');
    expect(snapshot.projectedText.length, prefix.length + 1 + suffix.length);
  });

  testWidgets('a same-revision projection swap replaces the surface plan', (
    tester,
  ) async {
    const source = 'Before {{date:2026-09-01}} after';
    final controller = ComposerSurfaceController();

    await tester.pumpWidget(
      _surfaceHost(projection: _resolve(source), controller: controller),
    );
    expect(controller.snapshot!.projectedText, source);

    await tester.pumpWidget(
      _surfaceHost(
        projection: _resolve(source, includeDate: true),
        controller: controller,
      ),
    );
    await tester.pump();

    expect(controller.snapshot!.projectedText, 'Before \uFFFC after');
    expect(find.text('September 1'), findsOneWidget);
  });

  testWidgets('a block node takes the height of its widget, not its source', (
    tester,
  ) async {
    const rawComponent = '''[grid]
| one | two |
| --- | --- |
| a | b |
| c | d |
| e | f |
| g | h |
| i | j |
[/grid]''';
    const source = 'Before\n$rawComponent\nAfter';
    final controller = ComposerSurfaceController();

    await tester.pumpWidget(
      _surfaceHost(
        projection: _resolve(source, includeGrid: true),
        controller: controller,
      ),
    );
    await tester.pump();

    expect(rawComponent.split('\n'), hasLength(9));
    final gridRect = tester.getRect(find.byKey(const Key('grid-widget')));
    expect(gridRect.height, 173);
    expect(controller.snapshot!.blockComponentCount, 1);
    final projectedText = controller.snapshot!.projectedText;
    expect(projectedText, 'Before\n\uFFFC\nAfter');
    expect(projectedText, isNot(contains(rawComponent)));

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final blockOffset = projectedText.indexOf('\uFFFC');
    final followingCaret = editable.renderEditable.getLocalRectForCaret(
      TextPosition(offset: blockOffset + 2),
    );
    final followingCaretTop = editable.renderEditable.localToGlobal(
      followingCaret.topLeft,
    );
    expect(followingCaretTop.dy, greaterThanOrEqualTo(gridRect.bottom));

    final hit = editable.renderEditable.getPositionForPoint(
      Offset(followingCaretTop.dx + 2, followingCaretTop.dy + 2),
    );
    expect(hit.offset, greaterThan(blockOffset));
  });

  testWidgets('a block owns its row without a trailing source newline', (
    tester,
  ) async {
    const rawComponent = '[grid]\none\n[/grid]';
    const source = 'Before\n${rawComponent}After';
    final controller = ComposerSurfaceController();

    await tester.pumpWidget(
      _surfaceHost(
        projection: _resolve(source, includeGrid: true),
        controller: controller,
      ),
    );
    await tester.pump();

    expect(controller.snapshot!.projectedText, 'Before\n\uFFFCAfter');
    final gridRect = tester.getRect(find.byKey(const Key('grid-widget')));
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final blockOffset = controller.snapshot!.projectedText.indexOf('\uFFFC');
    final followingCaret = editable.renderEditable.getLocalRectForCaret(
      TextPosition(offset: blockOffset + 1),
    );
    final followingCaretTop = editable.renderEditable.localToGlobal(
      followingCaret.topLeft,
    );

    expect(followingCaretTop.dy, greaterThanOrEqualTo(gridRect.bottom));
  });

  test('production adapter gates remain explicit', () {
    expect(projectedTextFieldComposerSurfaceGate.isProductionReady, isFalse);
    expect(superEditorDev52ComposerSurfaceGate.isProductionReady, isFalse);
    expect(
      superEditorDev52ComposerSurfaceGate.blockers,
      contains(ComposerSurfaceCapability.swiftPackageManager),
    );
  });

  test('maps both boundaries of a compressed inline atom', () {
    const rawComponent = '{{date:2026-09-01}}';
    const source = 'a$rawComponent b';
    final plan = ComposerSurfaceProjectionPlan.fromProjection(
      _resolve(source, includeDate: true),
    );
    final atom = plan.atoms.single;

    expect(atom.sourceBefore, 1);
    expect(atom.sourceAfter, 1 + rawComponent.length);
    expect(atom.surfaceBefore, 1);
    expect(atom.surfaceAfter, 2);
    expect(plan.componentAtSurfaceOffset(atom.surfaceOffset)?.kind, _dateKind);
    expect(plan.componentAtSurfaceOffset(0), isNull);

    expect(
      plan.surfaceBoundaryForSourceBoundary(atom.sourceBefore + 1),
      atom.surfaceBefore,
    );
    expect(
      plan.surfaceBoundaryForSourceBoundary(
        atom.sourceBefore + 1,
        affinity: ComposerSurfaceAtomAffinity.after,
      ),
      atom.surfaceAfter,
    );
    expect(
      plan.sourceBoundaryForSurfaceBoundary(atom.surfaceBefore),
      atom.sourceBefore,
    );
    expect(
      plan.sourceBoundaryForSurfaceBoundary(atom.surfaceAfter),
      atom.sourceAfter,
    );
    expect(
      plan.sourceRangeForSurfaceRange(
        ComposerSurfaceRange(atom.surfaceBefore, atom.surfaceAfter),
      ),
      ComposerSourceRange(atom.sourceBefore, atom.sourceAfter),
    );
  });

  test('a one-code-unit atom still has distinct surface boundaries', () {
    const source = 'a@b';
    final plan = ComposerSurfaceProjectionPlan.fromProjection(
      _resolve(source, includeOneCodeUnit: true),
    );
    final atom = plan.atoms.single;

    expect(plan.snapshot.projectedText, 'a\uFFFCb');
    expect(atom.component.sourceRange.length, 1);
    expect(atom.surfaceBefore, 1);
    expect(atom.surfaceAfter, 2);
    expect(plan.surfaceBoundaryForSourceBoundary(1), 1);
    expect(plan.surfaceBoundaryForSourceBoundary(2), 2);
    expect(plan.sourceBoundaryForSurfaceBoundary(1), 1);
    expect(plan.sourceBoundaryForSurfaceBoundary(2), 2);
    expect(
      plan.sourceRangeForSurfaceRange(const ComposerSurfaceRange(1, 2)),
      const ComposerSourceRange(1, 2),
    );
  });

  test('a selected block placeholder expands to the complete block source', () {
    const rawComponent = '[grid]\none\ntwo\n[/grid]';
    const source = 'Before\n$rawComponent\nAfter';
    final plan = ComposerSurfaceProjectionPlan.fromProjection(
      _resolve(source, includeGrid: true),
    );
    final atom = plan.atoms.single;

    expect(atom.component.layout, ComposerComponentLayout.block);
    expect(
      plan.sourceRangeForSurfaceRange(
        ComposerSurfaceRange(atom.surfaceBefore, atom.surfaceAfter),
      ),
      ComposerSourceRange(
        source.indexOf(rawComponent),
        source.indexOf(rawComponent) + rawComponent.length,
      ),
    );
  });
}

Widget _surfaceHost({
  required ComposerProjection projection,
  required ComposerSurfaceController controller,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        child: ComposerSurface(
          projection: projection,
          controller: controller,
          components: ComposerSurfaceComponents(
            widgets: {
              _dateKind: (context, component) => const Text('September 1'),
              _gridKind: (context, component) => const SizedBox(
                key: Key('grid-widget'),
                height: 173,
                child: Text('Grid preview'),
              ),
            },
            semanticLabels: {
              _dateKind: (context, component) => 'Date: September 1',
              _gridKind: (context, component) => 'Grid preview',
            },
          ),
        ),
      ),
    ),
  );
}

ComposerProjection _resolve(
  String source, {
  bool includeDate = false,
  bool includeGrid = false,
  bool includeOneCodeUnit = false,
}) {
  final definitions = <ComposerComponentDefinition<Object>>[];
  if (includeDate) {
    definitions.add(
      ComposerComponentDefinition<Object>(
        kind: _dateKind,
        layout: ComposerComponentLayout.inline,
        precedence: 0,
        parse: (input) => RegExp(r'\{\{date:([^}]+)\}\}')
            .allMatches(input.source)
            .map(
              (match) => ComposerComponentCandidate<Object>(
                range: ComposerSourceRange(match.start, match.end),
                value: match.group(1)!,
              ),
            ),
      ),
    );
  }
  if (includeGrid) {
    definitions.add(
      ComposerComponentDefinition<Object>(
        kind: _gridKind,
        layout: ComposerComponentLayout.block,
        precedence: 0,
        parse: (input) => RegExp(r'\[grid\][\s\S]*?\[/grid\]')
            .allMatches(input.source)
            .map(
              (match) => ComposerComponentCandidate<Object>(
                range: ComposerSourceRange(match.start, match.end),
                value: 'parsed grid',
              ),
            ),
      ),
    );
  }
  if (includeOneCodeUnit) {
    definitions.add(
      ComposerComponentDefinition<Object>(
        kind: _oneCodeUnitKind,
        layout: ComposerComponentLayout.inline,
        precedence: 0,
        parse: (input) => RegExp('@')
            .allMatches(input.source)
            .map(
              (match) => ComposerComponentCandidate<Object>(
                range: ComposerSourceRange(match.start, match.end),
                value: 'at',
              ),
            ),
      ),
    );
  }

  return const ComposerProjectionResolver().resolve(
    input: ComposerParseInput(
      source: source,
      revision: const ComposerRevision(1),
    ),
    definitions: definitions,
  );
}
