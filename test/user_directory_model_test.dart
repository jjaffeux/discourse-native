import 'package:discourse_native/src/models/user_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes dynamic columns, directory values, and public user fields', () {
    final metadata = UserDirectoryMetadata.fromColumns(
      const {
        'directory_columns': [
          {
            'id': 2,
            'name': 'Team',
            'type': 'user_field',
            'position': 2,
            'user_field_id': 7,
          },
          {
            'id': 1,
            'name': 'likes_received',
            'type': 'automatic',
            'position': 1,
            'icon': 'heart',
          },
        ],
      },
      groupNames: const ['staff', 'design', 'staff'],
    );

    expect(metadata.columns.map((column) => column.name), [
      'likes_received',
      'Team',
    ]);
    expect(metadata.columns.first.label, 'Likes received');
    expect(metadata.groupNames, ['design', 'staff']);

    final page = UserDirectoryPage.fromWire(const {
      'directory_items': [
        {
          'id': 42,
          'likes_received': 290,
          'user': {
            'id': 42,
            'username': 'sam',
            'name': 'Sam Saffron',
            'avatar_template': '/user_avatar/example.com/sam/{size}/1.png',
            'primary_group_name': 'staff',
            'user_fields': {
              '7': {
                'value': ['Core', 'Performance'],
                'searchable': true,
              },
            },
          },
        },
      ],
      'meta': {
        'total_rows_directory_items': 87,
        'last_updated_at': '2026-09-04T07:06:00.000Z',
        'load_more_directory_items':
            '/directory_items.json?period=weekly&page=1',
      },
    }, 'https://example.com');

    final item = page.items.single;
    expect(item.user.username, 'sam');
    expect(
      item.user.avatarUrl,
      'https://example.com/user_avatar/example.com/sam/90/1.png',
    );
    expect(item.numericValueFor(metadata.columns.first), 290);
    expect(item.valueFor(metadata.columns.last), ['Core', 'Performance']);
    expect(page.totalRows, 87);
    expect(page.lastUpdatedAt, DateTime.utc(2026, 9, 4, 7, 6));
    expect(page.nextPagePath, contains('page=1'));
  });

  test('rejects malformed users without discarding valid column metadata', () {
    expect(
      () => UserDirectoryPage.fromWire(const {
        'directory_items': [
          {
            'id': 1,
            'user': {'id': 1},
          },
        ],
      }, 'https://example.com'),
      throwsFormatException,
    );

    final metadata = UserDirectoryMetadata.fromColumns(const {
      'directory_columns': [
        {'id': 1, 'position': 1},
        {'id': 2, 'name': 'post_count', 'type': 0, 'position': 2},
      ],
    });
    expect(metadata.columns.single.name, 'post_count');
  });
}
