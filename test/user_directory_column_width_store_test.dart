import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/site_preference_keys.dart';
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

  test(
    'retirement spans shared stores and preserves fresh write ordering',
    () async {
      final persistence = _HeldPersistence();
      final first = UserDirectoryColumnWidthStore(persistence: persistence);
      final replacement = UserDirectoryColumnWidthStore(
        persistence: persistence,
      );
      const site = 'https://meta.discourse.org';
      const other = 'https://team.discourse.org';
      final write = first.write(siteUrl: site, widths: _widths(220));
      await persistence.writeStarted.future;
      final queued = replacement.write(siteUrl: site, widths: _widths(260));
      final oldRead = replacement.read(siteUrl: site);
      first.forgetSites(ForgottenSites.removed(site, keeping: const [other]));
      persistence.values.remove(site);
      await first.write(siteUrl: other, widths: _widths(240));
      final fresh = replacement.write(siteUrl: site, widths: _widths(300));
      persistence.releaseWrite.complete();
      await Future.wait([write, queued, fresh]);
      expect((await oldRead).isEmpty, isTrue);
      expect(persistence.writes, [
        (site, 220.0),
        (other, 240.0),
        (site, 300.0),
      ]);
      expect((await first.read(siteUrl: site))['identity'], 300);
      expect((await replacement.read(siteUrl: other))['identity'], 240);
    },
  );

  test('a pending read cannot restore forgotten widths', () async {
    final persistence = _HeldPersistence()..holdRead = true;
    const site = 'https://meta.discourse.org';
    persistence.values[site] = _widths(280).encode();
    final first = UserDirectoryColumnWidthStore(persistence: persistence);
    final replacement = UserDirectoryColumnWidthStore(persistence: persistence);
    final oldRead = first.read(siteUrl: site);
    await persistence.readStarted.future;
    replacement.forgetSites(ForgottenSites.removed(site, keeping: const []));
    persistence.values.remove(site);
    expect((await replacement.read(siteUrl: site)).isEmpty, isTrue);
    persistence.releaseRead.complete();
    expect((await oldRead).isEmpty, isTrue);
  });
}

UserDirectoryColumnWidths _widths(double identity) =>
    UserDirectoryColumnWidths({'identity': identity});

final class _HeldPersistence implements UserDirectoryColumnWidthPersistence {
  final values = <String, String>{};
  final writes = <(String, double?)>[];
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  bool holdRead = false;

  @override
  Future<String?> readWidths({required String siteUrl}) async {
    final value = values[siteUrl];
    if (holdRead && !readStarted.isCompleted) {
      readStarted.complete();
      await releaseRead.future;
    }
    return value;
  }

  @override
  Future<bool> writeWidths({
    required String siteUrl,
    required String encoded,
  }) async {
    writes.add((
      siteUrl,
      UserDirectoryColumnWidths.decode(encoded)['identity'],
    ));
    values[siteUrl] = encoded;
    if (!writeStarted.isCompleted) {
      writeStarted.complete();
      await releaseWrite.future;
    }
    return true;
  }
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
