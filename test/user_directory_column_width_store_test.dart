import 'dart:convert';

import 'package:discourse_native/src/data/user_directory_column_width_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips widths independently for each forum', () async {
    final persistence = _MemoryPersistence();
    final store = UserDirectoryColumnWidthStore(persistence: persistence);

    await store.write(
      siteUrl: 'https://one.example',
      widths: UserDirectoryColumnWidths(const {
        'identity': 312,
        'metric.automatic.1': 184,
      }),
    );
    await store.write(
      siteUrl: 'https://two.example',
      widths: UserDirectoryColumnWidths(const {'identity': 220}),
    );

    expect((await store.read(siteUrl: 'https://one.example')).widths, {
      'identity': 312,
      'metric.automatic.1': 184,
    });
    expect((await store.read(siteUrl: 'https://two.example')).widths, {
      'identity': 220,
    });
  });

  test('ignores malformed and unsafe stored widths', () async {
    final persistence = _MemoryPersistence()
      ..values['https://example.com'] = jsonEncode({
        'version': 1,
        'widths': {
          'identity': 300,
          'too-small': 2,
          'too-large': 5000,
          'not-a-number': 'wide',
        },
      });
    final store = UserDirectoryColumnWidthStore(persistence: persistence);

    expect((await store.read(siteUrl: 'https://example.com')).widths, {
      'identity': 300,
    });

    persistence.values['https://example.com'] = '{broken';
    expect((await store.read(siteUrl: 'https://example.com')).isEmpty, isTrue);
  });
}

final class _MemoryPersistence implements UserDirectoryColumnWidthPersistence {
  final Map<String, String> values = {};

  @override
  Future<String?> readWidths({required String siteUrl}) async =>
      values[siteUrl];

  @override
  Future<bool> writeWidths({
    required String siteUrl,
    required String encoded,
  }) async {
    values[siteUrl] = encoded;
    return true;
  }
}
