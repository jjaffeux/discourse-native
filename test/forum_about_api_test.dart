import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final authenticated in [false, true]) {
    test(
      'About supports ${authenticated ? 'authenticated' : 'anonymous'} subfolder forums',
      () async {
        final sent = <http.Request>[];
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent.add(request);
            return http.Response(
              jsonEncode({
                'about': {
                  'title': 'Forum',
                  'stats': {'voice_users_7_days': 17},
                },
              }),
              200,
            );
          }),
        );
        addTearDown(api.close);
        final about = await api.forumAbout(
          siteUrl: 'https://forum.example/discuss',
          apiKey: authenticated ? 'test-key' : null,
          clientId: authenticated ? 'test-client' : null,
        );
        expect(
          sent.single.url.toString(),
          'https://forum.example/discuss/about.json',
        );
        expect(
          sent.single.headers['user-api-key'],
          authenticated ? 'test-key' : isNull,
        );
        expect(
          sent.single.headers['user-api-client-id'],
          authenticated ? 'test-client' : isNull,
        );
        expect(about.voiceParticipants(voiceEnabled: true), 17);
      },
    );
  }

  test('About keeps HTTP and invalid response failures visible', () async {
    for (final (response, failure) in [
      (
        http.Response('{"errors":["Not permitted"]}', 403),
        isA<SiteLookupException>().having(
          (error) => error.statusCode,
          'statusCode',
          403,
        ),
      ),
      (http.Response('<html>Sign in</html>', 200), isA<Exception>()),
      (http.Response('{}', 200), isA<Exception>()),
    ]) {
      final api = DiscourseApi(client: MockClient((_) async => response));
      await expectLater(
        api.forumAbout(siteUrl: 'https://forum.example'),
        throwsA(failure),
      );
      api.close();
    }
  });
}
