import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('press and drag select entries once and release scrubbing', (
    tester,
  ) async {
    final selected = <String>[];
    final scrubs = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: DAlphabetIndex<String>(
              entries: const [
                DAlphabetIndexEntry(value: 'bookmarks', label: 'B'),
                DAlphabetIndexEntry(value: 'categories', label: 'C'),
                DAlphabetIndexEntry(value: 'users', label: 'U'),
              ],
              onSelected: selected.add,
              onScrubChanged: scrubs.add,
            ),
          ),
        ),
      ),
    );
    final index = find.byType(DAlphabetIndex<String>);
    final bounds = tester.getRect(index);
    // Padding outside the painted index does not select a letter.
    await tester.tapAt(Offset(bounds.left - 4, bounds.top + 10));
    expect(selected, isEmpty);
    final gesture = await tester.startGesture(
      Offset(bounds.center.dx, bounds.top + 10),
    );
    await tester.pump();
    await gesture.moveTo(Offset(bounds.center.dx, bounds.top + 30));
    await tester.pump();
    await gesture.moveTo(Offset(bounds.center.dx, bounds.top + 35));
    await tester.pump();
    await gesture.moveTo(Offset(bounds.center.dx, bounds.bottom + 50));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(selected, ['bookmarks', 'categories', 'users']);
    expect(scrubs, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard navigation and semantic activation work at large text in RTL',
    (tester) async {
      final selected = <String>[];
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Center(
                  child: DAlphabetIndex<String>(
                    entries: const [
                      DAlphabetIndexEntry(value: 'bookmarks', label: 'B'),
                      DAlphabetIndexEntry(value: 'categories', label: 'C'),
                      DAlphabetIndexEntry(value: 'users', label: 'U'),
                    ],
                    onSelected: selected.add,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(selected, ['users', 'categories', 'bookmarks']);
      final node = tester.getSemantics(find.bySemanticsLabel('C'));
      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(selected.last, 'categories');
      expect(tester.getSize(find.byType(DAlphabetIndex<String>)).height, 120);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets('changing entries during a drag releases list interaction', (
    tester,
  ) async {
    final scrubs = <bool>[];
    var entries = const [DAlphabetIndexEntry(value: 'groups', label: 'G')];
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: DAlphabetIndex<String>(
                  entries: entries,
                  onSelected: (_) {},
                  onScrubChanged: scrubs.add,
                ),
              );
            },
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(tester.getCenter(find.text('G')));
    await tester.pump();
    update(() => entries = const []);
    await tester.pump();
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(scrubs, [true, false]);
    expect(tester.takeException(), isNull);
  });
}
