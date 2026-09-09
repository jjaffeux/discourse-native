import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  ThemeData? theme,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: direction,
        child: Center(child: SizedBox(width: 600, child: child)),
      ),
    ),
  ),
);

void main() {
  testWidgets('matches slot bounds, gaps and reference text metrics', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const DEmpty(
          children: [
            DEmptyHeader(
              children: [
                DEmptyMedia(
                  variant: DEmptyMediaVariant.icon,
                  child: Icon(Icons.cloud),
                ),
                DEmptyTitle('No data'),
                DEmptyDescription('A short explanation'),
              ],
            ),
            DEmptyContent(
              children: [
                SizedBox(key: Key('action'), width: 60, height: 28),
                SizedBox(key: Key('second'), height: 20),
              ],
            ),
          ],
        ),
      ),
    );
    final media = tester.getRect(find.byType(Icon));
    final title = tester.getRect(find.text('No data'));
    final description = tester.getRect(find.text('A short explanation'));
    final content = tester.getRect(find.byType(DEmptyContent));
    expect(media.size, const Size(16, 16));
    expect(
      title.top - media.bottom,
      24,
    ); // 8px tile inset + margin + header gap.
    expect(description.top - title.bottom, 8);
    expect(content.top - description.bottom, 16);
    expect(content.width, 384);
    expect(
      tester.getRect(find.byKey(const Key('second'))).top -
          tester.getRect(find.byKey(const Key('action'))).bottom,
      10,
    );
    final style = tester.widget<Text>(find.text('No data')).style!;
    expect(style.fontSize, 14);
    expect(style.height, 20 / 14);
    expect(style.letterSpacing, -.35);
    expect(style.fontWeight, FontWeight.w500);
  });

  testWidgets(
    'updates live palette radius and preserves borrowed editing and focus',
    (tester) async {
      final controller = TextEditingController(text: 'draft');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      final base = ThemeData.light();
      final tokens = DTokens.fromTheme(base);
      Widget sample(ThemeData theme) => _host(
        DEmpty(
          outlined: true,
          children: [
            const DEmptyHeader(
              children: [
                DEmptyMedia(
                  variant: DEmptyMediaVariant.icon,
                  child: Icon(Icons.cloud),
                ),
                DEmptyTitle('Title'),
              ],
            ),
            DEmptyContent(
              children: [TextField(controller: controller, focusNode: focus)],
            ),
          ],
        ),
        theme: theme,
      );
      await tester.pumpWidget(sample(base.copyWith(extensions: [tokens])));
      focus.requestFocus();
      await tester.pump();
      final changed = tokens.copyWith(
        radius: 12,
        muted: const Color(0x55224466),
      );
      await tester.pumpWidget(sample(base.copyWith(extensions: [changed])));
      await tester.pumpAndSettle();
      expect(controller.text, 'draft');
      expect(focus.hasFocus, isTrue);
      final tile = tester.widget<Container>(
        find.descendant(
          of: find.byType(DEmptyMedia),
          matching: find.byType(Container),
        ),
      );
      final decoration = tile.decoration! as BoxDecoration;
      expect(decoration.color, changed.muted);
      expect(decoration.borderRadius, BorderRadius.circular(12));
      await tester.pumpWidget(const SizedBox());
      controller.text = 'still owned by caller';
      expect(controller.text, 'still owned by caller');
    },
  );

  testWidgets(
    'arbitrary content retains Form validation reset and keyboard action',
    (tester) async {
      final form = GlobalKey<FormState>();
      String? saved;
      await tester.pumpWidget(
        _host(
          Form(
            key: form,
            child: DEmpty(
              children: [
                const DEmptyHeader(
                  children: [DEmptyTitle('Search', headingLevel: 2)],
                ),
                DEmptyContent(
                  children: [
                    TextFormField(
                      initialValue: 'initial',
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                      onSaved: (v) => saved = v,
                    ),
                    TextButton(
                      onPressed: () {
                        if (form.currentState!.validate()) {
                          form.currentState!.save();
                        }
                      },
                      child: const Text('Submit'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'query');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(saved, 'query');
      form.currentState!.reset();
      await tester.pump();
      expect(find.text('initial'), findsOneWidget);
    },
  );

  testWidgets(
    'large RTL text and arbitrary media fit a narrow scrolling pane',
    (tester) async {
      tester.view.physicalSize = const Size(240, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          const SingleChildScrollView(
            child: DEmpty(
              children: [
                DEmptyHeader(
                  children: [
                    DEmptyMedia(child: SizedBox(width: 48, height: 48)),
                    DEmptyTitle('لا توجد مشاريع بعد', headingLevel: 1),
                    DEmptyDescription(
                      'لم تقم بإنشاء أي مشاريع بعد. ابدأ بإنشاء مشروعك الأول.',
                    ),
                  ],
                ),
                DEmptyContent(
                  children: [
                    Text('Long content which wraps across several lines'),
                  ],
                ),
              ],
            ),
          ),
          scale: 2,
          direction: TextDirection.rtl,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(DEmptyContent)).width, 192);
      expect(
        tester
            .getSemantics(find.text('لا توجد مشاريع بعد'))
            .getSemanticsData()
            .headingLevel,
        1,
      );
      semantics.dispose();
    },
  );
}
