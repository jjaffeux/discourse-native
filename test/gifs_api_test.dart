import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('GIF proxy API', () {
    test(
      'loads authenticated featured categories and skips malformed tags',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'tags': [
                  {
                    'name': 'Celebrate',
                    'image': 'https://cdn.example/celebrate.webp',
                    'searchterm': 'celebration',
                  },
                  {'name': 'Missing media'},
                ],
              }),
              200,
            );
          }),
        );
        addTearDown(api.close);

        final categories = await api.gifCategories(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
          clientId: 'native-client',
        );

        expect(sent.url.path, '/gifs/categories.json');
        expect(sent.headers['User-Api-Key'], 'secret');
        expect(sent.headers['User-Api-Client-Id'], 'native-client');
        expect(categories, hasLength(1));
        expect(categories.single.title, 'Celebrate');
        expect(categories.single.searchTerm, 'celebration');
      },
    );

    test(
      'searches with the opaque cursor and selects the requested format',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'title': 'Dancing cat',
                    'media_formats': {
                      'webp': {
                        'url': 'https://cdn.example/cat.webp',
                        'dims': [320, 180],
                      },
                      'gif': {
                        'url': 'https://cdn.example/cat.gif',
                        'dims': [640, 360],
                      },
                    },
                  },
                  {'title': 'Missing format'},
                ],
                'next': ' next/48 ',
              }),
              200,
            );
          }),
        );
        addTearDown(api.close);

        final page = await api.searchGifs(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
          clientId: 'native-client',
          query: ' dancing cat ',
          fileDetail: 'gif',
          position: ' cursor/24 ',
        );

        expect(sent.url.path, '/gifs/search.json');
        expect(sent.url.queryParameters, {
          'q': 'dancing cat',
          'pos': 'cursor/24',
        });
        expect(sent.headers['User-Api-Key'], 'secret');
        expect(page.results, hasLength(1));
        expect(page.results.single.url, 'https://cdn.example/cat.gif');
        expect(page.results.single.width, 640);
        expect(page.nextPosition, 'next/48');
      },
    );

    test('rejects invalid search input before making a request', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests += 1;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.close);

      Future<void> expectInvalid({
        String query = 'cat',
        String fileDetail = 'webp',
        String position = '0',
      }) async {
        await expectLater(
          api.searchGifs(
            siteUrl: 'https://forum.example',
            apiKey: 'secret',
            query: query,
            fileDetail: fileDetail,
            position: position,
          ),
          throwsArgumentError,
        );
      }

      await expectInvalid(query: '   ');
      await expectInvalid(query: List.filled(101, 'a').join());
      await expectInvalid(fileDetail: 'avif');
      await expectInvalid(position: ' \n ');
      expect(requests, 0);
    });

    test(
      'preserves response statuses used by picker error messaging',
      () async {
        for (final status in [403, 404, 429, 502]) {
          final api = DiscourseApi(
            client: MockClient((_) async => http.Response('nope', status)),
          );

          try {
            await expectLater(
              api.searchGifs(
                siteUrl: 'https://forum.example',
                apiKey: 'secret',
                query: 'cat',
                fileDetail: 'webp',
              ),
              throwsA(
                isA<SiteLookupException>().having(
                  (error) => error.statusCode,
                  'statusCode',
                  status,
                ),
              ),
              reason: 'HTTP $status must remain available to the picker',
            );
          } finally {
            api.close();
          }
        }
      },
    );
  });
}
