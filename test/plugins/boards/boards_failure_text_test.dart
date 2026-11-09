import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/boards/boards_controller.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/plugins/boards/boards_navigation.dart';
import 'package:discourse_native/src/plugins/boards/boards_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/boards_fixture.dart';

final _leaks = RegExp(r'Exception|Failure|statusCode|retryAfter');

Future<BoardWriteResult> _move(BoardHandle handle) => handle.move(
  101,
  11,
  const PlaceFirst(),
  review: (_, _, _) async => const BoardRepair(),
);

void main() {
  test(
    'a failed board read or move shows its reason, not a type name',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();

      final shown = <String, String?>{};

      fixture.transport.failures['GET /boards/api/boards/1.json'] =
          const SiteLookupException(SiteLookupFailure.unreachable, boardsSite);
      await handle.refresh();
      shown['read unreachable'] = handle.error;

      fixture.transport.failures['GET /boards/api/boards/1.json'] =
          const SiteLookupException(
            SiteLookupFailure.notDiscourse,
            boardsSite,
            statusCode: 403,
          );
      await handle.refresh();
      shown['read forbidden'] = handle.error;

      fixture.transport.failures.remove('GET /boards/api/boards/1.json');
      await handle.refresh();
      expect(handle.snapshot, isNotNull);

      fixture.transport.failures['PUT /boards/api/boards/1/cards/101'] =
          const WriteException(
            WriteFailure.validation,
            errors: ['Column is full'],
            statusCode: 422,
          );
      final moved = await _move(handle);
      shown['move validation'] = moved.error;
      expect(moved.state, BoardWriteState.refused);

      fixture.transport.failures.remove('PUT /boards/api/boards/1/cards/101');
      fixture
              .transport
              .failures['PUT /boards/api/boards/1/check-constraint-mismatches'] =
          const WriteException(WriteFailure.rateLimited, statusCode: 429);
      final checked = await _move(handle);
      shown['move constraints'] = checked.error;

      final raw = shown.entries.where(
        (entry) => _leaks.hasMatch(entry.value ?? ''),
      );
      // ignore: avoid_print
      print('PERF_PROOF failure-text-owner raw_type_names_shown=${raw.length}');
      expect(raw, isEmpty, reason: '$shown');
      expect(shown, {
        'read unreachable': "Couldn't reach $boardsSite.",
        'read forbidden': isNot(contains('not a Discourse forum')),
        'move validation': 'Column is full',
        'move constraints': isNotNull,
      });
    },
  );

  test('a board the site answered for is not called unreachable', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();

    final shown = <int, String?>{};
    for (final status in [500, 404]) {
      fixture.transport.failures['GET /boards/api/boards/1.json'] =
          SiteLookupException(
            SiteLookupFailure.unreachable,
            boardsSite,
            statusCode: status,
          );
      await handle.refresh();
      shown[status] = handle.error;
    }

    expect(handle.snapshot, isNull, reason: 'a 404 withdraws a deleted board');
    expect(shown, {
      500: "Couldn't load this board.",
      404: "Couldn't load this board.",
    });
  });

  testWidgets('a move sent without an answer says its result is unknown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    fixture.transport.failures['PUT /boards/api/boards/1/cards/102'] =
        const WriteException(WriteFailure.unreachable);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => DToaster(child: child!),
        home: Scaffold(
          body: BoardsPage(
            site: boardsSite,
            route: const BoardsRoute(boardId: 1),
            controller: fixture.controller,
            navigation: fixture.navigation,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.ancestor(
      of: find.text('Write release notes'),
      matching: find.byType(DItem),
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byType(DDropdownMenuTrigger)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(DDialogContent),
            matching: find.byType(DSelect<int>),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('In progress').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DButton, 'Move').last);
    await tester.pumpAndSettle();

    expect(
      fixture.transport.writes.map((write) => write.path),
      contains('/boards/api/boards/1/cards/102'),
    );
    expect(
      find.descendant(
        of: find.byType(DToaster),
        matching: find.textContaining('result is unknown'),
      ),
      findsOneWidget,
    );
    expect(find.text("Couldn't reach the site."), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
