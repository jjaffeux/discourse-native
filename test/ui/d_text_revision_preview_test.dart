import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (current, saved) in [
    ('A new sentence.', 'A saved sentence.'),
    ('👩🏽‍💻 café\nnext', '👩🏽‍💻 thé\nfirst'),
    ('  indent\n', '  indent\n\n'),
    ('', 'restored'),
    ('removed', ''),
    ('x ' * 1000, 'y ' * 1000),
  ]) {
    test(
      'word diff losslessly reconstructs both sides (${current.length}, ${saved.length})',
      () {
        final runs = textRevisionRuns(current, saved);
        expect(
          runs
              .where((r) => r.kind != DTextRevisionKind.restored)
              .map((r) => r.text)
              .join(),
          current,
        );
        expect(
          runs
              .where((r) => r.kind != DTextRevisionKind.removed)
              .map((r) => r.text)
              .join(),
          saved,
        );
      },
    );
  }

  testWidgets(
    'preview retains child state, semantics describe changes, reduced motion shows final text',
    (tester) async {
      final semantic = tester.ensureSemantics();
      try {
        final controller = TextEditingController(text: 'live editor');
        addTearDown(controller.dispose);
        Widget host(
          bool active, {
          bool reduced = false,
          Animation<double>? animation,
        }) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              disableAnimations: reduced,
              textScaler: const TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SizedBox(
                width: 300,
                height: 240,
                child: DTextRevisionPreview(
                  current: 'A new sentence.',
                  saved: 'A saved sentence.',
                  active: active,
                  restoration: animation,
                  child: DTextarea(controller: controller),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(host(false));
        final editor = tester.element(find.byType(EditableText));
        await tester.pumpWidget(host(true));
        expect(tester.element(find.byType(EditableText)), same(editor));
        expect(controller.text, 'live editor');
        expect(find.bySemanticsLabel(RegExp('Removed: new')), findsOneWidget);
        await tester.pumpWidget(
          host(
            true,
            reduced: true,
            animation: const AlwaysStoppedAnimation(.2),
          ),
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.textSpan?.toPlainText(includeSemanticsLabels: false) ==
                    'A saved sentence.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(host(false));
        expect(tester.element(find.byType(EditableText)), same(editor));
      } finally {
        semantic.dispose();
      }
    },
  );
}
