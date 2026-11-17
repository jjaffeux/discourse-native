import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/shell/mobile_scroll_dock.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_sheet_scroll_fixture.dart';

const _phones = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.iOS,
});

const _topic = Topic(
  id: 7,
  title: 'Reading a rich discussion in a sheet',
  slug: 'topic-7',
);

/// Elements that existed before recording started and were built again,
/// with the widget each was built from.
List<(Element, Widget)> _recordRebuilds(WidgetTester tester) {
  final known = Set<Element>.identity()..addAll(tester.allElements);
  final rebuilt = <(Element, Widget)>[];
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    if (!known.add(element)) rebuilt.add((element, element.widget));
  };
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  return rebuilt;
}

bool _within(Element element, Element ancestor) {
  if (identical(element, ancestor)) return true;
  if (!element.mounted) return false;
  var found = false;
  element.visitAncestorElements((candidate) {
    found = identical(candidate, ancestor);
    return !found;
  });
  return found;
}

/// The row a topic list builds for [topicId], beneath the selection that
/// every row re-reads as the open topic changes. The row keeps its widget, and
/// is not rebuilt, unless the list itself rebuilds.
Element _rowContent(WidgetTester tester, int topicId) {
  final row = find.descendant(
    of: find.byType(TopicListView),
    matching: find.byKey(ValueKey(topicId)),
  );
  final content = tester.widget<ListenableBuilder>(row).child!;
  return tester.element(
    find.descendant(of: row, matching: find.byWidget(content)),
  );
}

int _rebuildsOf<T extends Widget>(List<(Element, Widget)> rebuilt) =>
    rebuilt.where((rebuild) => rebuild.$2 is T).length;

void main() {
  testWidgets('Back and Forward swipe frames leave the dock alone', (
    tester,
  ) async {
    final shell = await pumpTopicSheetScrollFixture(tester);
    final frame = find.byKey(const ValueKey('mobile-root'));
    final bounds = tester.getRect(frame);
    final rebuilt = _recordRebuilds(tester);

    for (final back in [true, false]) {
      final direction = back ? 1.0 : -1.0;
      final gesture = await tester.startGesture(
        Offset(back ? bounds.left + 5 : bounds.right - 5, bounds.center.dy),
      );
      await gesture.moveBy(Offset(direction * 80, 0));
      await tester.pump();
      final livePage = find.byKey(const ValueKey('mobile-content-panel'));
      final initialOffset = tester.getTopLeft(livePage).dx;
      rebuilt.clear();
      for (var frame = 0; frame < 8; frame++) {
        await gesture.moveBy(Offset(direction * 8, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getTopLeft(livePage).dx, isNot(initialOffset));
      expect(_rebuildsOf<MobileScrollDock>(rebuilt), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shell.currentContent?.isTopic, !back);
    }
  }, variant: _phones);

  // Android keeps the list in the topic sheet's source slot. iOS moves the
  // list beneath each topic sheet, which rebuilds it as it moves.
  testWidgets(
    'opening a topic on Android redraws only the list rows whose selection '
    'changes',
    (tester) async {
      final shell = await pumpTopicSheetScrollFixture(tester);
      shell.handleBack();
      await tester.pumpAndSettle();
      final rows = {
        for (var id = 1; id <= 8; id++) id: _rowContent(tester, id),
      };
      final rebuilt = _recordRebuilds(tester);

      shell.openTopic(_topic);
      await tester.pumpAndSettle();

      expect(
        rebuilt.where(
          (rebuild) => rows.values.any((row) => identical(rebuild.$1, row)),
        ),
        isEmpty,
        reason: 'the list does not rebuild its rows',
      );
      final reselected = {
        for (final MapEntry(key: id, value: row) in rows.entries)
          if (rebuilt.any(
            (rebuild) =>
                rebuild.$2 is ForumTabSelector && _within(rebuild.$1, row),
          ))
            id,
      };
      expect(reselected, {6, 7, 8});
      expect(_rebuildsOf<ChatMobileSidebar>(rebuilt), 0);

      rebuilt.clear();
      shell.handleBack();
      await tester.pumpAndSettle();
      expect(_rebuildsOf<ChatMobileSidebar>(rebuilt), 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a menu sheet over a topic leaves the reader and the page frame alone',
    (tester) async {
      await pumpTopicSheetScrollFixture(tester);
      final rebuilt = _recordRebuilds(tester);

      await tester.tap(find.byKey(const ValueKey('topic-more-actions')));
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsWidgets);
      expect(_rebuildsOf<TopicView>(rebuilt), 0);
      expect(_rebuildsOf<DHistoryTransition>(rebuilt), 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_rebuildsOf<TopicView>(rebuilt), 0);
      expect(_rebuildsOf<DHistoryTransition>(rebuilt), 0);
    },
    variant: _phones,
  );
}
