import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/content_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.example';
const _otherSite = 'https://other.example/forum';
const _alice = 'id:1';
const _bob = 'id:2';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'discourse-native-content-snapshot-test-',
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  // An hour keeps the debounce out of every test that does not ask for it:
  // nothing reaches the disk until `flush`.
  ContentSnapshotStore open({
    ContentSnapshotLimits limits = const ContentSnapshotLimits(),
    Duration writeDelay = const Duration(hours: 1),
  }) => ContentSnapshotStore(
    directory: () => directory,
    limits: limits,
    writeDelay: writeDelay,
  );

  File fileFor(String siteUrl) =>
      File('${directory.path}/${Uri.encodeComponent(siteUrl)}.json');

  void saveFeed(
    ContentSnapshotStore store,
    String destination,
    String wire, {
    String siteUrl = _site,
    String account = _alice,
    String path = '/latest.json',
  }) => store.saveFeed(
    siteUrl,
    account,
    destination,
    path,
    wire: wire,
    bytes: utf8.encode(wire).length,
  );

  void saveTopic(
    ContentSnapshotStore store,
    int id,
    String wire, {
    String account = _alice,
  }) => store.saveTopic(
    _site,
    account,
    id,
    wire: wire,
    bytes: utf8.encode(wire).length,
  );

  group('round trip', () {
    test('a later launch reads back what this one saved', () async {
      final first = open();
      saveFeed(first, 'latest', '{"topic_list":"é ☃"}');
      saveTopic(first, 7, '{"id":7}');
      await first.flush();

      final second = open();
      expect(
        await second.readFeed(_site, _alice, 'latest', '/latest.json'),
        '{"topic_list":"é ☃"}',
      );
      expect(await second.readTopic(_site, _alice, 7), '{"id":7}');
      expect(await second.readTopic(_site, _alice, 8), isNull);
    });

    test('a list saved for another path is not this list', () async {
      final first = open();
      saveFeed(first, 'category-4', '{"a":1}', path: '/c/4/l/latest.json');
      await first.flush();

      final second = open();
      expect(
        await second.readFeed(_site, _alice, 'category-4', '/c/4/l/top.json'),
        isNull,
      );
    });

    test('a save is readable before it is written', () async {
      final store = open();
      saveTopic(store, 7, '{"id":7}');

      expect(await store.readTopic(_site, _alice, 7), '{"id":7}');
      expect(await fileFor(_site).exists(), isFalse);
    });

    test(
      'the first save of a launch keeps the entries already on disk',
      () async {
        final first = open();
        saveFeed(first, 'latest', '{"a":1}');
        saveTopic(first, 7, '{"id":7}');
        await first.flush();

        // Saved before anything was read: the response that wins the race with
        // hydration must not commit alone.
        final second = open();
        saveTopic(second, 8, '{"id":8}');
        await second.flush();

        final third = open();
        expect(
          await third.readFeed(_site, _alice, 'latest', '/latest.json'),
          '{"a":1}',
        );
        expect(await third.readTopic(_site, _alice, 7), '{"id":7}');
        expect(await third.readTopic(_site, _alice, 8), '{"id":8}');
      },
    );

    test('the file and its directory are owner-only', () async {
      final store = open();
      saveTopic(store, 7, '{"id":7}');
      await store.flush();

      expect((await fileFor(_site).stat()).mode & 0x1ff, 0x180); // 0600
      expect((await directory.stat()).mode & 0x1ff, 0x1c0); // 0700
    }, skip: Platform.isWindows);
  });

  group('writes', () {
    test('a burst of saves is one write, made after the delay', () async {
      final store = open(writeDelay: const Duration(milliseconds: 150));
      for (var revision = 0; revision < 20; revision++) {
        saveFeed(store, 'latest', '{"revision":$revision}');
      }
      await pumpEventQueue();
      expect(await fileFor(_site).exists(), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 400));
      final written = await fileFor(_site).readAsString();
      expect(written, contains(r'{\"revision\":19}'));
      expect(written, isNot(contains(r'{\"revision\":18}')));
    });

    test('saving what is already kept writes nothing', () async {
      final store = open();
      saveTopic(store, 7, '{"id":7}');
      await store.flush();
      final written = (await fileFor(_site).stat()).modified;
      await fileFor(_site).setLastModified(DateTime(2001));

      saveTopic(store, 7, '{"id":7}');
      await store.flush();

      expect((await fileFor(_site).stat()).modified, DateTime(2001));
      expect(written, isNot(DateTime(2001)));
    });
  });

  group('a snapshot this version cannot read', () {
    final unreadable = <String, List<int>>{
      'another format version': utf8.encode(
        jsonEncode({
          'version': ContentSnapshotStore.formatVersion + 1,
          'account': _alice,
          'feeds': <Object>[],
          'topics': [
            {'id': 7, 'savedAt': 1, 'bytes': 8, 'wire': '{"id":7}'},
          ],
        }),
      ),
      'no version at all': utf8.encode('{"account":"id:1"}'),
      'a truncated document': utf8.encode('{"version":1,"account":"id:1","fe'),
      'a root that is not an object': utf8.encode('[1,2,3]'),
      'an entry of the wrong shape': utf8.encode(
        jsonEncode({
          'version': ContentSnapshotStore.formatVersion,
          'account': _alice,
          'feeds': <Object>[],
          'topics': [
            {'id': '7', 'wire': 12},
          ],
        }),
      ),
      'bytes that are not text': [0xff, 0xfe, 0x00, 0xc3],
      'an empty file': <int>[],
    };

    for (final MapEntry(key: name, value: bytes) in unreadable.entries) {
      test('$name is treated as absent and replaced', () async {
        await fileFor(_site).writeAsBytes(bytes);

        final store = open();
        expect(await store.readTopic(_site, _alice, 7), isNull);
        expect(
          await store.readFeed(_site, _alice, 'latest', '/latest.json'),
          isNull,
        );

        saveTopic(store, 9, '{"id":9}');
        await store.flush();
        expect(await open().readTopic(_site, _alice, 9), '{"id":9}');
      });
    }
  });

  group('account scoping', () {
    test('one account never reads what another saved', () async {
      final first = open();
      saveFeed(first, 'messages', '{"private":true}');
      saveTopic(first, 7, '{"id":7}');
      await first.flush();

      final second = open();
      expect(
        await second.readFeed(_site, _bob, 'messages', '/latest.json'),
        isNull,
      );
      expect(await second.readTopic(_site, _bob, 7), isNull);
      expect(await second.readTopic(_site, 'anonymous', 7), isNull);
    });

    test("another account's save replaces the document", () async {
      final first = open();
      saveFeed(first, 'messages', '{"private":true}');
      saveTopic(first, 7, '{"id":7}');
      await first.flush();

      final second = open();
      saveTopic(second, 8, '{"id":8}', account: _bob);
      await second.flush();

      expect(await fileFor(_site).readAsString(), isNot(contains('private')));
      final third = open();
      expect(await third.readTopic(_site, _alice, 7), isNull);
      expect(await third.readTopic(_site, _bob, 8), '{"id":8}');
    });

    test('forums do not share a document', () async {
      final store = open();
      saveFeed(store, 'latest', '{"site":"a"}');
      saveFeed(store, 'latest', '{"site":"b"}', siteUrl: _otherSite);
      await store.flush();

      final reopened = open();
      expect(
        await reopened.readFeed(_site, _alice, 'latest', '/latest.json'),
        '{"site":"a"}',
      );
      expect(
        await reopened.readFeed(_otherSite, _alice, 'latest', '/latest.json'),
        '{"site":"b"}',
      );
    });
  });

  group('deletion', () {
    test('forgetting a forum deletes its file and leaves the others', () async {
      final store = open();
      saveFeed(store, 'latest', '{"site":"a"}');
      saveFeed(store, 'latest', '{"site":"b"}', siteUrl: _otherSite);
      await store.flush();

      await store.forget(_site);

      expect(await fileFor(_site).exists(), isFalse);
      expect(await fileFor(_otherSite).exists(), isTrue);
      expect(
        await store.readFeed(_site, _alice, 'latest', '/latest.json'),
        isNull,
      );
    });

    test(
      'a save still waiting on the delay is not written afterwards',
      () async {
        final store = open(writeDelay: const Duration(milliseconds: 50));
        saveTopic(store, 7, '{"id":7}');
        await pumpEventQueue();

        await store.forget(_site);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await store.flush();

        expect(await fileFor(_site).exists(), isFalse);
      },
    );

    test('a write already under way does not outlive the deletion', () async {
      final store = open();
      // Large enough that its encoding leaves the isolate, so the deletion is
      // requested while the write is genuinely in flight.
      saveTopic(store, 7, jsonEncode({'cooked': 'x' * (200 * 1024)}));
      final writing = store.flush();
      final forgetting = store.forget(_site);
      await Future.wait([writing, forgetting]);

      expect(await fileFor(_site).exists(), isFalse);
      expect(await store.readTopic(_site, _alice, 7), isNull);
    });

    test('a save accepted before its file was read is dropped too', () async {
      final store = open();
      saveTopic(store, 7, '{"id":7}');
      final forgetting = store.forget(_site);
      await forgetting;
      await store.flush();

      expect(await fileFor(_site).exists(), isFalse);
      expect(await store.readTopic(_site, _alice, 7), isNull);
    });

    test('the next account starts from nothing', () async {
      final store = open();
      saveTopic(store, 7, '{"id":7}');
      await store.flush();
      await store.forget(_site);

      saveTopic(store, 8, '{"id":8}', account: _bob);
      await store.flush();

      final reopened = open();
      expect(await reopened.readTopic(_site, _alice, 7), isNull);
      expect(await reopened.readTopic(_site, _bob, 8), '{"id":8}');
    });
  });

  group('bounds', () {
    test('keeps the most recently saved lists and topics', () async {
      final store = open(
        limits: const ContentSnapshotLimits(feeds: 2, topics: 2),
      );
      for (final id in [1, 2, 3]) {
        saveFeed(store, 'feed-$id', '{"feed":$id}');
        saveTopic(store, id, '{"id":$id}');
      }
      // Opening a kept topic again makes it the newest.
      saveTopic(store, 2, '{"id":2,"again":true}');
      saveTopic(store, 4, '{"id":4}');
      await store.flush();

      final reopened = open();
      Future<String?> feed(int id) =>
          reopened.readFeed(_site, _alice, 'feed-$id', '/latest.json');
      expect(await feed(1), isNull);
      expect(await feed(2), isNotNull);
      expect(await feed(3), isNotNull);
      expect(await reopened.readTopic(_site, _alice, 1), isNull);
      expect(await reopened.readTopic(_site, _alice, 3), isNull);
      expect(await reopened.readTopic(_site, _alice, 2), contains('again'));
      expect(await reopened.readTopic(_site, _alice, 4), isNotNull);
    });

    test('refuses a response larger than one entry may be', () async {
      final store = open(
        limits: const ContentSnapshotLimits(entryBytes: 64, totalBytes: 1024),
      );
      saveTopic(store, 7, jsonEncode({'cooked': 'x' * 100}));
      await store.flush();

      expect(await store.readTopic(_site, _alice, 7), isNull);
      expect(await fileFor(_site).exists(), isFalse);
    });

    test('drops the oldest topics, then lists, to fit the total', () async {
      final body = jsonEncode({'cooked': 'x' * 80});
      final bytes = utf8.encode(body).length;
      final store = open(
        limits: ContentSnapshotLimits(entryBytes: bytes, totalBytes: bytes * 3),
      );
      saveFeed(store, 'latest', body);
      saveFeed(store, 'new', body);
      saveTopic(store, 1, body);
      saveTopic(store, 2, body);
      saveTopic(store, 3, body);
      await store.flush();

      final reopened = open();
      expect(await reopened.readTopic(_site, _alice, 1), isNull);
      expect(await reopened.readTopic(_site, _alice, 2), isNull);
      expect(await reopened.readTopic(_site, _alice, 3), isNotNull);
      expect(
        await reopened.readFeed(_site, _alice, 'latest', '/latest.json'),
        isNotNull,
      );
      expect(
        await reopened.readFeed(_site, _alice, 'new', '/latest.json'),
        isNotNull,
      );
    });
  });
}
