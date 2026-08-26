import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/plugins/discourse_model_codec.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_api_client.dart';
import 'package:discourse_native/src/plugins/poll/poll_api.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_api_client.dart';
import 'package:discourse_native/src/plugins/site_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'GIF adapter owns route construction, validation, and parsing',
    () async {
      final transport = _RecordingTransport()
        ..getResponse = {
          'results': [
            {
              'title': 'Dancing cat',
              'media_formats': {
                'gif': {
                  'url': 'https://cdn.example/cat.gif',
                  'dims': [640, 360],
                },
              },
            },
          ],
          'next': 'cursor-2',
        };
      final api = GifsApiClient(transport);

      final page = await api.searchGifs(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
        query: ' dancing cat ',
        fileDetail: 'gif',
        position: ' cursor/1 ',
      );

      expect(transport.gets.single.path, '/gifs/search.json');
      expect(Uri.parse(transport.gets.single.pathAndQuery).queryParameters, {
        'q': 'dancing cat',
        'pos': 'cursor/1',
      });
      expect(page.results.single.url, 'https://cdn.example/cat.gif');
      expect(page.nextPosition, 'cursor-2');
    },
  );

  test(
    'Poll adapter owns its write payload and personalized response',
    () async {
      final transport = _RecordingTransport()
        ..writeResponse = {
          'poll': _poll('best'),
          'vote': ['best-a'],
        };
      final api = PollApi(transport);

      final response = await api.votePoll(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
        postId: 11,
        pollName: 'best',
        options: const ['best-a'],
      );

      expect(transport.writes.single.method, 'PUT');
      expect(transport.writes.single.path, '/polls/vote.json');
      expect(transport.writes.single.body, {
        'post_id': 11,
        'poll_name': 'best',
        'options': ['best-a'],
      });
      expect(response.poll.name, 'best');
      expect(response.selection.optionIds, ['best-a']);
    },
  );

  test(
    'Reactions adapter supports public reads and injected post decoding',
    () async {
      final transport = _RecordingTransport()
        ..getResponse = {
          'users': [
            {'id': 3, 'username': 'sam', 'reaction': 'clap'},
          ],
          'total_rows': 1,
        };
      final api = ReactionsApiClient(
        transport,
        DiscourseModelCodec(extensions: pluginRegistry),
      );

      final reactors = await api.postReactors(
        siteUrl: 'https://forum.example',
        postId: 7,
        reaction: '+1',
      );

      expect(transport.gets.single.apiKey, isNull);
      expect(Uri.parse(transport.gets.single.pathAndQuery).queryParameters, {
        'limit': '30',
        'reaction_value': '+1',
      });
      expect(reactors.reactors.single.username, 'sam');

      transport.writeResponse = {
        'id': 7,
        'post_number': 1,
        'username': 'sam',
        'cooked': '',
        'reactions': [
          {'id': 'clap', 'count': 1},
        ],
        'reaction_users_count': 1,
      };
      final post = await api.toggleReaction(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
        postId: 7,
        reaction: '+1',
      );
      expect(
        transport.writes.single.path,
        '/discourse-reactions/posts/7/custom-reactions/%2B1/toggle.json',
      );
      expect(post?.plugins.get(reactionsDataKey), isNotNull);
    },
  );
}

Map<String, Object?> _poll(String name) => {
  'id': 1,
  'name': name,
  'type': 'regular',
  'status': 'open',
  'results': 'always',
  'public': true,
  'dynamic': false,
  'voters': 1,
  'chart_type': 'bar',
  'title': 'Best?',
  'options': [
    {'id': '$name-a', 'html': 'A', 'votes': 1},
    {'id': '$name-b', 'html': 'B', 'votes': 0},
  ],
};

final class _RecordingTransport implements PluginApiTransport {
  Map<String, dynamic> getResponse = const {};
  Map<String, dynamic> writeResponse = const {};
  final List<({String pathAndQuery, String path, String? apiKey})> gets = [];
  final List<({String method, String path, Map<String, Object?> body})> writes =
      [];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    gets.add((pathAndQuery: path, path: Uri.parse(path).path, apiKey: apiKey));
    return getResponse;
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
    writes.add((method: method, path: path, body: body));
    return writeResponse;
  }
}
