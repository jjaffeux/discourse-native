import 'package:discourse_native/src/models/json.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('numeric directory values from wire data', () {
    const column = UserDirectoryColumn(
      id: 1,
      name: 'time_read',
      type: UserDirectoryColumnType.automatic,
      position: 1,
    );
    final bounded = '123'.padLeft(maximumJsonIntegerCodeUnits, '0');
    for (final (value, expected) in <(Object?, num?)>[
      (123, 123),
      (12.5, 12.5),
      ('123', 123),
      ('-12.5', -12.5),
      (' 123 ', 123),
      ('1e3', 1000),
      ('1e300', 1e300),
      (bounded, 123),
      ('0$bounded', null),
      ('NaN', null),
      ('Infinity', null),
      ('-Infinity', null),
      ('1e999', null),
      (double.nan, null),
      (double.infinity, null),
      (double.negativeInfinity, null),
      ('not a number', null),
      (null, null),
    ]) {
      test(
        'accepts only finite bounded numeric ${value is String ? 'text' : 'values'}: $value',
        () {
          final item = UserDirectoryItem.fromWire({
            'user': const {'id': 1, 'username': 'sam'},
            column.name: value,
          }, 'https://example.com');

          expect(item.numericValueFor(column), expected);
          expect(item.valueFor(column), same(value));
        },
      );
    }
  });

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

  test('decodes the complete editable column configuration', () {
    final metadata = UserDirectoryMetadata.fromColumns(const {
      'directory_columns': [
        {
          'id': 1,
          'name': 'likes_received',
          'type': 'automatic',
          'position': 1,
          'enabled': true,
        },
        {
          'id': 9,
          'name': 'solutions',
          'type': 'plugin',
          'position': 2,
          'enabled': false,
        },
        {
          'id': 14,
          'name': 'GitHub Username',
          'type': 'user_field',
          'position': 3,
          'user_field_id': 42,
          'enabled': false,
        },
      ],
    }, editable: true);

    expect(metadata.canManageColumns, isTrue);
    expect(metadata.columns.map((column) => column.name), ['likes_received']);
    expect(metadata.availableColumns.map((column) => column.name), [
      'likes_received',
      'solutions',
      'GitHub Username',
    ]);
    final configured = metadata.availableColumns.last.copyWith(
      enabled: true,
      position: 2,
    );
    expect(configured.userFieldId, 42);
    expect(configured.toConfigurationWire(), {
      'id': 14,
      'enabled': true,
      'position': 2,
    });
  });
}
