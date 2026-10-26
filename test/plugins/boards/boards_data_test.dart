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

  test('Boards settings decode fails closed without an explicit true', () {
    const codec = BoardsSettingsCodec();
    for (final value in [
      null,
      'enabled',
      <String, Object?>{},
      {'enabled': 1},
    ]) {
      expect(codec.decode(value).enabled, isFalse);
    }
  });

  test('cards decode only with positive identity in their own column', () {
    final column = BoardColumn.decode({
      'id': 2,
      'cards': [
        {'id': 1, 'column_id': 2, 'card_type': 'floater'},
        {'id': 0, 'column_id': 2, 'card_type': 'floater'},
        {'id': 3, 'column_id': 9, 'card_type': 'floater'},
        {
          'id': 4,
          'column_id': 2,
          'card_type': 'topic',
          'topic_id': 5,
          'topic': {'id': 6, 'title': 'Other topic'},
        },
      ],
    })!;
    expect(column.cards.map((card) => card.id), [1]);
  });

  test('archived boards are neither writable nor manageable', () {
    final board = BoardSnapshot.decode({
      'id': 1,
      'can_write': true,
      'can_manage': true,
      'archived': true,
    })!;
    expect(board.canWrite, isFalse);
    expect(board.canManage, isFalse);
  });

  test('constraint repairs send only the fields they fix', () {
    expect(const BoardConstraintCheck().needsRepair, isFalse);
    expect(const BoardConstraintCheck(categoryIds: [5]).needsRepair, isTrue);
    expect(const BoardRepair(categoryId: 5).json, {'category_id': 5});
    expect(const BoardRepair().json, isEmpty);
  });

  test('a drop places a card by its slot and leaves it alone on its own', () {
    Map<String, Object?> floater(int id, int column) => {
      'id': id,
      'column_id': column,
      'card_type': 'floater',
    };
    final board = BoardSnapshot.decode({
      'id': 1,
      'columns': [
        {
          'id': 10,
          'cards': [floater(1, 10), floater(2, 10), floater(3, 10)],
        },
        {'id': 11, 'cards': <Object?>[]},
        {
          'id': 12,
          'default_sort': 'recency',
          'cards': [floater(4, 12)],
        },
        {'id': 13, 'default_sort': 'alphabetical', 'cards': <Object?>[]},
      ],
    })!;
    final priority = board.column(10)!;
    final empty = board.column(11)!;
    final recency = board.column(12)!;
    final middle = board.card(2)!;
    Matcher after(int cardId) => isA<PlaceAfter>().having(
      (placement) => placement.cardId,
      'cardId',
      cardId,
    );
    expect(boardDropPlacement(middle, priority, 1), isNull);
    expect(boardDropPlacement(middle, priority, 0), isA<PlaceFirst>());
    expect(boardDropPlacement(middle, priority, 2), after(3));
    expect(boardDropPlacement(middle, priority, 9), after(3));
    final first = board.card(1)!;
    expect(boardDropPlacement(first, priority, 0), isNull);
    expect(boardDropPlacement(first, priority, 1), after(2));
    final top = boardDropPlacement(middle, empty, 0)!;
    expect(top, isA<PlaceFirst>());
    expect(boardPlacement(board, middle, empty, top), {'after_card_id': null});
    expect(boardDropPlacement(middle, recency, 0), isA<PlaceLast>());
    expect(boardDropPlacement(board.card(4)!, recency, 0), isNull);
    expect(boardDropPlacement(middle, board.column(13)!, 0), isNull);
  });

  test('memberships prefer the unicode board and column titles', () {
    final membership = BoardMemberships.decode([
      {
        'board_id': 1,
        'board_name': 'Roadmap',
        'unicode_board_name': 'Roadmap 🚀',
        'cards': [
          {
            'card_id': 10,
            'column_title': 'Done',
            'unicode_column_title': 'Done ✅',
          },
        ],
      },
    ]).values.single;
    expect(membership.name, 'Roadmap 🚀');
    expect(membership.columnTitle, 'Done ✅');
  });

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
