import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/shell/composer_document/component.dart'
    as document;
import 'package:discourse_native/src/shell/composer_document/document.dart';
import 'package:discourse_native/src/shell/composer_document/interaction.dart';
import 'package:discourse_native/src/shell/composer_document/selection.dart';
import 'package:discourse_native/src/shell/composer_document/source.dart';
import 'package:discourse_native/src/shell/composer_hybrid/component_registration.dart';
import 'package:discourse_native/src/shell/composer_hybrid/session.dart';
import 'package:discourse_native/src/shell/composer_surface/projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registers the editing-contract tests shared by every hybrid component.
///
/// [markdown] must contain exactly one component occurrence at [expectedRange].
/// Keeping the fixture source outside this harness makes the same suite useful
/// for both core and plugin-owned component parsers.
void runComposerComponentConformance<T extends Object>({
  required String name,
  required ComposerComponent<T> component,
  required String markdown,
  required TextRange expectedRange,
  required ComposerComponentLayout expectedLayout,
}) {
  if (!expectedRange.isValid ||
      expectedRange.isCollapsed ||
      expectedRange.end > markdown.length) {
    throw ArgumentError.value(
      expectedRange,
      'expectedRange',
      'must identify a non-empty range inside markdown',
    );
  }

  final expectedSource = markdown.substring(
    expectedRange.start,
    expectedRange.end,
  );
  final expectedDocumentRange = ComposerSourceRange(
    expectedRange.start,
    expectedRange.end,
  );

  ComposerHybridEditingSession createSession(ComposerSelection selection) {
    return ComposerHybridEditingSession(
      markdown: markdown,
      registrations: [ComposerHybridComponentRegistration.from(component)],
      selection: selection,
    );
  }

  group('$name hybrid component conformance', () {
    test('projects one exact, lossless, raw-free surface atom', () {
      final session = createSession(
        ComposerCaretSelection(expectedRange.start),
      );
      addTearDown(session.dispose);

      final projection = session.snapshot.projection;
      final match = projection.components.single;
      expect(projection.issues, isEmpty);
      expect(match.kind.value, component.kind.id);
      expect(match.range, expectedDocumentRange);
      expect(match.source, expectedSource);
      expect(match.layout, _documentLayoutFor(expectedLayout));
      expect(projection.reconstructedSource, markdown);
      expect(session.markdown, markdown);

      final surface = ComposerSurfaceProjectionPlan.fromProjection(projection);
      final atom = surface.atoms.single;
      expect(atom.component.kind, match.kind);
      expect(atom.component.sourceRange, expectedDocumentRange);
      expect(
        surface.snapshot.inlineComponentCount +
            surface.snapshot.blockComponentCount,
        1,
      );
      expect(
        surface.snapshot.inlineComponentCount,
        expectedLayout == ComposerComponentLayout.inline ? 1 : 0,
      );
      expect(
        surface.snapshot.blockComponentCount,
        expectedLayout == ComposerComponentLayout.block ? 1 : 0,
      );
      expect(surface.snapshot.projectedText, isNot(contains(expectedSource)));
      expect(
        surface.snapshot.projectedText,
        contains(composerSurfaceObjectReplacementCharacter),
      );
      expect(
        surface.sourceRangeForSurfaceRange(
          ComposerSurfaceRange(atom.surfaceBefore, atom.surfaceAfter),
        ),
        expectedDocumentRange,
      );
    });

    testWidgets('renders and labels without exact authoring source', (
      tester,
    ) async {
      final session = createSession(
        ComposerCaretSelection(expectedRange.start),
      );
      addTearDown(session.dispose);
      final match = session.snapshot.projection.components.single;
      final renderer = session.rendererFor(match.kind)!;
      late BuildContext buildContext;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              buildContext = context;
              return renderer.build(
                context,
                match: match,
                baseStyle: const TextStyle(fontSize: 16),
                selected: false,
                hovered: false,
              );
            },
          ),
        ),
      );

      final renderedText = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((widget) => widget.text.toPlainText())
          .join();
      expect(renderedText, isNot(contains(expectedSource)));
      expect(
        renderer.semanticLabel(buildContext, match),
        isNot(contains(expectedSource)),
      );
    });

    test('traverses before, selected, and after in both directions', () {
      final session = createSession(
        ComposerCaretSelection(expectedRange.start),
      );
      addTearDown(session.dispose);
      final token = session.snapshot.projection.components.single.token;

      final selectedFromBefore = session.dispatch(
        const ComposerMoveIntent(ComposerMoveDirection.right),
      );
      expect(selectedFromBefore, isA<ComposerHybridSelectionHandled>());
      expect(session.selection, ComposerComponentSelection(token));

      session.dispatch(const ComposerMoveIntent(ComposerMoveDirection.right));
      expect(session.selection, ComposerCaretSelection(expectedRange.end));

      final selectedFromAfter = session.dispatch(
        const ComposerMoveIntent(ComposerMoveDirection.left),
      );
      expect(selectedFromAfter, isA<ComposerHybridSelectionHandled>());
      expect(session.selection, ComposerComponentSelection(token));

      session.dispatch(const ComposerMoveIntent(ComposerMoveDirection.left));
      expect(session.selection, ComposerCaretSelection(expectedRange.start));
    });

    for (final direction in ComposerDeleteDirection.values) {
      final keyName = switch (direction) {
        ComposerDeleteDirection.backward => 'Backspace',
        ComposerDeleteDirection.forward => 'Delete',
      };

      test('$keyName selects at the boundary, then removes one atom', () {
        final boundary = direction == ComposerDeleteDirection.backward
            ? expectedRange.end
            : expectedRange.start;
        final session = createSession(ComposerCaretSelection(boundary));
        addTearDown(session.dispose);
        final token = session.snapshot.projection.components.single.token;

        final selected = session.dispatch(ComposerDeleteIntent(direction));
        expect(selected, isA<ComposerHybridSelectionHandled>());
        expect(session.selection, ComposerComponentSelection(token));
        expect(session.markdown, markdown);
        expect(session.revision, const ComposerRevision(0));

        final removed = session.dispatch(ComposerDeleteIntent(direction));
        expect(removed, isA<ComposerHybridTransactionHandled>());
        expect(
          (removed as ComposerHybridTransactionHandled).result,
          isA<ComposerCommitApplied>(),
        );
        expect(
          session.markdown,
          markdown.replaceRange(expectedRange.start, expectedRange.end, ''),
        );
        expect(session.revision, const ComposerRevision(1));
        expect(session.selection, ComposerCaretSelection(expectedRange.start));
        expect(session.snapshot.projection.components, isEmpty);
      });
    }

    test('snaps partial forward and reverse ranges around the atom', () {
      final forwardSession = createSession(const ComposerCaretSelection(0));
      addTearDown(forwardSession.dispose);
      final forwardInterior = expectedRange.start + 1;

      forwardSession.dispatch(
        ComposerSelectIntent(
          anchor: expectedRange.start,
          focus: forwardInterior,
        ),
      );
      expect(
        forwardSession.selection,
        ComposerRangeSelection(
          anchor: expectedRange.start,
          focus: expectedRange.end,
        ),
      );

      final reverseSession = createSession(const ComposerCaretSelection(0));
      addTearDown(reverseSession.dispose);
      final reverseInterior = expectedRange.end - 1;

      reverseSession.dispatch(
        ComposerSelectIntent(anchor: expectedRange.end, focus: reverseInterior),
      );
      expect(
        reverseSession.selection,
        ComposerRangeSelection(
          anchor: expectedRange.end,
          focus: expectedRange.start,
        ),
      );
    });

    test('Escape unselects the atom at its after boundary', () {
      final session = createSession(
        ComposerCaretSelection(expectedRange.start),
      );
      addTearDown(session.dispose);

      session.dispatch(const ComposerMoveIntent(ComposerMoveDirection.right));
      expect(session.selection, isA<ComposerComponentSelection>());

      final escaped = session.dispatch(const ComposerEscapeIntent());
      expect(escaped, isA<ComposerHybridSelectionHandled>());
      expect(session.selection, ComposerCaretSelection(expectedRange.end));

      final passThrough = session.dispatch(const ComposerEscapeIntent());
      expect(passThrough, isA<ComposerHybridPassThrough>());
    });

    test('undo restores exact source and component selection', () {
      final session = createSession(
        ComposerCaretSelection(expectedRange.start),
      );
      addTearDown(session.dispose);
      final originalToken = session.snapshot.projection.components.single.token;

      session.dispatch(const ComposerMoveIntent(ComposerMoveDirection.right));
      expect(session.selection, ComposerComponentSelection(originalToken));
      session.dispatch(
        const ComposerDeleteIntent(ComposerDeleteDirection.backward),
      );
      expect(session.markdown, isNot(markdown));

      final restored = session.undo();
      expect(restored?.source, markdown);
      expect(restored?.projection.reconstructedSource, markdown);
      expect(restored?.selection, isA<ComposerComponentSelection>());
      final restoredToken =
          (restored!.selection as ComposerComponentSelection).component;
      expect(restoredToken.revision, restored.revision);
      expect(restoredToken.revision, isNot(originalToken.revision));
      expect(restoredToken.kind, originalToken.kind);
      expect(restoredToken.range, originalToken.range);
      expect(restoredToken.source, originalToken.source);
      expect(restored.projection.components.single.source, expectedSource);
    });
  });
}

document.ComposerComponentLayout _documentLayoutFor(
  ComposerComponentLayout layout,
) {
  return switch (layout) {
    ComposerComponentLayout.inline => document.ComposerComponentLayout.inline,
    ComposerComponentLayout.block => document.ComposerComponentLayout.block,
  };
}
