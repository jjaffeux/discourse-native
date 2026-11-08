import 'dart:convert';

import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_controller.dart';
import 'package:discourse_native/src/shell/search_words.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/additional_service_performance_workloads.dart';

const baseline = bool.fromEnvironment('PERF_BASELINE');

void main() {
  test(
    'service workloads consume and validate their complete results',
    () async {
      final timings = await measureAdditionalServicePerformance();
      // ignore: avoid_print
      print('SERVICE_WORKLOADS ${jsonEncode(timings)}');
    },
  );

  test('multiword field matching reads fields once', () {
    final fields = ServiceCountingFields([
      for (var i = 0; i < 9; i++) 'unrelated field $i',
      'One Two Three Four Five Six',
    ]);
    expect(searchWordsMatch('one two three four five six', fields), isTrue);
    // ignore: avoid_print
    print('SEARCH_FIELD_READS ${fields.reads}');
    if (!baseline) expect(fields.reads, lessThanOrEqualTo(10));
    expect(searchWordsMatch('one nonexistent', fields), isFalse);
    expect(searchWordsMatch('ONE two', ['oNe', 'TWO']), isTrue);
    expect(searchWordsMatch('foo FOO', ['Foo']), isTrue);
    expect(searchWordsMatch('missing', const []), isFalse);
    final unused = ServiceCountingFields(['not needed']);
    expect(searchWordsMatch('category:general @alice', unused), isTrue);
    expect(unused.reads, 0);
  });

  test('query reuse follows changes and owns its normalized words', () {
    for (var i = 0; i < 20; i++) {
      final query = 'alpha "$i" category:general';
      expect(searchWordsMatch(query, ['ALPHA $i']), isTrue);
      expect(searchWordsMatch(query, ['alpha missing']), isFalse);
      expect(searchWordsMatch('beta', ['ALPHA $i']), isFalse);
      expect(searchWordsMatch(query, ['ALPHA $i']), isTrue);
    }
    final words = searchWords('first second');
    expect(searchWordsMatch('first second', ['first second']), isTrue);
    words.clear();
    expect(searchWordsMatch('first second', ['first second']), isTrue);
    final longQuery = List.filled(5000, 'a').join();
    expect(searchWordsMatch(longQuery, [longQuery]), isTrue);
    expect(searchWordsMatch(longQuery, ['different']), isFalse);
  });

  test(
    'immutable GET keys calculate their hash once across map operations',
    () {
      final uri = ServiceCountingUri(
        Uri.parse('https://example.com/latest.json'),
      );
      final key = DiscourseGetRequestKey(
        uri,
        headers: {'User-Api-Key': 'key', 'Accept': 'application/json'},
        timeout: const Duration(seconds: 10),
        maxResponseBytes: 1024,
      );
      final pending = {key: 42};
      for (var i = 0; i < 100; i++) {
        expect(pending[key], 42);
      }
      expect(pending.remove(key), 42);
      // ignore: avoid_print
      print('REQUEST_KEY_URL_HASH_READS ${uri.hashReads}');
      if (!baseline) expect(uri.hashReads, 1);
    },
  );

  test(
    'GET hash memoization preserves order, ownership and session identity',
    () {
      final session = Object();
      final authentication = Object();
      final headers = {'User-Api-Key': 'key', 'Accept': 'application/json'};
      DiscourseGetRequestKey key(Map<String, String> values, {Object? owner}) =>
          DiscourseGetRequestKey(
            Uri.parse('https://example.com/latest.json'),
            headers: values,
            timeout: const Duration(seconds: 10),
            maxResponseBytes: 1024,
            session: owner ?? session,
            authentication: authentication,
          );
      final first = key(headers);
      final before = first.hashCode;
      headers['User-Api-Key'] = 'other';
      final equivalent = key({
        'accept': 'application/json',
        'user-api-key': 'key',
      });
      expect(first, equivalent);
      expect(first.hashCode, equivalent.hashCode);
      expect(first.hashCode, before);
      expect(first, isNot(key(headers)));
      expect(first, isNot(key({'User-Api-Key': 'key'}, owner: Object())));
      expect({first: 1}[equivalent], 1);
    },
  );

  test(
    'nested child pages retain stable order and deduplicate overlaps',
    () async {
      final loader = ServiceNestedLoader(pageCount: 20, pageSize: 30);
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open();
      for (var page = 0; page < loader.pageCount; page++) {
        await controller.loadChildren(2, depth: 1);
      }
      expect(controller.error, isNull);
      expect(controller.childrenState(2, depth: 1).error, isNull);
      expect(controller.childrenState(2, depth: 1).hasMore, isFalse);
      expect(loader.childRequests, 20);
      expect(
        controller.childrenFor(2).map((node) => node.postNumber),
        List.generate(600, (i) => i + 3),
      );
      await controller.loadChildren(2, depth: 1);
      expect(loader.childRequests, 20);
    },
  );

  test(
    'tag directory preserves ties, first record ownership and immutability',
    () async {
      final fixture = ServiceTagFixture();
      addTearDown(fixture.api.close);
      final tags = await fixture.api.tags(siteUrl: 'https://example.com');
      fixture.check(tags);
      expect(() => tags.clear(), throwsUnsupportedError);
    },
  );
}
