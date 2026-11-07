import 'package:discourse_native/src/plugins/chat/chat_deletion_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unrecognized and incomplete single deliveries do not sample the clock',
    () {
      DateTime unexpectedClock() => throw StateError('unexpected fallback');
      expect(
        ChatDeletionEvent.decode({'type': 'edit'}, clock: unexpectedClock),
        isNull,
      );
      expect(
        ChatDeletionEvent.decode({
          'type': 'delete',
          'deleted_id': 'bad',
        }, clock: unexpectedClock),
        isNull,
      );
    },
  );

  test('bulk deletion snapshots IDs and retains one server timestamp', () {
    final ids = <Object?>[1, '2', null, 'bad', 1];
    final event =
        ChatDeletionEvent.decode({
              'type': 'bulk_delete',
              'deleted_ids': ids,
              'deleted_at': '2026-08-12T10:00:00Z',
              'deleted_by_id': '7',
            }, clock: () => throw StateError('server timestamp must win'))!
            as ChatMessagesDeleted;
    ids.clear();
    expect(event.messageIds, [1, 2, 1]);
    expect(event.deletedAt, DateTime.utc(2026, 8, 12, 10));
    expect(event.deletedById, 7);
    expect(() => event.messageIds.add(3), throwsUnsupportedError);
  });
}
