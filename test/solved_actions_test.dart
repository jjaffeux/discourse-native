import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/solved/solved_change_result.dart';
import 'package:discourse_native/src/plugins/solved/solved_controller.dart';
import 'package:discourse_native/src/plugins/solved/solved_post.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const site = 'https://meta.example';
const topic = TopicDetail(id: 7, title: 'Question', stream: [1, 2, 3]);
Post post(
  int id, {
  bool accepted = false,
  bool canAccept = true,
  bool canUnaccept = true,
  int type = 1,
}) => Post(
  id: id,
  postNumber: id,
  username: 'sam',
  cooked: '<p>Answer</p>',
  postType: type,
  plugins: PluginData.none.withValue(
    solvedPostKey,
    SolvedPost(
      accepted: accepted,
      canAccept: canAccept,
      canUnaccept: canUnaccept,
    ),
  ),
);

void main() {
  test('absent Solved serializer fields do not enable an action', () {
    expect(SolvedPost.fromJson({}), isNull);
    expect(
      SolvedPost.fromJson({'accepted_answer': true})!.canUnaccept,
      isFalse,
    );
  });

  test(
    'solution permissions exclude first posts, whispers and denied intents',
    () {
      final f = Fixture();
      expect(f.controller.canChange(post(1), true), isFalse);
      expect(f.controller.canChange(post(2, type: 4), true), isFalse);
      expect(f.controller.canChange(post(2, canAccept: false), true), isFalse);
      expect(
        f.controller.canChange(
          post(2, accepted: true, canUnaccept: false),
          false,
        ),
        isFalse,
      );
      expect(
        f.controller.canChange(
          post(2, accepted: true, canAccept: false),
          false,
        ),
        isTrue,
      );
    },
  );

  for (final accepted in [true, false]) {
    test(
      'writes the real ${accepted ? 'accept' : 'unaccept'} API and refreshes guardian records',
      () async {
        final f = Fixture();
        f.posts.records[2] = post(2, accepted: !accepted);
        f.posts.records[3] = post(3, accepted: true);
        expect((await f.change(accepted)).kind, SolvedChangeKind.applied);
        expect(
          f.api.calls.single.$1,
          accepted ? '/solution/accept.json' : '/solution/unaccept.json',
        );
        expect(f.api.calls.single.$2, 'POST');
        expect(f.api.calls.single.$3, {'id': 2});
        expect(f.posts.refreshed, [2, 3]);
        expect(f.reloads, [7]);
        expect(f.posts.busy, isFalse);
      },
    );
  }

  test(
    'retirement during credentials cannot send or release a replacement write',
    () async {
      final f = Fixture();
      f.requests.gate = Completer();
      final pending = f.change(true);
      await Future<void>.delayed(Duration.zero);
      f.requests.lease.current = false;
      f.requests.gate!.complete((
        credentials: const PluginRequestCredentials(
          apiKey: 'retired',
          clientId: '',
        ),
        failure: null,
      ));
      final result = await pending;
      expect(result.kind, SolvedChangeKind.inactive);
      expect(result.isCurrent, isFalse);
      expect(f.api.calls, isEmpty);
      expect(f.posts.ends, 0);
    },
  );

  test(
    'a permission revoked while credentials load prevents the write',
    () async {
      final f = Fixture();
      f.requests.gate = Completer();
      final pending = f.change(true);
      f.posts.records[2] = post(2, canAccept: false);
      f.requests.gate!.complete((
        credentials: const PluginRequestCredentials(
          apiKey: 'key',
          clientId: '',
        ),
        failure: null,
      ));
      expect((await pending).kind, SolvedChangeKind.unchanged);
      expect(f.api.calls, isEmpty);
      expect(f.posts.ends, 1);
    },
  );

  test('server refusal does not invent accepted state', () async {
    final f = Fixture();
    f.api.solvedFailure = const WriteException(WriteFailure.forbidden);
    final result = await f.change(true);
    expect(result.kind, SolvedChangeKind.refused);
    expect(result.failure, same(f.api.solvedFailure));
    expect(f.posts.records[2]!.plugins.get(solvedPostKey)!.accepted, isFalse);
    expect(f.posts.refreshed, isEmpty);
    expect(f.posts.busy, isFalse);
  });

  test('a double invocation shares the post write lane', () async {
    final f = Fixture();
    f.requests.gate = Completer();
    final pending = f.change(true);
    expect((await f.change(true)).kind, SolvedChangeKind.busy);
    f.requests.gate!.complete((
      credentials: const PluginRequestCredentials(apiKey: 'key', clientId: ''),
      failure: null,
    ));
    await pending;
    expect(f.api.calls, hasLength(1));
  });

  test('an unchanged answer sends no write', () async {
    final f = Fixture();
    f.posts.records[2] = post(2, accepted: true);
    expect((await f.change(true)).kind, SolvedChangeKind.unchanged);
    expect(f.api.calls, isEmpty);
    expect(f.posts.ends, 0);
  });

  test('acceptance is retained when the opening lease retires', () async {
    final f = Fixture();
    f.api.onAccepted = () => f.requests.lease.current = false;
    final result = await f.change(true);
    expect(result.kind, SolvedChangeKind.acceptedRetired);
    expect(result.isCurrent, isFalse);
    expect(f.api.calls, hasLength(1));
    expect(f.posts.refreshed, isEmpty);
    expect(f.reloads, isEmpty);
    expect(f.posts.ends, 0);
  });

  test(
    'retirement during refresh retains acceptance and stops reload',
    () async {
      final f = Fixture();
      f.posts.onRefresh = () => f.requests.lease.current = false;
      final result = await f.change(true);
      expect(result.kind, SolvedChangeKind.acceptedRetired);
      expect(f.posts.refreshed, [2]);
      expect(f.reloads, isEmpty);
      expect(f.posts.ends, 0);
    },
  );

  for (final (failure, kind) in [
    (
      const WriteException(WriteFailure.unreachable),
      SolvedChangeKind.uncertain,
    ),
    (
      const WriteException(WriteFailure.unreachable, notSent: true),
      SolvedChangeKind.notSent,
    ),
  ]) {
    test(
      'a transport ${kind.name} outcome does not invent acceptance',
      () async {
        final f = Fixture();
        f.api.solvedFailure = failure;
        final result = await f.change(true);
        expect(result.kind, kind);
        expect(result.failure, same(failure));
        expect(f.posts.refreshed, isEmpty);
        expect(f.reloads, isEmpty);
        expect(f.posts.busy, isFalse);
      },
    );
  }

  test('a credential exception is known not sent', () async {
    final f = Fixture();
    f.requests.gate = Completer();
    final pending = f.change(true);
    final failure = StateError('credential storage failed');
    f.requests.gate!.completeError(failure);
    final result = await pending;
    expect(result.kind, SolvedChangeKind.notSent);
    expect(result.failure!.cause, same(failure));
    expect(f.api.calls, isEmpty);
    expect(f.posts.busy, isFalse);
  });

  for (final refreshPost in [true, false]) {
    test(
      'a surfaced ${refreshPost ? 'post refresh' : 'topic reload'} failure retains acceptance',
      () async {
        final f = Fixture();
        const failure = WriteException(WriteFailure.forbidden, statusCode: 404);
        if (refreshPost) {
          f.posts.refreshFailure = failure;
        } else {
          f.reloadFailure = failure;
        }
        final result = await f.change(true);
        expect(result.kind, SolvedChangeKind.acceptedRefreshFailed);
        expect(result.failure, same(failure));
        expect(result.isCurrent, isTrue);
        expect(f.api.calls, hasLength(1));
        expect(f.posts.busy, isFalse);
      },
    );
  }
}

