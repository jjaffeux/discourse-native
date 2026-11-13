import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/site_appearance_loader.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> main() async {
  final times = <int>[];
  for (var run = 0; run < 9; run++) {
    final requests = <String>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      requests.add(path);
      await Future<void>.delayed(Duration(milliseconds: path == '/' ? 80 : 30));
      final body = switch (path) {
        '/site.json' => jsonEncode({
          'user_themes': [
            {'theme_id': 5, 'default': true, 'color_scheme_id': 10},
          ],
        }),
        '/u/alice.json' => jsonEncode({
          'user': {
            'username': 'alice',
            'user_option': {
              'theme_ids': [5],
            },
          },
        }),
        '/color-scheme-stylesheet/10/5.json' => '{"new_href":"/palette.css"}',
        '/' => '<html><head><title>Forum</title></head></html>',
        '/palette.css' =>
          '''
          :root {
            --scheme-type: light; --primary: #222222; --secondary: #ffffff;
            --tertiary: #0088cc; --quaternary: #e45735; --danger: #c80001;
            --success: #009900; --love: #fa6c8d;
          }
        ''',
        _ => throw StateError('Unexpected request $path'),
      };
      if (request.headers.containsKey('user-api-key') !=
          (path != '/palette.css')) {
        throw StateError('Unexpected authentication for $path');
      }
      return http.Response(body, 200);
    });
    final loader = SiteAppearanceLoader(client: client);
    final watch = Stopwatch()..start();
    final result = await loader.load(
      siteUrl: 'https://forum.example',
      username: 'alice',
      apiKey: 'fixture-key',
    );
    watch.stop();
    client.close();
    if (result?.base?.primary.toARGB32() != 0xff222222 ||
        result?.base?.tertiary.toARGB32() != 0xff0088cc ||
        requests.length != 5 ||
        requests.toSet().length != 5) {
      throw StateError('Appearance restoration did not complete');
    }
    if (run >= 2) times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  stdout.writeln(jsonEncode({'load_signed_in_forum_appearance': times[3]}));
  exit(0);
}
