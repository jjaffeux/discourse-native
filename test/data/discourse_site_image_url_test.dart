import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const imageCases = [
    (
      description: 'root-relative artwork on a root forum',
      siteUrl: 'https://example.com',
      image: '/images/emoji/twitter/smile.png?v=2',
      expected: 'https://example.com/images/emoji/twitter/smile.png?v=2',
    ),
    (
      description: 'server-prefixed artwork on a subfolder forum',
      siteUrl: 'https://example.com/community',
      image: '/community/images/emoji/twitter/smile.png?v=2',
      expected:
          'https://example.com/community/images/emoji/twitter/smile.png?v=2',
    ),
    (
      description: 'root-relative artwork outside the forum subfolder',
      siteUrl: 'https://example.com/community',
      image: '/uploads/icon.png',
      expected: 'https://example.com/uploads/icon.png',
    ),
    (
      description: 'directory-relative artwork under the forum subfolder',
      siteUrl: 'https://example.com/community',
      image: 'uploads/icon.png',
      expected: 'https://example.com/community/uploads/icon.png',
    ),
    (
      description: 'absolute HTTPS artwork with a port and encoded query',
      siteUrl: 'https://example.com/community',
      image: 'https://cdn.example.com:9443/icon%20one.png?v=a%2Fb&v=2',
      expected: 'https://cdn.example.com:9443/icon%20one.png?v=a%2Fb&v=2',
    ),
    (
      description: 'protocol-relative CDN artwork on an HTTPS forum',
      siteUrl: 'https://example.com/community',
      image: '//cdn.example.com:9443/icon%20one.png?v=a%2Fb&v=2',
      expected: 'https://cdn.example.com:9443/icon%20one.png?v=a%2Fb&v=2',
    ),
    (
      description: 'protocol-relative CDN artwork on a localhost HTTP forum',
      siteUrl: 'http://localhost:4200/community',
      image: '//cdn.example.com:8080/icon%20one.png?v=a%2Fb&v=2',
      expected: 'http://cdn.example.com:8080/icon%20one.png?v=a%2Fb&v=2',
    ),
    (
      description: 'root-relative artwork on a localhost HTTP forum',
      siteUrl: 'http://localhost:4200/community',
      image: '/community/uploads/icon%20one.png?v=a%2Fb&v=2',
      expected:
          'http://localhost:4200/community/uploads/icon%20one.png?v=a%2Fb&v=2',
    ),
    (
      description: 'absolute localhost HTTP artwork',
      siteUrl: 'http://localhost:4200/community',
      image: 'http://localhost:4300/uploads/icon.png?v=2',
      expected: 'http://localhost:4300/uploads/icon.png?v=2',
    ),
    (
      description: 'root-relative artwork with an encoded subfolder and port',
      siteUrl: 'https://example.com:8443/caf%C3%A9/team%2Fone',
      image: '/caf%C3%A9/team%2Fone/uploads/icon%20one.png?v=a%2Fb&v=2',
      expected:
          'https://example.com:8443/caf%C3%A9/team%2Fone/uploads/icon%20one.png?v=a%2Fb&v=2',
    ),
    (
      description: 'directory-relative artwork with an encoded subfolder',
      siteUrl: 'https://example.com:8443/caf%C3%A9/team%2Fone',
      image: 'uploads/icon%20one.png?v=a%2Fb&v=2',
      expected:
          'https://example.com:8443/caf%C3%A9/team%2Fone/uploads/icon%20one.png?v=a%2Fb&v=2',
    ),
    (
      description: 'nonempty artwork with a malformed percent escape',
      siteUrl: 'https://example.com',
      image: '/uploads/icon%zz.png',
      expected: 'https://example.com/uploads/icon%zz.png',
    ),
  ];

  group('emojiCatalog image URLs', () {
    for (final entry in imageCases) {
      test('resolves ${entry.description}', () async {
        final api = _apiServing([
          (
            'GET',
            '${entry.siteUrl}/emojis.json',
            _jsonResponse({
              'smileys_&_emotion': [
                {'name': 'smile', 'url': entry.image},
              ],
            }),
          ),
        ]);

        final catalog = await api.emojiCatalog(siteUrl: entry.siteUrl);

        expect(catalog.all.map((emoji) => (emoji.name, emoji.url)), [
          ('smile', entry.expected),
        ]);
      });
    }

    test(
      'skips empty or malformed rows while retaining valid artwork',
      () async {
        final api = _apiServing([
          (
            'GET',
            'https://example.com/community/emojis.json',
            _jsonResponse({
              'default': [
                null,
                'not a row',
                {'name': 'missing'},
                {'name': 'null', 'url': null},
                {'name': 'empty', 'url': ''},
                {'name': 'number', 'url': 42},
                {'name': 'object', 'url': <String, Object?>{}},
                {'name': '', 'url': '/uploads/ignored.png'},
                {
                  'name': 'smile',
                  'url': '/community/images/emoji/twitter/smile.png?v=2',
                },
              ],
            }),
          ),
        ]);

        final catalog = await api.emojiCatalog(
          siteUrl: 'https://example.com/community',
        );

        expect(catalog.all.map((emoji) => (emoji.name, emoji.url)), [
          (
            'smile',
            'https://example.com/community/images/emoji/twitter/smile.png?v=2',
          ),
        ]);
      },
    );
  });

  group('lookup site icon URLs', () {
    for (final entry in imageCases) {
      test('resolves ${entry.description}', () async {
        final api = _lookupApi(entry.siteUrl, entry.image);

        final site = await api.lookup(entry.siteUrl);

        expect(site.iconUrl, entry.expected);
      });
    }

    for (final (description, icon) in <(String, Object?)>[
      ('null', null),
      ('empty', ''),
      ('whitespace', '   '),
      ('numeric', 42),
      ('object', <String, Object?>{}),
    ]) {
      test('omits an icon with a $description value', () async {
        const siteUrl = 'https://example.com/community';
        final api = _lookupApi(siteUrl, icon);

        final site = await api.lookup(siteUrl);

        expect(site.iconUrl, isNull);
      });
    }
  });
}

DiscourseApi _lookupApi(String siteUrl, Object? icon) => _apiServing([
  (
    'HEAD',
    '$siteUrl/user-api-key/new',
    http.Response('', 200, headers: {'auth-api-version': '4'}),
  ),
  (
    'GET',
    '$siteUrl/site/basic-info.json',
    _jsonResponse({'title': 'Forum', 'apple_touch_icon_url': icon}),
  ),
]);

http.Response _jsonResponse(Object? body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

DiscourseApi _apiServing(List<(String, String, http.Response)> responses) {
  final requested = <(String, String)>[];
  final expected = [for (final (method, url, _) in responses) (method, url)];
  final api = DiscourseApi(
    client: MockClient((request) async {
      final index = requested.length;
      requested.add((request.method, request.url.toString()));
      expect(requested, expected.take(index + 1).toList());
      return responses[index].$3;
    }),
  );
  addTearDown(api.close);
  addTearDown(() => expect(requested, expected));
  return api;
}
