import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/data/topic_read_outbox.dart';
import 'package:discourse_native/src/shell/topic_read_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Runs with no test binding, so the requests cross real loopback sockets and
/// the transport itself decides what a refused connection means.
void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('topic-read-sockets-');
    file = File('${directory.path}/topic-reads.json');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('reads made while the site is down are delivered after a relaunch, when '
      'the site first answers', () async {
    final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = reserved.port;
    await reserved.close();
    final siteUrl = 'http://127.0.0.1:$port';

    ({TopicReadController controller, TopicReadOutbox outbox}) launch() {
      final api = DiscourseApi();
      addTearDown(api.close);
      final outbox = createTopicReadOutbox(() => file);
      final controller = TopicReadController(
        api: api,
        credentials: FakeApiCredentialReader()..keys[siteUrl] = 'key',
        lifecycle: SiteLifecycle(),
        store: Store(),
        outbox: outbox,
        accountFor: (_) => 'user:sam',
        originSuccesses: api.onOriginSuccess,
      );
      return (controller: controller, outbox: outbox);
    }

    final offline = launch();
    await offline.controller.mark(
      siteUrl,
      1,
      3,
      caughtUp: false,
      readPostNumbers: [1, 2],
    );
    await offline.outbox.sites();
    // The process is killed here: nothing is disposed or flushed.

    final received = <Map<String, Object?>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      received.add({
        'path': request.uri.path,
        'key': request.headers.value('User-Api-Key'),
        ...jsonDecode(body) as Map<String, Object?>,
      });
      request.response.statusCode = 200;
      await request.response.close();
    });

    final relaunched = launch();
    addTearDown(relaunched.controller.dispose);
    expect(await relaunched.outbox.sites(), {siteUrl});
    await pumpEventQueue();
    await relaunched.controller.mark(siteUrl, 2, 1, caughtUp: false);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (received.length < 2 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(received, [
      {
        'path': '/topics/timings.json',
        'key': 'key',
        'topic_id': 2,
        'topic_time': 500,
        'timings': {'1': 500},
      },
      {
        'path': '/topics/timings.json',
        'key': 'key',
        'topic_id': 1,
        'topic_time': 1500,
        'timings': {'1': 500, '2': 500, '3': 500},
      },
    ]);
  });
}
