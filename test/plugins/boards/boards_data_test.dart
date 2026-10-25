import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
