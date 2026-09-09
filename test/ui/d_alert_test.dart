import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(
    Widget child, {
    double width = 448,
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
    ThemeData? theme,
  }) => MaterialApp(
    theme: theme,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: direction,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
  const basic = DAlert(
    icon: Icon(Icons.info_outline),
    title: DAlertTitle(child: Text('Title')),
    description: DAlertDescription(child: Text('Description')),
  );

  testWidgets('source grid metrics and live-region semantics', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(host(basic));
    expect(tester.getSize(find.byType(DAlert)), const Size(448, 60));
    expect(tester.getTopLeft(find.text('Title')), const Offset(35, 9));
    expect(tester.getTopLeft(find.text('Description')), const Offset(35, 31));
    expect(
      tester.getTopLeft(find.byIcon(Icons.info_outline)),
      const Offset(11, 11),
    );
    final node = tester.getSemantics(find.byType(DAlert));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    await tester.pumpWidget(
      host(
        const DAlert(
          liveRegion: false,
          description: DAlertDescription(child: Text('History')),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(DAlert)).flagsCollection.isLiveRegion,
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('measured actions reflow, mirror and keep keyboard ownership', (
    tester,
  ) async {
    var presses = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Widget alert() => DAlert(
      title: const DAlertTitle(child: Text('Title')),
      description: const DAlertDescription(
        child: Text('A useful message that wraps naturally.'),
      ),
      action: DAlertAction(
        child: DButton(
          focusNode: focus,
          label: const Text('Retry'),
          onPressed: () => presses++,
        ),
      ),
    );
    await tester.pumpWidget(host(alert()));
    final normal = tester.getRect(find.byType(DButton));
    expect(normal.right, 439);
    expect(normal.top, 9);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
    await tester.pumpWidget(
      host(alert(), width: 240, scale: 2, direction: TextDirection.rtl),
    );
    expect(
      tester.getRect(find.byType(DButton)).top,
      greaterThan(
        tester
            .getRect(find.text('A useful message that wraps naturally.'))
            .bottom,
      ),
    );
    expect(tester.getRect(find.byType(DButton)).left, 9);
    await tester.tap(find.byType(DButton));
    expect(presses, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'live tokens preserve border role, proportional radius and alpha',
    (tester) async {
      for (final dark in [false, true]) {
        final base = ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        final tokens = DTokens.fromTheme(base).copyWith(
          radius: 13,
          border: const Color(0xff123456),
          colors: base.colorScheme.copyWith(
            error: const Color(0x80ff0000),
            outlineVariant: Colors.green,
          ),
        );
        await tester.pumpWidget(
          host(
            const DAlert(
              variant: DAlertVariant.destructive,
              description: DAlertDescription(child: Text('Failure')),
            ),
            theme: base.copyWith(extensions: [tokens]),
          ),
        );
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(DAlert),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final decoration = box.decoration as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(13));
        expect((decoration.border! as Border).top.color, tokens.border);
        final context = tester.element(find.text('Failure'));
        expect(
          DefaultTextStyle.of(context).style.color!.a,
          closeTo(tokens.destructive.a * .9, .001),
        );
      }
    },
  );
}
