import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/plugins/boards/boards_navigation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../mobile_shell_test.dart' show pumpMobileShellFixture;
import '../../support/boards_fixture.dart';

final _sheet = find.byType(DSheetContent);
final _dock = find.byKey(const ValueKey('mobile-bottom-bar'));
final _title = find.byKey(const ValueKey('board-title'));

Future<ShellController> _openBoard(
  WidgetTester tester, {
  String name = 'Product roadmap',
  List<String> tags = const ['roadmap'],
  Size size = const Size(390, 844),
}) async {
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
  final board = boardFixtureJson(extraCards: 30);
  (board['board'] as Map)
    ..['name'] = name
    ..['tag_names'] = tags;
  final shell = await pumpMobileShellFixture(tester, size: size, board: board);
  shell.pushContent(
    const ContentRoute(
      destination: ExtensionDestination('boards'),
      title: 'Boards',
      icon: boardsIcon,
    ),
  );
  await tester.pumpAndSettle();
  expect(_sheet, findsNothing);
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  return shell;
}

void main() {
  const platforms = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  });

  testWidgets('a board opens from the directory as a page sheet', (
    tester,
  ) async {
    final shell = await _openBoard(tester);
    expect(shell.currentContent?.id, 'boards/1');
    expect(tester.widget<DSheetContent>(_sheet).variant, DSheetVariant.page);
    expect(find.descendant(of: _sheet, matching: _title), findsOneWidget);
    final pull = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
    );
    await pull.moveBy(const Offset(0, 20));
    await pull.moveBy(const Offset(0, 220));
    await pull.up();
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'boards');
    expect(_sheet, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('the sheet header keeps tags and actions beside the title', (
    tester,
  ) async {
    await _openBoard(tester, name: 'Board');
    expect(find.byKey(const ValueKey('board-back')), findsNothing);
    final title = tester.getRect(_title);
    for (final control in [
      find.text('# roadmap'),
      find.byKey(const ValueKey('board-controls')),
    ]) {
      final bounds = tester.getRect(control);
      expect(bounds.left, greaterThan(title.right));
      expect(bounds.center.dy, inInclusiveRange(title.top, title.bottom));
    }
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('the sheet header wraps tags and actions below a long title', (
    tester,
  ) async {
    await _openBoard(
      tester,
      name: 'Quarterly product roadmap for the native apps',
      tags: ['roadmap', 'native'],
    );
    final title = tester.getRect(_title);
    final roadmap = tester.getRect(find.text('# roadmap'));
    final native = tester.getRect(find.text('# native'));
    final menu = tester.getRect(find.byKey(const ValueKey('board-controls')));
    expect(roadmap.top, greaterThanOrEqualTo(title.bottom));
    expect(native.center.dy, roadmap.center.dy);
    expect(menu.center.dy, roadmap.center.dy);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('a column fills the sheet and hints at the next one', (
    tester,
  ) async {
    await _openBoard(tester);
    final sheet = tester.getRect(_sheet);
    final first = tester.getRect(find.byKey(const ValueKey('board-column-10')));
    final next = tester.getRect(find.byKey(const ValueKey('board-column-11')));
    expect(first.left - sheet.left, 12);
    expect(next.left - first.right, 12);
    expect(sheet.right - next.left, 5);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('a tablet sheet keeps several fixed-width columns in view', (
    tester,
  ) async {
    await _openBoard(tester, size: const Size(820, 1180));
    final first = tester.getRect(find.byKey(const ValueKey('board-column-10')));
    final next = tester.getRect(find.byKey(const ValueKey('board-column-11')));
    expect(first.width, 300);
    expect(next.right, lessThan(tester.getRect(_sheet).right));
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('board columns scroll to their last card above the dock', (
    tester,
  ) async {
    await _openBoard(tester);
    final dock = tester.getRect(_dock);
    final add = find.byKey(const ValueKey('board-add-10'));
    expect(tester.getRect(add).bottom, lessThanOrEqualTo(dock.top));
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const PageStorageKey('board-column-list-10')),
      ),
    );
    for (var step = 0; step < 80; step++) {
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final last = find.ancestor(
      of: find.text('Task 30'),
      matching: find.byType(DItem),
    );
    expect(tester.getRect(_dock), dock);
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(dock.top));
    expect(tester.getRect(add).bottom, lessThanOrEqualTo(dock.top));
    expect(tester.takeException(), isNull);
  }, variant: platforms);
}
