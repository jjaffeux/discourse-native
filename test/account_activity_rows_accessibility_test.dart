import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an unread notification is a named 44 pixel keyboard target', (
    tester,
  ) async {
    var opens = 0;
    await _pumpRow(
      tester,
      NotificationRow(
        notification: const DiscourseNotification.test(
          id: 1,
          typeId: NotificationTypeId(2),
          title: 'A useful topic',
          data: {'display_username': 'sam'},
        ),
        onTap: () => opens++,
      ),
    );

    final row = find.byType(NotificationRow);
    final target = _target(row);
    final semantics = find.byKey(const ValueKey('notification-row-1'));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(semantics),
      isSemantics(
        label: 'sam replied to A useful topic, unread',
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    final focus = _focusTarget(tester, target);
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);
    expect(
      tester.getSemantics(semantics),
      isSemantics(isFocusable: true, isFocused: true),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opens, 1);
  });

  testWidgets('a bookmark and its note form one 44 pixel keyboard target', (
    tester,
  ) async {
    var opens = 0;
    await _pumpRow(
      tester,
      BookmarkRow(
        bookmark: const Bookmark(
          id: 2,
          author: 'alice',
          title: 'Saved topic',
          name: 'Read this later',
        ),
        onTap: () => opens++,
      ),
    );

    final row = find.byType(BookmarkRow);
    final target = _target(row);
    final semanticsTarget = find.byKey(const ValueKey('bookmark-row-2'));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    final semantics = tester.getSemantics(semanticsTarget);
    expect(
      semantics,
      isSemantics(
        label: 'alice, Saved topic, Note: Read this later',
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(
      semantics.getSemanticsData().tooltip,
      isEmpty,
      reason: 'the visual note tooltip is already part of the row name',
    );

    final focus = _focusTarget(tester, target);
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(opens, 1);
  });
}

Future<void> _pumpRow(WidgetTester tester, Widget row) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 320, child: row),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _target(Finder row) =>
    find.descendant(of: row, matching: find.byType(InkWell));

FocusNode _focusTarget(WidgetTester tester, Finder target) {
  expect(target, findsOneWidget);
  final focusChild = find
      .descendant(of: target, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  return focus;
}
