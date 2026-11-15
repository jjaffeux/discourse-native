import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/content_snapshot_store.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// A forum that answers a list and one topic over a real socket, and can be
/// taken away. Nothing below the shell is faked: the transport, the parsers,
/// the worker isolates and the snapshot file are the ones the app ships.
final class _Forum {
  _Forum._(this._server, this.port);

  static Future<_Forum> start({int port = 0, String edition = 'first'}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final forum = _Forum._(server, server.port);
    server.listen((request) async {
      final body = switch (request.uri.path) {
        '/latest.json' => {
          'topic_list': {
            'topics': [
              for (final id in [7, 8])
                {
                  'id': id,
                  'title': 'Topic $id, $edition edition',
                  'slug': 'topic-$id',
                  'posts_count': 2,
                },
            ],
          },
        },
        '/t/7.json' => {
          'id': 7,
          'title': 'Topic 7, $edition edition',
          'slug': 'topic-7',
          'posts_count': 2,
          'post_stream': {
            'stream': [70, 71],
            'posts': [
              for (final id in [70, 71])
                {
                  'id': id,
                  'post_number': id - 69,
                  'username': 'author',
                  'cooked': '<p>post $id, $edition edition</p>',
                },
            ],
          },
        },
        _ => null,
      };
      request.response.statusCode = body == null ? 404 : 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body ?? const <String, Object>{}));
      await request.response.close();
    });
    return forum;
  }

  final HttpServer _server;
  final int port;

  String get url => 'http://127.0.0.1:$port';

  Future<void> stop() => _server.close(force: true);
}

Future<void> _until(bool Function() ready, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for $what.');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory directory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp(
      'discourse-native-offline-launch-test-',
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  // Everything a launch owns is new each time; only the directory survives,
  // as it does across launches of the app.
  Future<({ShellController shell, DiscourseApi api})> launch(
    String siteUrl,
  ) async {
    final api = DiscourseApi(timeout: const Duration(seconds: 5));
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        DiscourseInstance(url: siteUrl, title: 'Forum', apiVersion: 4),
      ]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      contentSnapshots: ContentSnapshotStore(directory: () => directory),
    );
    await shell.load();
    return (shell: shell, api: api);
  }

  Future<void> quit(({ShellController shell, DiscourseApi api}) app) async {
    await app.shell.flushForExit();
    app.shell.dispose();
    app.api.close();
  }

  Future<void> openTopic(ShellController shell) {
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic-7', title: 'Topic 7'),
    );
    return shell.loadTopic(7, 'topic-7');
  }

  List<String?> listTitles(ShellController shell, String siteUrl) => [
    for (final id in shell.currentFeed?.topicIds ?? const <int>[])
      shell.store.read<Topic>(siteUrl, id)?.title,
  ];

  test(
    'a launch with the forum unreachable shows what the last launch read',
    () async {
      var forum = await _Forum.start();
      final siteUrl = forum.url;

      final online = await launch(siteUrl);
      await _until(
        () => online.shell.currentFeed?.loading == false,
        'the first list',
      );
      expect(online.shell.currentFeed!.error, isNull);
      expect(online.shell.currentFeed!.stale, isFalse);
      expect(listTitles(online.shell, siteUrl), [
        'Topic 7, first edition',
        'Topic 8, first edition',
      ]);
      await openTopic(online.shell);
      expect(
        online.shell.store.read<Post>(siteUrl, 70)?.cooked,
        '<p>post 70, first edition</p>',
      );
      await quit(online);
      await forum.stop();

      final offline = await launch(siteUrl);
      await _until(
        () => offline.shell.currentFeed?.loading == false,
        'the offline list',
      );
      final feed = offline.shell.currentFeed!;
      expect(listTitles(offline.shell, siteUrl), [
        'Topic 7, first edition',
        'Topic 8, first edition',
      ]);
      expect(feed.stale, isTrue);
      expect(feed.error, isNotNull, reason: 'the failed request is reported');

      await openTopic(offline.shell);
      expect(
        offline.shell.store.read<TopicDetail>(siteUrl, 7)?.title,
        'Topic 7, first edition',
      );
      expect(
        offline.shell.store.read<Post>(siteUrl, 70)?.cooked,
        contains('70'),
      );
      expect(
        offline.shell.store.read<Post>(siteUrl, 71)?.cooked,
        contains('71'),
      );
      await quit(offline);

      // The forum comes back with different content: the snapshot is shown
      // first and then gives way, in the list and in the topic.
      forum = await _Forum.start(port: forum.port, edition: 'second');
      addTearDown(forum.stop);
      final back = await launch(siteUrl);
      addTearDown(() => quit(back));
      await _until(
        () => back.shell.currentFeed?.loading == false,
        'the revalidated list',
      );
      expect(back.shell.currentFeed!.stale, isFalse);
      expect(back.shell.currentFeed!.error, isNull);
      expect(listTitles(back.shell, siteUrl), [
        'Topic 7, second edition',
        'Topic 8, second edition',
      ]);
      await openTopic(back.shell);
      expect(
        back.shell.store.read<Post>(siteUrl, 70)?.cooked,
        '<p>post 70, second edition</p>',
      );
    },
  );

  test(
    'nothing is shown offline to a launch that never read the forum',
    () async {
      final forum = await _Forum.start();
      final siteUrl = forum.url;
      await forum.stop();

      final offline = await launch(siteUrl);
      addTearDown(() => quit(offline));
      await _until(
        () => offline.shell.currentFeed?.loading == false,
        'the failed list',
      );

      expect(offline.shell.currentFeed!.topicIds, isEmpty);
      expect(offline.shell.currentFeed!.stale, isFalse);
      expect(offline.shell.currentFeed!.error, isNotNull);
    },
  );
}
