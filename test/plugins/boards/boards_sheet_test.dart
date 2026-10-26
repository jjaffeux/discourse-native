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
  int extraCards = 30,
  bool fromDirectory = true,
}) async {
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
  final board = boardFixtureJson(extraCards: extraCards);
  (board['board'] as Map)
    ..['name'] = name
    ..['tag_names'] = tags;
  final shell = await pumpMobileShellFixture(tester, size: size, board: board);
  if (!fromDirectory) {
    shell.pushContent(
      ContentRoute(
        destination: const ExtensionDestination('boards/1'),
        title: name,
        icon: boardsIcon,
      ),
    );
    await tester.pumpAndSettle();
    return shell;
  }
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
  expect(shell.currentContent?.id, 'boards/1');
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
    expect(sheet.right - next.left, 10);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('a phone swipe settles on one column at a time', (tester) async {
    await _openBoard(tester);
    final sheet = tester.getRect(_sheet);
    Finder column(int id) => find.byKey(ValueKey('board-column-$id'));
    double left(int id) => tester.getRect(column(id)).left - sheet.left;
    await tester.fling(column(10), const Offset(-120, 0), 1000);
    await tester.pumpAndSettle();
    expect(left(11), 12);
    // The last column rests against the trailing padding, showing the same
    // sliver of its predecessor that the first column shows of its successor.
    double right(int id) => sheet.right - tester.getRect(column(id)).right;
    await tester.fling(column(11), const Offset(-200, 0), 8000);
    await tester.pumpAndSettle();
    expect(right(12), 12);
    expect(left(12), 12 + 10);
    final hold = await tester.startGesture(tester.getCenter(column(12)));
    for (var step = 0; step < 10; step++) {
      await hold.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await hold.up();
    await tester.pumpAndSettle();
    expect(right(12), 12);
    await tester.fling(column(12), const Offset(120, 0), 1000);
    await tester.pumpAndSettle();
    expect(left(11), 12);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('a tablet sheet keeps several fixed-width columns in view', (
    tester,
  ) async {
    await _openBoard(tester, size: const Size(820, 1180));
    final column = find.byKey(const ValueKey('board-column-10'));
    final first = tester.getRect(column);
    final next = tester.getRect(find.byKey(const ValueKey('board-column-11')));
    expect(first.width, 300);
    expect(next.right, lessThan(tester.getRect(_sheet).right));
    await tester.timedDrag(
      column,
      const Offset(-100, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(column).left,
      inExclusiveRange(first.left - 312 + 20, first.left - 20),
    );
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

  testWidgets('a board that fits keeps its header still', (tester) async {
    await _openBoard(tester);
    final title = tester.getRect(_title);
    await tester.drag(_title, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(_title), title);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  for (final (size, scale) in [
    (const Size(320, 700), 1.0),
    (const Size(320, 700), 2.0),
    (const Size(390, 844), 1.5),
    (const Size(390, 844), 2.0),
    (const Size(844, 390), 1.0),
    (const Size(844, 390), 2.0),
  ]) {
    testWidgets(
      'a ${size.width.round()}x${size.height.round()} board at ${scale}x text '
      'reaches every column footer',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _openBoard(
          tester,
          size: size,
          name: 'Quarterly product roadmap for the native apps',
          tags: ['roadmap', 'native', 'ios', 'android'],
          extraCards: 3,
          fromDirectory: false,
        );
        expect(tester.takeException(), isNull);
        final sheet = tester.getRect(_sheet);
        final dock = tester.getRect(_dock);
        // The title's top stays clear of the dock even where the sheet is
        // short; its centre can sit under the dock on a landscape phone.
        await tester.dragFrom(
          tester.getTopLeft(_title) + const Offset(20, 10),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        for (final id in [10, 11]) {
          final add = find.byKey(ValueKey('board-add-$id'));
          await tester.ensureVisible(add);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(add);
          expect(bounds.top, greaterThanOrEqualTo(sheet.top));
          expect(bounds.bottom, lessThanOrEqualTo(dock.top));
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }
}
