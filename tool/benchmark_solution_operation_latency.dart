import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/solved/solved_change_result.dart';
import 'package:discourse_native/src/plugins/solved/solved_controller.dart';
import 'package:discourse_native/src/plugins/solved/solved_post.dart';

import '../test/support/fakes.dart';

const _site = 'https://forum.example';
const _topic = TopicDetail(id: 7, title: 'Question', stream: [1, 2, 3]);
const _delay = Duration(milliseconds: 30);

Future<void> main() async {
  final samples = <int>[];
  for (var run = 0; run < 7; run++) {
    final host = _Host();
    final api = _Api();
    final controller = SolvedController(
      transport: api,
      requests: host,
      posts: host,
      topics: PluginTopicRefreshHost(
        reloadTopic: (_, id) async {
          if (id != _topic.id || host.refreshed.length != 2) {
            throw StateError('Answer records must settle before topic reload');
          }
          await Future<void>.delayed(_delay);
          host.reloaded = true;
        },
      ),
      readers: host,
    );
    final watch = Stopwatch()..start();
    final result = await controller.change(
      siteUrl: _site,
      topic: _topic,
      postId: 3,
      accepted: true,
      lease: host,
    );
    watch.stop();
    if (result.kind != SolvedChangeKind.applied ||
        !host.reloaded ||
        api.calls != 1 ||
        host.busy ||
        host.refreshed.toSet().length != 2 ||
        host.records[2]!.plugins.get(solvedPostKey)!.accepted ||
        !host.records[3]!.plugins.get(solvedPostKey)!.accepted) {
      throw StateError('Changing the accepted answer did not reconcile');
    }
    if (run >= 2) samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  stdout.writeln(jsonEncode({'replace_accepted_solution': samples[2]}));
  exit(0);
}

Post _answer(int id, {required bool accepted}) => Post(
  id: id,
  postNumber: id,
  username: 'reader',
  cooked: '<p>Answer</p>',
  plugins: PluginData.none.withValue(
    solvedPostKey,
    SolvedPost(accepted: accepted, canAccept: true, canUnaccept: true),
  ),
);

class _Host
    implements
        PluginSiteLease,
        PluginRequestHost,
        PluginPostHost,
        PluginTopicReaderHost {
  final records = {
    2: _answer(2, accepted: true),
    3: _answer(3, accepted: false),
  };
  final refreshed = <int>[];
  bool busy = false;
  bool reloaded = false;
  @override
  bool get isCurrent => true;
  @override
  bool commit(void Function() callback) {
    callback();
    return true;
  }

  @override
  void Function() onRetire(void Function() observer) => () {};
  @override
  PluginSiteLease capture(String siteUrl) => this;
  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      const PluginRequestCredentials(apiKey: 'key', clientId: '');
  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async =>
      (credentials: await credentialsFor(siteUrl), failure: null);
  @override
  Post? readPost(String siteUrl, int postId) => records[postId];
  @override
  bool beginWrite(String siteUrl, int postId) => busy = true;
  @override
  void endWrite(String siteUrl, int postId) => busy = false;
  @override
  bool writeInFlight(String siteUrl, int postId) => busy;
  @override
  bool topicArchived(String siteUrl, int topicId) => false;
  @override
  PluginTopicReader? forVisibleTopic(String siteUrl, int topicId) => null;
  @override
  void updatePluginRecord<T extends Object>(
    String siteUrl,
    int postId,
    PluginDataKey<T> key,
    T? Function(T?) update,
  ) => throw StateError('Unexpected local edit');
  @override
  Future<bool> refreshPost({
    required String siteUrl,
    required int topicId,
    required int postId,
    required String? apiKey,
    required PluginSiteLease lease,
  }) async {
    await Future<void>.delayed(_delay);
    records[postId] = _answer(postId, accepted: postId == 3);
    refreshed.add(postId);
    return true;
  }
}

class _Api extends FakeDiscourseApi {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    if (path != '/solution/accept.json' ||
        method != 'POST' ||
        body['id'] != 3) {
      throw StateError('Unexpected solution write');
    }
    calls++;
    await Future<void>.delayed(_delay);
    return {};
  }
}
