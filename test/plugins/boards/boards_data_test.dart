import 'package:discourse_native/src/plugins/boards/board_column_panel.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final enabled in [false, true]) {
    test('Boards settings retain value identity with enabled=$enabled', () {
      const codec = BoardsSettingsCodec();
      final original = BoardsSettings(enabled: enabled);
      final decoded = codec.decode({'enabled': enabled});

      expect(decoded.enabled, enabled);
      expect(codec.encode(decoded), {'enabled': enabled});
      expect(decoded, original);
      expect(decoded.hashCode, original.hashCode);
      expect(decoded, isNot(codec.decode({'enabled': !enabled})));
    });
  }

  test('directory metadata decodes creator, privacy and column icon', () {
    final board = BoardSnapshot.decode({
      'id': 1,
      'created_by': {
        'username': 'lee',
        'avatar_template': '/user_avatar/forum/lee/{size}/1.png',
      },
      'anonymous_can_read': false,
      'columns': [
        {'id': 10, 'title': 'Done', 'icon': 'check'},
      ],
    })!;
    expect(board.createdBy?.username, 'lee');
    expect(
      board.createdBy?.avatarTemplate,
      '/user_avatar/forum/lee/{size}/1.png',
    );
    expect(board.anonymousCanRead, isFalse);
    expect(board.columns.single.icon, 'check');
    expect(
      BoardSnapshot.decode({
        'id': 1,
        'anonymous_can_read': true,
      })!.anonymousCanRead,
      isTrue,
    );
  });

  test('missing or malformed directory metadata remains unknown', () {
    for (final creator in [
      null,
      'invalid',
      {'avatar_template': '/avatar.png'},
      {'username': 7},
    ]) {
      final board = BoardSnapshot.decode({
        'id': 1,
        'created_by': creator,
        'anonymous_can_read': 'false',
      })!;
      expect(board.createdBy, isNull);
      expect(board.anonymousCanRead, isNull);
    }
    final board = BoardSnapshot.decode({
      'id': 1,
      'columns': [
        {'id': 10},
      ],
    })!;
    expect(board.createdBy, isNull);
    expect(board.anonymousCanRead, isNull);
    expect(board.columns.single.icon, isEmpty);
  });
  test(
    'reader metadata uses recency and server actor/assignment fallbacks',
    () {
      final card = BoardCard.decode({
        'id': 1,
        'column_id': 2,
        'card_type': 'topic',
        'topic_id': 5,
        'recency_at': '2026-01-02T00:00:00Z',
        'topic': {
          'id': 5,
          'bumped_at': '2025-12-01T00:00:00Z',
          'last_poster': {
            'username': 'jane',
            'avatar_template': '/jane/{size}.png',
          },
          'all_assigned_users': [
            {'username': 'sam', 'avatar_template': '/sam/{size}.png'},
            {'username': 'lee'},
          ],
        },
      })!;
      expect(card.recencyAt, DateTime.utc(2026, 1, 2));
      expect(card.activityAt, DateTime.utc(2026, 1, 2));
      expect(card.activityUser?.username, 'jane');
      expect(card.assignees.map((user) => user.username), ['sam', 'lee']);
      final fallback = BoardCard.decode({
        'id': 2,
        'column_id': 2,
        'card_type': 'floater',
        'created_at': '2026-02-01T00:00:00Z',
        'created_by': {'username': 'author'},
        'assigned_to': {
          'username': 'owner',
          'avatar_template': '/owner/{size}.png',
        },
      })!;
      expect(fallback.recencyAt, isNull);
      expect(fallback.activityAt, DateTime.utc(2026, 2, 1));
      expect(fallback.activityUser?.username, 'author');
      expect(fallback.assignees.single.username, 'owner');
    },
  );

  test(
    'recency projection preserves server order and the seven-day boundary',
    () {
      final column = BoardColumn.decode({
        'id': 2,
        'default_sort': 'recency',
        'cards': [
          {
            'id': 1,
            'column_id': 2,
            'card_type': 'floater',
            'recency_at': '2026-01-10T00:00:00Z',
          },
          {
            'id': 2,
            'column_id': 2,
            'card_type': 'floater',
            'recency_at': '2026-01-02T23:59:59Z',
          },
          {
            'id': 3,
            'column_id': 2,
            'card_type': 'floater',
            'recency_at': '2026-01-03T00:00:00Z',
          },
          {
            'id': 4,
            'column_id': 2,
            'card_type': 'floater',
            'recency_at': 'invalid',
          },
        ],
      })!;
      final visible = boardColumnCards(column, now: DateTime.utc(2026, 1, 10));
      expect(visible.cards.map((card) => card.id), [1, 3]);
      expect(visible.hiddenCount, 2);
      final linked = boardColumnCards(
        column,
        now: DateTime.utc(2026, 1, 10),
        linkedCardIds: {4},
      );
      expect(linked.cards.map((card) => card.id), [1, 3, 4]);
      final expanded = boardColumnCards(
        column,
        now: DateTime.utc(2026, 1, 10),
        showOlder: true,
      );
      expect(expanded.cards.map((card) => card.id), [1, 2, 3, 4]);
      expect(expanded.hiddenCount, 0);
    },
  );
}
