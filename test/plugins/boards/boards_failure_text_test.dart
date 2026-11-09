import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/boards/boards_controller.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
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
          const SiteLookupException(
            SiteLookupFailure.unreachable,
            boardsSite,
            statusCode: 500,
          );
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
}
