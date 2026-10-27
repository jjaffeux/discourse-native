import 'dart:ui' show Tristate;

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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
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
  testWidgets('card without a mark aligns its title with its content', (
    tester,
  ) async {
    var presses = 0;
    await _mount(
      tester,
      DPlaceCard(
        title: const Text('Team roadmap'),
        description: const Text('Upcoming work'),
        footer: const Text('3 columns'),
        onPressed: () => presses++,
      ),
    );
    final title = tester.getRect(find.text('Team roadmap'));
    final card = tester.getRect(find.byType(DPlaceCard));
    expect(title.left, card.left + 12);
    expect(title.left, tester.getRect(find.text('Upcoming work')).left);
    expect(title.left, tester.getRect(find.text('3 columns')).left);
    await tester.tap(find.text('Team roadmap'));
    expect(presses, 1);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('card controls keep their own targets and the footer yields', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var presses = 0, joins = 0, menus = 0;
    await _mount(
      tester,
      DPlaceCard(
        leading: const DPlaceCardMark(
          color: Colors.blue,
          child: Icon(Icons.tag),
        ),
        title: const Text('Support'),
        footer: const Text('42 members and a footer long enough to yield'),
        trailing: DButton.iconOnly(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          size: DButtonSize.small,
          onPressed: () => menus++,
        ),
        action: DButton(
          label: const Text('Join'),
          size: DButtonSize.small,
          onPressed: () => joins++,
        ),
        onPressed: () => presses++,
      ),
    );
    final card = tester.getRect(find.byType(DPlaceCard));
    final join = tester.getRect(find.widgetWithText(DButton, 'Join'));
    final footer = tester.getRect(find.textContaining('42 members'));
    expect(join.right, lessThanOrEqualTo(card.right - 12));
    expect(footer.right, lessThanOrEqualTo(join.left));
    await tester.tap(find.widgetWithText(DButton, 'Join'));
    await tester.tap(find.byTooltip('More'));
    expect((presses, joins, menus), (0, 1, 1));
    await tester.tap(find.text('Support'));
    expect(presses, 1);
    final node = tester.getSemantics(find.byType(DPlaceCard));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(
      find.descendant(
        of: find.byType(DPlaceCard),
        matching: find.bySemanticsLabel('Join'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('hover keeps the card flat and preserves its target', (
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
    expect(surface().boxShadow, isEmpty);
    final original = tester.getRect(find.byType(GestureDetector).last);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(original.center);
    await tester.pumpAndSettle();
    expect(surface().boxShadow, isEmpty);
    expect(
      tester.getTopLeft(find.byType(GestureDetector).last).dy,
      closeTo(original.top, .01),
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
    'reduced motion preserves geometry and high contrast preserves the fill',
    (tester) async {
      await _mount(
        tester,
        _card(onPressed: () {}),
        reduced: true,
        highContrast: true,
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
      expect(surface.color!.a, .82);
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

  testWidgets('card grows with text and exposes its disabled action state', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await _mount(tester, _card(onPressed: () {}, focus: focus));
      final initial = tester.getSize(find.byType(DPlaceCard));
      await _mount(tester, _card(focus: focus), scale: 2);
      expect(
        tester.getSize(find.byType(DPlaceCard)).height,
        greaterThan(initial.height),
      );
      final data = tester
          .getSemantics(find.byType(DPlaceCard))
          .getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      await tester.tap(find.byType(DPlaceCard));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
