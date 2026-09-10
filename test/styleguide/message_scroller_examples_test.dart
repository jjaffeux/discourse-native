import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/message_scroller_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget exampleHost(WidgetBuilder builder) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(width: 360, child: Builder(builder: builder)),
      ),
    ),
  );

  test('accounts for every frozen behavior family', () {
    final text = messageScrollerExamples.examples
        .expand(
          (example) => [example.title, example.description, ...example.states],
        )
        .join(' ')
        .toLowerCase();

    for (final term in const [
      'stream',
      'previous context',
      'anchor',
      'group',
      'saved',
      'no flash',
      'prepend',
      'visibility',
      'scroll state',
      'virtual',
      'accessibility',
      'unstyled',
      'reduced motion',
    ]) {
      expect(text, contains(term), reason: term);
    }
  });

  testWidgets('all examples render at narrow 200% RTL with reduced motion', (
    tester,
  ) async {
    for (final example in messageScrollerExamples.examples) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: example.title);
    }
  });

  testWidgets('command example targets a stable virtualized row', (
    tester,
  ) async {
    final example = messageScrollerExamples.examples.singleWhere(
      (candidate) => candidate.title.startsWith('Commands'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 700, child: Builder(builder: example.builder)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Message 24'));
    await tester.pumpAndSettle();

    expect(find.text('Addressable message 24'), findsOneWidget);
    final viewport = tester.widget<DMessageScrollerViewport>(
      find.byType(DMessageScrollerViewport),
    );
    expect(viewport.itemId(23), 'command-23');
  });

  testWidgets('history example preserves its visible row across large prepends', (
    tester,
  ) async {
    final example = messageScrollerExamples.examples.singleWhere(
      (candidate) => candidate.title == 'Load history',
    );
    await tester.pumpWidget(exampleHost(example.builder));
    await tester.pumpAndSettle();
    final retained = find.text(
      'Earlier message 20 includes a second line to demonstrate variable-height restoration.',
    );
    final top = tester.getTopLeft(retained).dy;

    for (var batch = 0; batch < 2; batch++) {
      await tester.tap(find.text('Load earlier messages'));
      await tester.pumpAndSettle();
      expect(retained, findsOneWidget);
      expect(tester.getTopLeft(retained).dy, closeTo(top, .5));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reference demo preserves the canonical card chrome', (
    tester,
  ) async {
    final example = messageScrollerExamples.examples.singleWhere(
      (candidate) => candidate.title == 'Reference demo',
    );
    await tester.pumpWidget(exampleHost(example.builder));
    await tester.pumpAndSettle();

    final card = tester.widget<DCard>(find.byType(DCard));
    final header = tester.widget<DCardHeader>(find.byType(DCardHeader));
    final content = tester.widget<DCardContent>(find.byType(DCardContent));
    final footer = tester.widget<DCardFooter>(find.byType(DCardFooter));
    final reset = tester.widget<DButton>(
      find.byWidgetPredicate(
        (widget) => widget is DButton && widget.tooltip == 'Reset conversation',
      ),
    );
    final addFiles = tester.widget<DInputGroupButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is DInputGroupButton && widget.tooltip == 'Add files',
      ),
    );
    final helper = find.text('Demo is read only. Press send to send messages.');

    expect(card.spacing, DSpacing.xl);
    expect(header.border, isTrue);
    expect(content.edgeToEdge, isTrue);
    expect(content.joinNext, isTrue);
    expect(footer.border, isFalse);
    expect(footer.muted, isFalse);
    expect(reset.onPressed, isNotNull);
    expect(addFiles.variant, DButtonVariant.outline);
    expect(
      find.ancestor(of: helper, matching: find.byType(DCard)),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byType(DInputGroup),
        matching: find.byType(DCardFooter),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer owners reset, select a tool, send and stop a reply', (
    tester,
  ) async {
    await tester.pumpWidget(
      exampleHost(messageScrollerExamples.examples.first.builder),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DInputGroup), findsOneWidget);
    expect(find.byType(DDropdownMenu), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is DSelect<Object?>),
      findsOneWidget,
    );

    await tester.tap(find.text('Reset conversation'));
    await tester.pumpAndSettle();
    expect(find.byType(DEmpty), findsOneWidget);

    final tools = find.byWidgetPredicate(
      (widget) =>
          widget is DInputGroupButton && widget.tooltip == 'Composer tools',
    );
    await tester.ensureVisible(tools);
    await tester.tap(tools);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Web search'));
    await tester.pumpAndSettle();
    expect(
      find.text('Offline demo · next message: Web search'),
      findsOneWidget,
    );

    final send = find.byWidgetPredicate(
      (widget) =>
          widget is DInputGroupButton && widget.tooltip == 'Send message',
    );
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pump();
    expect(find.byType(DEmpty), findsNothing);
    expect(
      tester
          .widget<DMessageScrollerViewport>(
            find.byType(DMessageScrollerViewport),
          )
          .resolvedBusy,
      isTrue,
    );
    await tester.ensureVisible(find.text('Stop reply'));
    await tester.tap(find.text('Stop reply'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DMessageScrollerViewport>(
            find.byType(DMessageScrollerViewport),
          )
          .resolvedBusy,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('anchor role uses Toggle Group and changes new-turn anchoring', (
    tester,
  ) async {
    final example = messageScrollerExamples.examples.singleWhere(
      (candidate) => candidate.title.startsWith('Anchoring'),
    );
    await tester.pumpWidget(exampleHost(example.builder));
    await tester.pumpAndSettle();
    expect(find.byType(DToggleGroup<String>), findsOneWidget);
    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Append turn'));
    await tester.pumpAndSettle();
    final viewport = tester.widget<DMessageScrollerViewport>(
      find.byType(DMessageScrollerViewport),
    );
    expect(viewport.itemCount, 14);
    expect(viewport.itemIsAnchor(13), isTrue);
    expect(viewport.itemIsAnchor(12), isFalse);
  });

  testWidgets('outline preview has an accessible click-to-open jump list', (
    tester,
  ) async {
    final example = messageScrollerExamples.examples.singleWhere(
      (candidate) => candidate.title.startsWith('Commands'),
    );
    await tester.pumpWidget(exampleHost(example.builder));
    await tester.pumpAndSettle();
    expect(find.byType(DHoverCard), findsOneWidget);
    await tester.tap(find.text('Transcript outline'));
    await tester.pumpAndSettle();
    final turn = find.descendant(
      of: find.byKey(const ValueKey('transcript-outline-false')),
      matching: find.text('Turn 3'),
    );
    await tester.tap(turn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Addressable message 17'), findsOneWidget);
  });
}
