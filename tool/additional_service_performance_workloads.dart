import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_controller.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_data.dart';
import 'package:discourse_native/src/shell/search_words.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<Map<String, int>> measureAdditionalServicePerformance() async {
  final results = <String, int>{};
  Future<void> measure(
    String name,
    int iterations,
    Future<void> Function() action,
  ) async {
    for (var i = 0; i < 10; i++) {
      await action();
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      await action();
    }
    results[name] = watch.elapsedMicroseconds;
  }

  final fields = [
    for (var i = 0; i < 9; i++)
      List.filled(
        30,
        'A design discussion without the requested words',
      ).join(' '),
    'One Two Three Four Five Six',
  ];
  await measure('search_field_matching', 10000, () async {
    if (!searchWordsMatch('one two three four five six', fields)) {
      throw StateError('search field matches changed');
    }
    if (searchWordsMatch('one nonexistent', fields)) {
      throw StateError('unmatched search word was accepted');
    }
  });

  for (final (name, query, expected) in [
    ('single_match', 'design', true),
    ('single_miss', 'missing', false),
    ('two_match', 'design keyboard', true),
    ('two_miss', 'design missing', false),
  ]) {
    for (final count in [1, 3]) {
      final fields = [
        'Design keyboard shortcuts',
        if (count == 3) ...['A tool for discussion', 'Developer experience'],
      ];
      await measure('search_${name}_${count}_fields', 100000, () async {
        if (searchWordsMatch(query, fields) != expected) {
          throw StateError('short search field match changed');
        }
      });
    }
  }

  final tagRows = [
    for (var i = 0; i < 1000; i++)
      (id: i, name: i.isEven ? 'Design keyboard $i' : 'Native widget $i'),
  ];
  var queryIndex = 0;
  await measure('search_tag_page_filter', 1000, () async {
    final design = (queryIndex++).isEven;
    final matches = searchTextMatcher(
      design ? 'design keyboard' : 'native widget',
    );
    final selected = [
      for (final row in tagRows)
        if (matches(row.name)) row.id,
    ];
    final parity = design ? 0 : 1;
    if (selected.length != 500 ||
        selected.first != parity ||
        selected.last != 998 + parity ||
        selected.fold(0, (sum, id) => sum + id) != 249500 + 500 * parity) {
      throw StateError('Tag page filtering changed');
    }
  });

  final urls = [
    for (var i = 0; i < 100; i++) Uri.parse('https://example.com/t/$i.json'),
  ];
  await measure('shared_get_key_lookup', 10000, () async {
    final keys = [
      for (final url in urls)
        DiscourseGetRequestKey(
          url,
          headers: {
            'User-Api-Key': 'account-key',
            'User-Api-Client-Id': 'client',
            'Accept': 'application/json',
            'Accept-Encoding': 'gzip',
            'User-Agent': 'Discourse Native',
          },
          timeout: const Duration(seconds: 10),
          maxResponseBytes: 16 * 1024 * 1024,
        ),
    ];
    final inFlight = <DiscourseGetRequestKey, int>{};
    for (var i = 0; i < keys.length; i++) {
      inFlight[keys[i]] = i;
    }
    for (var i = 0; i < keys.length; i++) {
      if (inFlight[keys[i]] != i || inFlight.remove(keys[i]) != i) {
        throw StateError('GET key lookup changed');
      }
    }
    if (inFlight.isNotEmpty) throw StateError('GET key removal changed');
  });

  final coordinator = DiscourseRequestCoordinator();
  final url = urls.first;
  var sends = 0;
  try {
    await measure('shared_get_coordinator_round_trip', 10000, () async {
      final response = Completer<http.Response>();
      final key = DiscourseGetRequestKey(
        url,
        headers: const {
          'User-Api-Key': 'account-key',
          'User-Api-Client-Id': 'client',
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
          'User-Agent': 'Discourse Native',
        },
        timeout: const Duration(seconds: 10),
        maxResponseBytes: 16 * 1024 * 1024,
      );
      final start = sends;
      Future<http.Response> send(Future<void> _) {
        sends++;
        return response.future;
      }

      final first = coordinator.runGet(url, send, coalesce: key);
      final second = coordinator.runGet(url, send, coalesce: key);
      response.complete(http.Response('{"ok":true}', 200));
      final received = await Future.wait([first, second]);
      if (sends != start + 1 ||
          !identical(received.first, received.last) ||
          received.first.statusCode != 200 ||
          received.first.body != '{"ok":true}') {
        throw StateError('shared GET coordinator delivery changed');
      }
    });
  } finally {
    coordinator.close();
  }

  for (final (name, pageCount, pageSize, iterations) in [
    ('nested_reply_small_page', 1, 1, 3000),
    ('nested_reply_page_merge', 20, 30, 200),
  ]) {
    final loader = ServiceNestedLoader(
      pageCount: pageCount,
      pageSize: pageSize,
    );
    await measure(name, iterations, () async {
      final controller = NestedRepliesController(loader: loader);
      try {
        await controller.open();
        for (var page = 0; page < loader.pageCount; page++) {
          await controller.loadChildren(2, depth: 1);
        }
        final children = controller.childrenFor(2);
        if (controller.error != null ||
            controller.childrenState(2, depth: 1).error != null ||
            children.length != loader.pageCount * loader.pageSize) {
          throw StateError('nested reply page count changed');
        }
        for (var i = 0; i < children.length; i++) {
          if (children[i].postNumber != i + 3) {
            throw StateError('nested reply order changed');
          }
        }
      } finally {
        controller.dispose();
      }
    });
  }

  final tags = ServiceTagFixture();
  try {
    await measure('tag_directory_loading', 300, () async {
      final result = await tags.api.tags(siteUrl: 'https://example.com');
      tags.check(result);
    });
  } finally {
    tags.api.close();
  }
  return results;
}