class Fixture {
  final api = _Api();
  final requests = _Requests();
  final posts = _Posts();
  final reloads = <int>[];
  Object? reloadFailure;
  late final controller = SolvedController(
    transport: api,
    requests: requests,
    posts: posts,
    topics: PluginTopicRefreshHost(
      reloadTopic: (_, id) async {
        reloads.add(id);
        if (reloadFailure != null) throw reloadFailure!;
      },
    ),
  );
  Future<SolvedChangeResult> change(bool accepted) => controller.change(
    siteUrl: site,
    topic: topic,
    postId: 2,
    accepted: accepted,
    lease: requests.lease,
  );
}

class _Lease implements PluginSiteLease {
  bool current = true;
  @override
  bool get isCurrent => current;
  @override
  bool commit(void Function() callback) {
    if (!current) return false;
    callback();
    return true;
  }
}

class _Requests implements PluginRequestHost {
  final lease = _Lease();
  Completer<PluginWriteCredential>? gate;
  @override
  PluginSiteLease capture(String siteUrl) => lease;
  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async =>
      gate == null
      ? (
          credentials: const PluginRequestCredentials(
            apiKey: 'key',
            clientId: '',
          ),
          failure: null,
        )
      : await gate!.future;
  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      const PluginRequestCredentials(apiKey: 'key', clientId: 'client');
}

class _Posts implements PluginPostHost {
  final records = <int, Post>{2: post(2)};
  final refreshed = <int>[];
  bool busy = false;
  int ends = 0;
  Object? refreshFailure;
  void Function()? onRefresh;
  @override
  Post? readPost(String siteUrl, int id) => records[id];
  @override
  bool beginWrite(String siteUrl, int id) {
    if (busy) return false;
    return busy = true;
  }

  @override
  void endWrite(String siteUrl, int id) {
    busy = false;
    ends++;
  }

  @override
  bool writeInFlight(String siteUrl, int id) => busy;
  @override
  bool topicArchived(String siteUrl, int topicId) => false;
  @override
  void updatePluginRecord<T extends Object>(
    String siteUrl,
    int id,
    PluginDataKey<T> key,
    T? Function(T?) update,
  ) {}
  @override
  Future<void> refreshPost({
    required String siteUrl,
    required int topicId,
    required int postId,
    required String? apiKey,
    required PluginSiteLease lease,
  }) async {
    refreshed.add(postId);
    onRefresh?.call();
    if (refreshFailure != null) throw refreshFailure!;
  }
}

class _Api extends FakeDiscourseApi {
  final calls = <(String, String, Map<String, Object?>)>[];
  WriteException? solvedFailure;
  void Function()? onAccepted;
  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    calls.add((path, method, body));
    if (solvedFailure != null) throw solvedFailure!;
    onAccepted?.call();
    return {};
  }
}
