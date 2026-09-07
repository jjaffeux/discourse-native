import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'text downloads retain subfolder, authentication headers, and UTF-8 content',
    () async {
      late http.Request request;
      final api = DiscourseApi(
        client: MockClient((value) async {
          request = value;
          return http.Response(
            'BEGIN:VCALENDAR\r\nSUMMARY:Réunion\r\nEND:VCALENDAR',
            200,
            headers: {'content-type': 'text/calendar; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      final text = await api.pluginGetText(
        siteUrl: 'https://forum.example/community',
        path: '/calendar.ics',
        apiKey: 'key',
        clientId: 'client',
      );
      expect(text, contains('Réunion'));
      expect(
        request.url.toString(),
        'https://forum.example/community/calendar.ics',
      );
      expect(request.headers['user-api-key'], 'key');
      expect(request.headers['user-api-client-id'], 'client');
      expect(request.url.query, isEmpty);
    },
  );

  test(
    'text download cannot move credentials to another origin or exceed response bounds',
    () async {
      var sent = 0;
      final api = DiscourseApi(
        maxResponseBytes: 32,
        client: MockClient((_) async {
          sent++;
          return http.Response('a' * 64, 200);
        }),
      );
      addTearDown(api.close);
      await expectLater(
        api.pluginGetText(
          siteUrl: 'https://forum.example',
          path: 'https://elsewhere.example/file',
          apiKey: 'secret',
        ),
        throwsArgumentError,
      );
      expect(sent, 0);
      await expectLater(
        api.pluginGetText(
          siteUrl: 'https://forum.example',
          path: '/calendar.ics',
          apiKey: 'key',
        ),
        throwsA(isA<SiteLookupException>()),
      );
      expect(sent, 1);
    },
  );
}
