import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _card({
  VoidCallback? onPressed,
  FocusNode? focus,
  bool selected = false,
}) => DPlaceCard(
  leading: const DPlaceCardMark(color: Colors.blue, child: Icon(Icons.tag)),
  title: const Text('Support'),
  description: const Text('Questions and answers from the community.'),
  footer: const Text('42 topics · 2h'),
  unreadCount: '3',
  strong: true,
  selected: selected,
  focusNode: focus,
  onPressed: onPressed,
);

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
  bool reduced = false,
  bool highContrast = false,
  DAppearanceMaterial material = DAppearanceMaterial.standard,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: DMaterialTheme.apply(AppTheme.light, material),
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduced,
          highContrast: highContrast,
        ),
        child: Scaffold(
          body: Center(child: SizedBox(width: 260, child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('card owns one accessible action and its native metrics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var presses = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _mount(tester, _card(onPressed: () => presses++, focus: focus));
    final card = find.byType(DPlaceCard);
    final rect = tester.getRect(card);
    final mark = tester.getRect(find.byType(DPlaceCardMark));
    expect(rect.width, 260);
    expect(rect.height, greaterThanOrEqualTo(100));
    expect(mark.size, const Size(29, 29));
    expect(mark.left - rect.left, 12);
    expect(mark.top - rect.top, 11);
    expect(tester.getRect(find.text('3')).top - rect.top, 13);
    final data = tester.getSemantics(card).getSemanticsData();
    expect(data.label, contains('Support'));
    expect(data.label, contains('42 topics'));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    await tester.tapAt(rect.topLeft + const Offset(1, 1));
    expect(presses, 0);
    await tester.tapAt(rect.bottomLeft + const Offset(14, -3));
    expect(presses, 1);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(presses, 3);
    semantics.dispose();
  });

  testWidgets('hover lifts only the visible card and expands the shadow', (
    tester,
  ) async {
    var presses = 0;
    await _mount(tester, _card(onPressed: () => presses++));
    final decoration = find.descendant(
      of: find.byType(DPlaceCard),
      matching: find.byType(AnimatedContainer),
    );
    BoxDecoration surface() =>
        tester.widget<AnimatedContainer>(decoration).decoration!
            as BoxDecoration;
    expect(surface().boxShadow!.last.blurRadius, 14);
    final original = tester.getRect(find.byType(GestureDetector).last);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(original.center);
    await tester.pumpAndSettle();
    expect(surface().boxShadow!.last.blurRadius, 24);
    expect(
      tester.getTopLeft(find.byType(GestureDetector).last).dy,
      closeTo(original.top - 1, .01),
    );
    await tester.tapAt(Offset(original.right + 3, original.center.dy));
    expect(presses, 0);
    await tester.tapAt(original.center);
    expect(presses, 1);
    await mouse.removePointer();
  });

  testWidgets('selected card keeps an inset accent ring and keyboard focus', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final prior = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    try {
      await _mount(
        tester,
        _card(onPressed: () {}, selected: true, focus: focus),
      );
      final card = find.byType(DPlaceCard);
      final tokens = DTokens.of(tester.element(card));
      final container = find.descendant(
        of: card,
        matching: find.byType(AnimatedContainer),
      );
      var visual = tester.widget<AnimatedContainer>(container);
      expect((visual.decoration! as BoxDecoration).boxShadow, isEmpty);
      expect(
        ((visual.foregroundDecoration! as BoxDecoration).border! as Border)
            .top
            .color,
        tokens.primary,
      );
      final rect = tester.getRect(card);
      focus.requestFocus();
      await tester.pumpAndSettle();
      visual = tester.widget<AnimatedContainer>(container);
      expect(
        ((visual.foregroundDecoration! as BoxDecoration).border! as Border)
            .top
            .width,
        2,
      );
      expect(tester.getRect(card), rect);
    } finally {
      FocusManager.instance.highlightStrategy = prior;
    }
  });

  testWidgets(
    'reduced motion preserves geometry and reduced transparency is opaque',
    (tester) async {
      await _mount(
        tester,
        _card(onPressed: () {}),
        reduced: true,
        highContrast: true,
        material: DAppearanceMaterial.liquidGlass,
      );
      final target = find.byType(GestureDetector).last;
      final rect = tester.getRect(target);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: rect.center);
      await tester.pumpAndSettle();
      expect(tester.getRect(target), rect);
      final surface =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byType(DPlaceCard),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(surface.color!.a, 1);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'lazy grid aligns different descriptions and leaves gaps inert in RTL',
    (tester) async {
      var presses = 0;
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: CustomScrollView(
                slivers: [
                  DPlaceCardGrid(
                    itemCount: 100,
                    itemBuilder: (context, index) => DPlaceCard(
                      key: ValueKey(index),
                      leading: const DPlaceCardMark(
                        color: Colors.blue,
                        child: Icon(Icons.tag),
                      ),
                      title: Text('Category $index'),
                      description: index == 0
                          ? const Text(
                              'A long description that needs both lines to fit within this card.',
                            )
                          : null,
                      footer: Text('Footer $index'),
                      onPressed: () => presses++,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getRect(find.byKey(const ValueKey(0)));
      final second = tester.getRect(find.byKey(const ValueKey(1)));
      expect(first.size, second.size);
      expect(first.left - second.right, closeTo(10, .001));
      expect(
        tester.getRect(find.text('Footer 0')).bottom,
        tester.getRect(find.text('Footer 1')).bottom,
      );
      expect(find.byKey(const ValueKey(99)), findsNothing);
      await tester.tapAt(Offset(second.right + 5, second.center.dy));
      expect(presses, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'card grows with text and disabling prevents pointer and keyboard actions',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await _mount(tester, _card(onPressed: () {}, focus: focus));
      final initial = tester.getSize(find.byType(DPlaceCard));
      await _mount(tester, _card(focus: focus), scale: 2);
      expect(
        tester.getSize(find.byType(DPlaceCard)).height,
        greaterThan(initial.height),
      );
      await tester.tap(find.byType(DPlaceCard));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(tester.takeException(), isNull);
    },
  );
}