final class ServiceCountingFields extends IterableBase<String> {
  ServiceCountingFields(this.values);
  final List<String> values;
  int reads = 0;
  @override
  Iterator<String> get iterator => values.map((value) {
    reads++;
    return value;
  }).iterator;
}

final class ServiceCountingUri implements Uri {
  ServiceCountingUri(this.value);
  final Uri value;
  int hashReads = 0;
  @override
  int get hashCode {
    hashReads++;
    return value.hashCode;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServiceCountingUri && other.value == value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class ServiceTagFixture {
  ServiceTagFixture({int count = 1000}) {
    final tags = [
      for (var i = 0; i < count; i++)
        {
          'id': i + 1,
          'name': '${i.isEven ? 'Tag' : 'tag'}-${i.toString().padLeft(4, '0')}',
          'slug': 'tag-$i',
          'count': i,
        },
    ]..shuffle(Random(731));
    final response = http.Response(
      jsonEncode({
        'tags': tags,
        'extras': {
          'tag_groups': [
            {
              'tags': [
                {'id': 1, 'name': 'Duplicate must not replace first'},
              ],
            },
          ],
          'categories': [
            {
              'tags': [
                {'id': count + 1, 'name': 'tag-0000', 'slug': 'tie'},
              ],
            },
          ],
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
    expectedIds = [1, count + 1, for (var i = 2; i <= count; i++) i];
    api = DiscourseApi(client: MockClient((_) async => response));
  }

  late final DiscourseApi api;
  late final List<int> expectedIds;

  void check(List<SidebarTag> result) {
    if (result.length != expectedIds.length) {
      throw StateError('tag directory count changed');
    }
    for (var i = 0; i < result.length; i++) {
      if (result[i].id != expectedIds[i]) {
        throw StateError('tag directory ordering changed at $i');
      }
    }
    if (result.first.slug != 'tag-0' || result.first.count != 0) {
      throw StateError('duplicate tag replaced first record');
    }
  }
}

final class ServiceNestedLoader implements NestedRepliesLoader {
  ServiceNestedLoader({required this.pageCount, required this.pageSize}) {
    final root = NestedReplyNode(
      postId: 102,
      postNumber: 2,
      data: NestedPostData(directReplyCount: pageCount * pageSize),
    );
    _roots = NestedPageReceipt(
      value: NestedRootPage(
        roots: [root],
        posts: [_payload(root)],
        page: 0,
        hasMore: false,
      ),
      acceptedPostIds: [root.postId],
    );
    _pages = [for (var page = 0; page < pageCount; page++) _page(page)];
  }
  final int pageCount;
  final int pageSize;
  late final NestedPageReceipt<NestedRootPage> _roots;
  late final List<NestedPageReceipt<NestedChildrenPage>> _pages;
  int childRequests = 0;

  NestedPageReceipt<NestedChildrenPage> _page(int page) {
    NestedReplyNode node(int index) => NestedReplyNode(
      postId: index + 103,
      postNumber: index + 3,
      data: const NestedPostData(replyToPostNumber: 2),
    );
    final nodes = [
      if (page > 0) node(page * pageSize - 1),
      for (var i = 0; i < pageSize; i++) node(page * pageSize + i),
      node(page * pageSize),
    ];
    return NestedPageReceipt(
      value: NestedChildrenPage(
        children: nodes,
        posts: nodes.map(_payload),
        page: page,
        hasMore: page < pageCount - 1,
      ),
      acceptedPostIds: nodes.map((node) => node.postId),
    );
  }

  static NestedPostPayload _payload(NestedReplyNode node) => NestedPostPayload(
    post: Post(
      id: node.postId,
      postNumber: node.postNumber,
      username: 'alice',
      cooked: '<p>Reply</p>',
    ),
    data: node.data,
  );

  @override
  bool get isCurrent => true;
  @override
  Future<NestedPageReceipt<NestedRootPage>?> roots({
    required NestedRepliesSort sort,
    required int page,
    required bool trackVisit,
  }) async => _roots;
  @override
  Future<NestedPageReceipt<NestedChildrenPage>?> children({
    required NestedRepliesSort sort,
    required int parentPostNumber,
    required int depth,
    required int page,
  }) async {
    childRequests++;
    return _pages[page];
  }

  @override
  Future<NestedPageReceipt<NestedContextPage>?> context({
    required NestedRepliesSort sort,
    required int postNumber,
    required int? contextDepth,
    required bool trackVisit,
  }) async => throw UnimplementedError();
}
