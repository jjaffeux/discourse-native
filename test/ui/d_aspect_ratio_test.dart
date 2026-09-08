import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ratio rejects zero, negative and non-finite values', () {
    for (final ratio in [
      0.0,
      -1.0,
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ]) {
      expect(
        () => DAspectRatio(ratio: ratio),
        throwsAssertionError,
        reason: '$ratio',
      );
    }
  });

  testWidgets(
    'arbitrary ratios honor bounded, tight and conflicting constraints',
    (tester) async {
      for (final (ratio, constraints, size) in [
        (16 / 9, const BoxConstraints(maxWidth: 384), const Size(384, 216)),
        (1.0, const BoxConstraints(maxWidth: 192), const Size(192, 192)),
        (
          9 / 16,
          const BoxConstraints(maxWidth: 160),
          const Size(160, 160 * 16 / 9),
        ),
        (1.37, const BoxConstraints(maxWidth: 274), const Size(274, 200)),
        (3 / 2, const BoxConstraints(maxHeight: 100), const Size(150, 100)),
        (
          16 / 9,
          const BoxConstraints(maxWidth: 260, maxHeight: 100),
          const Size(1600 / 9, 100),
        ),
        (
          1.0,
          const BoxConstraints.tightFor(width: 160, height: 90),
          const Size(160, 90),
        ),
        (
          1.0,
          const BoxConstraints(minWidth: 200, maxWidth: 300, maxHeight: 100),
          const Size(200, 100),
        ),
        (2.0, const BoxConstraints.tightFor(width: 0), Size.zero),
      ]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: UnconstrainedBox(
                child: ConstrainedBox(
                  constraints: constraints,
                  child: DAspectRatio(
                    ratio: ratio,
                    child: const SizedBox(key: ValueKey('content')),
                  ),
                ),
              ),
            ),
          ),
        );
        final actual = tester.getSize(find.byType(DAspectRatio));
        expect(
          actual.width,
          closeTo(size.width, 0.001),
          reason: '$ratio $constraints',
        );
        expect(
          actual.height,
          closeTo(size.height, 0.001),
          reason: '$ratio $constraints',
        );
        expect(tester.getSize(find.byKey(const ValueKey('content'))), actual);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'empty box reserves space and unbounded axes report a constraint error',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: 160, child: DAspectRatio(ratio: 2)),
          ),
        ),
      );
      expect(tester.getSize(find.byType(DAspectRatio)), const Size(160, 80));
      final render = tester.renderObject<RenderBox>(find.byType(DAspectRatio));
      expect(
        () => render.getDryLayout(const BoxConstraints()),
        throwsA(
          isA<FlutterError>().having(
            (error) => error.toString(),
            'message',
            contains('unbounded'),
          ),
        ),
      );
    },
  );

  testWidgets(
    'ratio, theme and direction updates retain input, focus, semantics and descendant ownership',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final controller = TextEditingController();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        var creations = 0;
        var disposals = 0;
        Widget app(
          double ratio,
          StyleguideTheme palette,
          TextDirection direction,
        ) => MaterialApp(
          theme: palette.resolve(AppTheme.light),
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: DAspectRatio(
                    ratio: ratio,
                    child: _Probe(
                      controller: controller,
                      focus: focus,
                      onCreate: () => creations++,
                      onDispose: () => disposals++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          app(1, StyleguideTheme.light, TextDirection.ltr),
        );
        await tester.enterText(find.byType(TextField), 'Retained draft');
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        for (final palette in [
          StyleguideTheme.dark,
          StyleguideTheme.forest,
          StyleguideTheme.plum,
        ]) {
          await tester.pumpWidget(app(1.5, palette, TextDirection.rtl));
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          expect(controller.text, 'Retained draft');
          expect(find.text('Count: 1'), findsOneWidget);
          expect(find.bySemanticsLabel('Increment'), findsOneWidget);
          expect(find.bySemanticsLabel('Child image'), findsOneWidget);
          expect(creations, 1);
          expect(disposals, 0);
          expect(
            tester.getSize(find.byType(DAspectRatio)).height,
            closeTo(320 / 1.5, 0.001),
          );
        }
        await tester.tap(find.text('Increment'));
        await tester.pump();
        expect(find.text('Count: 2'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        expect(disposals, 1);
        controller.text = 'Still caller owned';
        expect(controller.text, 'Still caller owned');
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'large content keeps native text scale and scroll position on ratio updates',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      Widget app(double ratio) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: DAspectRatio(
                  ratio: ratio,
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: const Column(
                      children: [
                        Text('Large text', style: TextStyle(fontSize: 16)),
                        SizedBox(height: 800),
                        Text('End'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(1));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('Large text'),
      );
      expect(paragraph.textScaler.scale(16), 32);
      scroll.jumpTo(120);
      await tester.pumpWidget(app(1.37));
      expect(scroll.offset, 120);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Probe extends StatefulWidget {
  const _Probe({
    required this.controller,
    required this.focus,
    required this.onCreate,
    required this.onDispose,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onCreate;
  final VoidCallback onDispose;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int count = 0;

  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      children: [
        TextField(controller: widget.controller),
        DButton(
          focusNode: widget.focus,
          onPressed: () => setState(() => count++),
          label: const Text('Increment'),
        ),
        Text('Count: $count'),
        Semantics(
          image: true,
          label: 'Child image',
          child: const SizedBox(height: 20),
        ),
      ],
    ),
  );
}
