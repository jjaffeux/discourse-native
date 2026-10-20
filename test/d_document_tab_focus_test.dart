import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'borrowed selection focus cancels before handled keys and restores handlers',
    (tester) async {
      final events = <String>[];
      var selections = 0;
      KeyEventResult firstHandler(FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent) events.add('first');
        return KeyEventResult.handled;
      }

      KeyEventResult nextHandler(FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent) events.add('next');
        return KeyEventResult.handled;
      }

      final first = FocusNode(onKeyEvent: firstHandler);
      final next = FocusNode(onKeyEvent: nextHandler);
      final close = FocusNode();
      addTearDown(first.dispose);
      addTearDown(next.dispose);
      addTearDown(close.dispose);

      Future<void> pump(FocusNode selection) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: 170,
              child: DDocumentTab(
                selected: true,
                selectionFocusNode: selection,
                closeFocusNode: close,
                onTapCancel: () => events.add('cancel'),
                onSelect: () => selections++,
                onClose: () {},
                closeLabel: 'Close draft',
                child: const Text('Draft'),
              ),
            ),
          ),
        ),
      );

      await pump(first);
      first.requestFocus();
      await tester.pumpAndSettle();
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.tab]) {
        await tester.sendKeyEvent(key);
      }
      expect(events, ['cancel', 'first', 'cancel', 'first']);
      expect(selections, 0);
      await pump(next);
      expect(first.onKeyEvent, firstHandler);
      next.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(events.sublist(4), ['cancel', 'next']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(next.onKeyEvent, nextHandler);
      expect(() => first.addListener(() {}), returnsNormally);
      expect(() => next.addListener(() {}), returnsNormally);
      expect(() => close.addListener(() {}), returnsNormally);
    },
  );

  testWidgets('replacing borrowed close focus updates close visibility', (
    tester,
  ) async {
    final first = FocusNode();
    final next = FocusNode();
    addTearDown(first.dispose);
    addTearDown(next.dispose);
    Future<void> pump(FocusNode close) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SizedBox(
            width: 170,
            child: DDocumentTab(
              selected: false,
              closeFocusNode: close,
              onSelect: () {},
              onClose: () {},
              closeLabel: 'Close draft',
              child: const Text('Draft'),
            ),
          ),
        ),
      ),
    );
    double opacity() => tester
        .widget<AnimatedOpacity>(
          find
              .descendant(
                of: find.byType(DDocumentTab),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;

    await pump(first);
    expect(opacity(), 0);
    first.requestFocus();
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await pump(next);
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    next.requestFocus();
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(() => first.addListener(() {}), returnsNormally);
    expect(() => next.addListener(() {}), returnsNormally);
  });
}
