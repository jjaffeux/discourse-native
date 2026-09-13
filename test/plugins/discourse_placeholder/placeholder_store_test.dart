import 'dart:io';

import 'package:discourse_native/src/plugins/discourse_placeholder/placeholder_store.dart';
import 'package:flutter_test/flutter_test.dart';

const post = (siteUrl: 'https://example.com', userId: 1, topicId: 2, postId: 3);

void main() {
  late Directory directory;
  late File file;
  late DateTime now;
  late PlaceholderStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'placeholder-store-test-',
    );
    file = File('${directory.path}/values.json');
    now = DateTime.utc(2026, 9, 13);
    store = PlaceholderStore(file: file, now: () => now);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'restores across restart with private permissions and sliding seven-day expiry',
    () async {
      await store.write(post, 'HOST', 'secret-host');
      expect((await file.stat()).mode & 0x1ff, 0x180);
      now = now.add(const Duration(days: 6));
      final restarted = PlaceholderStore(file: file, now: () => now);
      expect(await restarted.read(post), {'HOST': 'secret-host'});
      now = now.add(const Duration(days: 6));
      expect(await restarted.read(post), {'HOST': 'secret-host'});
      now = now.add(const Duration(days: 7));
      expect(await restarted.read(post), isEmpty);
      expect(await file.readAsString(), isNot(contains('secret-host')));
    },
  );

  test(
    'isolates account, site, topic, post and key; reset and forget are scoped',
    () async {
      const identities = [
        post,
        (siteUrl: 'https://example.com', userId: 9, topicId: 2, postId: 3),
        (siteUrl: 'https://other.com', userId: 1, topicId: 2, postId: 3),
        (siteUrl: 'https://example.com', userId: 1, topicId: 8, postId: 3),
        (siteUrl: 'https://example.com', userId: 1, topicId: 2, postId: 8),
        (siteUrl: 'https://example.com', userId: null, topicId: 2, postId: 3),
      ];
      await Future.wait([
        for (var i = 0; i < identities.length; i++)
          store.write(identities[i], 'X', '$i'),
      ]);
      await store.write(post, 'Y', 'kept');
      for (var i = 0; i < identities.length; i++) {
        expect((await store.read(identities[i]))['X'], '$i');
      }
      await store.write(post, 'X', null);
      expect(await store.read(post), {'Y': 'kept'});
      await store.forget(post.siteUrl);
      for (final id in identities) {
        expect(
          await store.read(id),
          id.siteUrl == 'https://other.com' ? {'X': '2'} : isEmpty,
        );
      }
    },
  );

  test('corrupt documents recover without preventing new values', () async {
    await file.writeAsString('{corrupt');
    expect(await store.read(post), isEmpty);
    await store.write(post, 'X', 'restored');
    expect(await store.read(post), {'X': 'restored'});
  });

  test('storage failure degrades to empty values', () async {
    final broken = PlaceholderStore(file: File('${file.path}/child'));
    await file.writeAsString('not a directory');
    expect(await broken.read(post), isEmpty);
    await broken.write(post, 'X', 'value');
    await broken.forget(post.siteUrl);
  });
}
