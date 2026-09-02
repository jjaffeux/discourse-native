import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'loads the authenticated application document at the site base',
    () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            _document({
              'currentUser': jsonEncode({
                'id': 42,
                'username': 'sam',
                'notification_channel_position': 91,
              }),
            }),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);

      final bootstrap = await api.messageBusBootstrap(
        siteUrl: 'https://example.com/forum',
        apiKey: 'secret',
        clientId: 'client-id',
      );

      expect(sent.url, Uri.parse('https://example.com/forum/'));
      expect(sent.headers['accept'], 'text/html');
      expect(sent.headers['User-Api-Key'], 'secret');
      expect(sent.headers['User-Api-Client-Id'], 'client-id');
      expect(bootstrap?.currentUser?.id, 42);
      expect(bootstrap?.notificationChannelPosition, 91);
    },
  );
}

String _document(Map<String, String> entries) =>
    '''
<script type="application/json" id="data-preloaded">
  ${jsonEncode(entries)}
</script>
''';
