import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_api.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_data.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example/discuss';
const _credentials = PluginRequestCredentials(
  apiKey: 'key',
  clientId: 'client',
);

void main() {
  test(
    'current topic mode gates reader independently of optional settings',
    () {
      const unknown = NestedRepliesSettings();
      const enabled = NestedTopicData(enabled: true);
      expect(unknown.allowsTopic(enabled, privateMessage: false), isTrue);
      expect(unknown.allowsTopic(enabled, privateMessage: true), isFalse);
      expect(unknown.allowsTopic(null, privateMessage: false), isFalse);
      expect(
        const NestedRepliesSettings(
          enabled: false,
        ).allowsTopic(enabled, privateMessage: false),
        isFalse,
      );
    },
  );

  test('full mode absence and sparse activity have independent authority', () {
    const held = NestedTopicData(enabled: true, hasNewReplies: true);
    final detail = NestedTopicData.fromContext(
      {},
      const TopicRecordDecodeContext.detail(),
    );
    final merged = held.merge(detail);
    expect(merged.enabled, isFalse);
    expect(merged.hasNewReplies, isTrue);
    final list = NestedTopicData.fromContext(
      {},
      const TopicRecordDecodeContext.list(),
    );
    expect(held.merge(list).hasNewReplies, isFalse);
  });

  test(
    'plugin policy merges sparse list state and marks visits without positions',
    () {
      final held = PluginData.none.withValue(
        nestedRepliesTopicKey,
        const NestedTopicData(enabled: true, hasNewReplies: true),
      );
      final incoming = PluginData.none.withValue(
        nestedRepliesTopicKey,
        NestedTopicData.fromContext({
          'is_nested_view': true,
        }, const TopicRecordDecodeContext.detail()),
      );
      final merged = incoming.mergeTopicRecordsFrom(held);
      expect(merged.topicReadingPolicy.showsActivityDot, isTrue);
      expect(merged.topicReadingPolicy.allowsChronologicalResume, isFalse);
      expect(merged.topicReadingPolicy.usesPositionForCatchUp, isFalse);
      final visited = merged.markTopicRead();
      expect(visited.topicReadingPolicy.explicitReadState, isTrue);
      expect(visited.get(nestedRepliesTopicKey)!.enabled, isTrue);
      expect(held.topicReadingPolicy.showsActivityDot, isTrue);
      expect(const NestedTopicData(enabled: false).topicReadingPolicy, isNull);
    },
  );

  test('settings preserve unknown enablement and bound server depth', () {
    final settings = NestedRepliesSettings.fromJson({
      'nested_replies_max_depth': 100,
      'nested_replies_default_sort': 'surprise',
    });
    expect(settings.enabled, isNull);
    expect(settings.maxDepth, 3);
    expect(settings.defaultSort, NestedRepliesSort.top);
    final restored = const NestedRepliesSettingsCodec().decode(
      const NestedRepliesSettingsCodec().encode(settings),
    );
    expect(restored!.enabled, isNull);
  });

  test(
    'root snapshot retains server order, separate OP, and effective sort',
    () async {
      final transport = _Transport()
        ..response = {
          'topic': {'id': 7, 'title': 'Tree', 'is_nested_view': true},
          'op_post': _post(1),
          'roots': [
            _post(3),
            _post(2, children: [_post(4, parent: 2)]),
          ],
          'page': 0,
          'has_more_roots': true,
          'sort': 'hot',
          'effective_sort': 'top',
          'message_bus_last_id': 42,
          'pinned_post_ids': [103],
        };
      final page =
          await NestedRepliesApi(
            transport,
            const DiscourseModelCodec.core(),
          ).roots(
            siteUrl: _site,
            topicId: 7,
            slug: 'a-topic',
            credentials: _credentials,
            sort: NestedRepliesSort.hot,
          );
      expect(page.op!.postNumber, 1);
      expect(page.roots.map((node) => node.postNumber), [3, 2]);
      expect(page.roots.last.children.single.postNumber, 4);
      expect(page.effectiveSort, NestedRepliesSort.top);
      expect(page.posts.map((value) => value.post.id).toSet(), {
        101,
        102,
        103,
        104,
      });
      expect(page.recommendations, isNull);
      expect(page.messageBusLastId, 42);
      final uri = Uri.parse(transport.paths.single);
      expect(uri.path, '/n/a-topic/7.json');
      expect(uri.queryParameters, {'sort': 'hot', 'page': '0'});
      expect(transport.sites.single, _site);
      expect(() => page.topicMetadata!['id'] = 8, throwsUnsupportedError);
    },
  );

  test(
    'later root pages do not invent omitted metadata or empty recommendations',
    () async {
      final transport = _Transport()
        ..response = {
          'roots': <Object?>[],
          'page': 2,
          'has_more_roots': false,
          'suggested_topics': <Object?>[],
        };
      final page =
          await NestedRepliesApi(
            transport,
            const DiscourseModelCodec.core(),
          ).roots(
            siteUrl: _site,
            topicId: 7,
            slug: 'tree',
            credentials: _credentials,
            sort: NestedRepliesSort.top,
            page: 2,
          );
      expect(page.topicMetadata, isNull);
      expect(page.effectiveSort, isNull);
      expect(page.recommendations, {'suggested_topics': <Object?>[]});
    },
  );

  test(
    'foreground context preserves zero window and only opts in requested visits',
    () async {
      final transport = _Transport()
        ..response = {
          'topic': {'id': 7},
          'target_post': _post(9, parent: 4),
          'ancestor_chain': <Object?>[],
          'siblings': <String, Object?>{},
          'ancestors_truncated': false,
          'effective_sort': 'new',
        };
      final page =
          await NestedRepliesApi(
            transport,
            const DiscourseModelCodec.core(),
          ).context(
            siteUrl: _site,
            topicId: 7,
            slug: 'tree',
            credentials: _credentials,
            sort: NestedRepliesSort.newest,
            postNumber: 9,
            contextDepth: 0,
            trackVisit: true,
          );
      expect(page.target.data.replyToPostNumber, 4);
      expect(page.ancestors, isEmpty);
      expect(Uri.parse(transport.paths.single).queryParameters, {
        'sort': 'new',
        'context': '0',
        'track_visit': 'true',
      });
    },
  );

  test(
    'created context resolves identity but publishes only filtered tree content',
    () async {
      final transport = _Transport()
        ..responses['/posts/109.json'] = {
          ..._post(9),
          'cooked': '<p>Unfiltered secret</p>',
        }
        ..responses['/n/tree/7/context/9.json?sort=new&context=0'] = {
          'topic': {'id': 7},
          'target_post': {
            ..._post(9),
            'ignored_post_placeholder': true,
            'cooked': '',
            'raw': null,
          },
          'ancestor_chain': <Object?>[],
          'siblings': <String, Object?>{},
          'ancestors_truncated': false,
        };
      final api = NestedRepliesApi(transport, const DiscourseModelCodec.core());
      final page = await api.createdContext(
        siteUrl: _site,
        topicId: 7,
        slug: 'tree',
        postId: 109,
        credentials: _credentials,
        sort: NestedRepliesSort.newest,
      );
      expect(page.target.postId, 109);
      expect(page.posts.single.redacted, isTrue);
      expect(
        page.posts.single.post.cooked,
        isNot(contains('Unfiltered secret')),
      );
      expect(transport.paths, [
        '/posts/109.json',
        '/n/tree/7/context/9.json?sort=new&context=0',
      ]);
    },
  );

  test(
    'created context refuses mismatched identities before a context request',
    () async {
      final transport = _Transport()..response = {..._post(9), 'topic_id': 8};
      final api = NestedRepliesApi(transport, const DiscourseModelCodec.core());
      await expectLater(
        api.createdContext(
          siteUrl: _site,
          topicId: 7,
          slug: 'tree',
          postId: 109,
          credentials: _credentials,
          sort: NestedRepliesSort.top,
        ),
        throwsFormatException,
      );
      expect(transport.paths, ['/posts/109.json']);
    },
  );

  test(
    'created context rejects a different target at the same post number',
    () async {
      final transport = _Transport()
        ..responses['/posts/109.json'] = _post(9)
        ..responses['/n/tree/7/context/9.json?sort=top&context=0'] = {
          'topic': {'id': 7},
          'target_post': {..._post(9), 'id': 999},
          'ancestor_chain': <Object?>[],
          'siblings': <String, Object?>{},
          'ancestors_truncated': false,
        };
      final api = NestedRepliesApi(transport, const DiscourseModelCodec.core());
      await expectLater(
        api.createdContext(
          siteUrl: _site,
          topicId: 7,
          slug: 'tree',
          postId: 109,
          credentials: _credentials,
          sort: NestedRepliesSort.top,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Mismatched created post identity',
          ),
        ),
      );
      expect(transport.paths, [
        '/posts/109.json',
        '/n/tree/7/context/9.json?sort=top&context=0',
      ]);
    },
  );

  test(
    'deleted and ignored redaction do not erase staff deleted content',
    () async {
      final ignored = _post(2)
        ..addAll({'ignored_post_placeholder': true, 'cooked': '', 'raw': null});
      final staffDeleted = _post(4)
        ..addAll({'deleted_post_placeholder': true, 'raw': 'staff content'});
      final transport = _Transport()
        ..response = {
          'children': [
            ignored,
            {
              'id': 103,
              'post_number': 3,
              'deleted_post_placeholder': true,
              'reply_to_post_number': 2,
              'cooked': '',
              'raw': null,
              'direct_reply_count': 1,
              'total_descendant_count': 3,
            },
            staffDeleted,
          ],
          'page': 0,
          'has_more': false,
        };
      final page =
          await NestedRepliesApi(
            transport,
            const DiscourseModelCodec.core(),
          ).children(
            siteUrl: _site,
            topicId: 7,
            slug: 'tree',
            parentPostNumber: 2,
            credentials: _credentials,
            sort: NestedRepliesSort.top,
            depth: 3,
          );
      expect(page.posts.map((post) => post.redacted), [true, true, false]);
      expect(page.children[1].data.totalDescendantCount, 3);
      expect(page.children[2].data.placeholder, NestedPostPlaceholder.deleted);
      expect(page.posts.last.post.raw, 'staff content');
      expect(Uri.parse(transport.paths.single).queryParameters['depth'], '3');
    },
  );

  test(
    'a cross-topic node cannot enter the canonical publication batch',
    () async {
      final transport = _Transport()
        ..response = {
          'children': [_post(2)..['topic_id'] = 9],
          'page': 0,
          'has_more': false,
        };
      await expectLater(
        NestedRepliesApi(transport, const DiscourseModelCodec.core()).children(
          siteUrl: _site,
          topicId: 7,
          slug: 'tree',
          parentPostNumber: 1,
          credentials: _credentials,
          sort: NestedRepliesSort.top,
          depth: 1,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'activity synthetic entries stay outside canonical post identity',
    () async {
      final transport = _Transport()
        ..response = {
          'small_actions': [
            {
              'synthetic': true,
              'action_code': 'topic_created',
              'username': 'alice',
            },
            _post(4)..['action_code'] = 'closed.enabled',
          ],
          'has_more': false,
        };
      final page =
          await NestedRepliesApi(
            transport,
            const DiscourseModelCodec.core(),
          ).activity(
            siteUrl: _site,
            topicId: 7,
            slug: 'tree',
            credentials: _credentials,
          );
      expect(page.entries.first.post, isNull);
      expect(page.entries.first.synthetic, isTrue);
      expect(page.entries.last.post!.id, 104);
    },
  );

  test(
    'pin and bulk mutations use IDs and retain partial success without retries',
    () async {
      final transport = _Transport()
        ..response = {
          'pinned_post_ids': [103, 102],
        };
      final api = NestedRepliesApi(transport, const DiscourseModelCodec.core());
      expect(
        await api.togglePin(
          siteUrl: _site,
          topicId: 7,
          slug: 'tree',
          postId: 102,
          credentials: _credentials,
        ),
        [103, 102],
      );
      expect(transport.writes.single.body, {'post_id': 102});
      transport.response = {
        'topic_ids': [7],
        'errors': ['Denied 8'],
      };
      final result = await api.bulkTopicMode(
        siteUrl: _site,
        topicIds: [7, 8],
        enabled: false,
        credentials: _credentials,
      );
      expect(result.changedTopicIds, [7]);
      expect(result.errors, ['Denied 8']);
      expect(transport.writes.last.path, '/topics/bulk.json');
      expect(transport.writes.last.body, {
        'topic_ids': [7, 8],
        'operation': {'type': 'disable_nested_view'},
      });
      transport.failure = StateError('connection lost');
      await expectLater(
        api.togglePin(
          siteUrl: _site,
          topicId: 7,
          slug: 'tree',
          postId: 102,
          credentials: _credentials,
        ),
        throwsStateError,
      );
      expect(transport.writes.length, 3);
    },
  );
  test(
    'category conversion uses the actual success envelope and completion marker',
    () async {
      final transport = _Transport()
        ..response = {
          'success': 'OK',
          'converted_topic_count': 12,
          'nested_replies_conversion_completed': true,
        };
      final result =
          await NestedRepliesApi(
            transport,
            const DiscourseModelCodec.core(),
          ).convertCategory(
            siteUrl: _site,
            categoryId: 3,
            credentials: _credentials,
          );
      expect(result.convertedTopicCount, 12);
      expect(result.completed, isTrue);
      expect(
        transport.writes.single.path,
        '/categories/3/convert_nested_replies.json',
      );
      expect(transport.writes.single.method, 'POST');
    },
  );

  test(
    'ignored reveal returns cooked content without manufacturing raw or actions',
    () async {
      final transport = _Transport()
        ..response = {'cooked': '<p>Authorized content</p>'};
      final cooked = await NestedRepliesApi(
        transport,
        const DiscourseModelCodec.core(),
      ).revealIgnored(siteUrl: _site, postId: 102, credentials: _credentials);
      expect(cooked, '<p>Authorized content</p>');
      expect(transport.paths.single, '/posts/102/cooked.json');
    },
  );
}

Map<String, dynamic> _post(
  int number, {
  int? parent,
  List<Map<String, dynamic>> children = const [],
}) => {
  'id': 100 + number,
  'post_number': number,
  'topic_id': 7,
  'username': 'alice',
  'cooked': '<p>Post $number</p>',
  'reply_to_post_number': parent,
  'direct_reply_count': children.length,
  'total_descendant_count': children.length,
  'children': children,
};

final class _Transport implements PluginApiTransport {
  Map<String, dynamic> response = {};
  final responses = <String, Map<String, dynamic>>{};
  Object? failure;
  final paths = <String>[];
  final sites = <String>[];
  final writes = <({String path, String method, Map<String, Object?> body})>[];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    paths.add(path);
    sites.add(siteUrl);
    if (failure != null) throw failure!;
    return responses[path] ?? response;
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    writes.add((path: path, method: method, body: body));
    if (failure != null) throw failure!;
    return response;
  }
}
