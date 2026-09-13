import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final key in <String?>[null, 'secret']) {
    test(
      'JSON query preserves subfolder and ${key == null ? 'anonymous' : 'authenticated'} headers',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response('{"categories":[]}', 200);
          }),
        );
        addTearDown(api.close);

        expect(
          await api.pluginQueryJson(
            siteUrl: 'https://forum.example/community',
            path: '/categories/search.json',
            apiKey: key,
            clientId: 'client',
            body: const {'term': 'Private search', 'page': 2, 'absent': null},
          ),
          {'categories': <Map<String, dynamic>>[]},
        );
        expect(sent.method, 'POST');
        expect(
          sent.url.toString(),
          'https://forum.example/community/categories/search.json',
        );
        expect(jsonDecode(sent.body), {'term': 'Private search', 'page': 2});
        expect(sent.headers['content-type'], 'application/json');
        expect(sent.headers['user-api-key'], key);
        expect(
          sent.headers['user-api-client-id'],
          key == null ? null : 'client',
        );
      },
    );
  }

  test('JSON queries retain same-origin and response bounds', () async {
    var sent = 0;
    final api = DiscourseApi(
      maxResponseBytes: 32,
      client: MockClient((_) async {
        sent++;
        return http.Response(jsonEncode({'large': 'x' * 64}), 200);
      }),
    );
    addTearDown(api.close);

    for (final key in <String?>[null, 'secret']) {
      await expectLater(
        api.pluginQueryJson(
          siteUrl: 'https://forum.example',
          path: '//elsewhere.example/search',
          apiKey: key,
          body: const {'term': 'Private search'},
        ),
        throwsArgumentError,
      );
    }
    expect(sent, 0);
    await expectLater(
      api.pluginQueryJson(
        siteUrl: 'https://forum.example',
        path: '/categories/search.json',
        apiKey: null,
        body: const {},
      ),
      throwsA(isA<SiteLookupException>()),
    );
    expect(sent, 1);
  });

  test(
    'JSON query rejects malformed responses and does not follow redirects',
    () async {
      for (final response in [
        http.Response('not JSON', 200),
        http.Response('[]', 200),
        http.Response(
          '',
          307,
          headers: {'location': 'https://elsewhere.example'},
        ),
      ]) {
        var sent = 0;
        final api = DiscourseApi(
          client: MockClient((_) async {
            sent++;
            return response;
          }),
        );
        addTearDown(api.close);
        await expectLater(
          api.pluginQueryJson(
            siteUrl: 'https://forum.example',
            path: '/categories/search.json',
            apiKey: null,
            body: const {},
          ),
          throwsA(isA<SiteLookupException>()),
        );
        expect(sent, 1);
      }
    },
  );
}
