import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('forum discovery', () {
    for (final (term, base) in [
      ('example.com?utm_source=link', 'https://example.com'),
      ('https://example.com/#latest', 'https://example.com'),
      (
        'https://example.com/forum?utm_source=link',
        'https://example.com/forum',
      ),
      ('https://example.com/forum#latest', 'https://example.com/forum'),
      (
        '  example.com/forum///?utm_source=link#latest  ',
        'https://example.com/forum',
      ),
      (
        'https://example.com/community/discuss/?page=2#latest',
        'https://example.com/community/discuss',
      ),
      (
        'https://example.com:8443/caf%C3%A9/a%2Fb%3Fc%23d%25e/'
            '?utm_source=link#latest',
        'https://example.com:8443/caf%C3%A9/a%2Fb%3Fc%23d%25e',
      ),
      (
        'http://localhost:4200/forum/?utm_source=link#latest',
        'http://localhost:4200/forum',
      ),
    ]) {
      test('discards page extras while preserving the base of $term', () async {
        final api = _discoveryApi([
          ('HEAD', '$base/user-api-key/new', _authResponse()),
          ('GET', '$base/site/basic-info.json', _basicInfoResponse()),
        ]);

        final site = await api.lookup(term);

        expect(site.url, base);
        expect(site.title, 'Community');
        expect(site.apiVersion, 4);
        expect(site.iconUrl, '$base/uploads/icon.png');
      });
    }

    for (final (location, landed, base) in [
      (
        'https://forums.example:8443/forum/user-api-key/new?ref=canonical',
        'https://forums.example:8443/forum/user-api-key/new?ref=canonical',
        'https://forums.example:8443/forum',
      ),
      (
        'https://forums.example/forum/user-api-key/new#latest',
        'https://forums.example/forum/user-api-key/new#latest',
        'https://forums.example/forum',
      ),
      (
        '../../community/discuss/user-api-key/new/?ref=canonical#latest',
        'https://example.com/community/discuss/user-api-key/new/'
            '?ref=canonical#latest',
        'https://example.com/community/discuss',
      ),
      (
        'https://forums.example:8443/user-api-key/new///?ref=canonical#latest',
        'https://forums.example:8443/user-api-key/new///?ref=canonical#latest',
        'https://forums.example:8443',
      ),
      (
        '/caf%C3%A9/a%2Fb%3Fc%23d%25e/user-api-key/new?ref=canonical#latest',
        'https://example.com/caf%C3%A9/a%2Fb%3Fc%23d%25e/'
            'user-api-key/new?ref=canonical#latest',
        'https://example.com/caf%C3%A9/a%2Fb%3Fc%23d%25e',
      ),
    ]) {
      test('uses a clean forum base after redirecting to $location', () async {
        final api = _discoveryApi([
          (
            'HEAD',
            'https://example.com/forum/user-api-key/new',
            http.Response('', 301, headers: {'location': location}),
          ),
          ('HEAD', landed, _authResponse()),
          ('GET', '$base/site/basic-info.json', _basicInfoResponse()),
        ]);

        final site = await api.lookup('example.com/forum');

        expect(site.url, base);
        expect(site.title, 'Community');
        expect(site.apiVersion, 4);
        expect(site.iconUrl, '$base/uploads/icon.png');
      });
    }

    for (final location in [
      '/forum',
      '/forum/login?next=/user-api-key/new',
      '/forum/latest#/user-api-key/new',
      '/forum/user-api-key/new/extra',
      '/forum/user-api-key/newish',
      '/forum/prefix-user-api-key/new',
      '/forum%2Fuser-api-key%2Fnew',
    ]) {
      test('rejects the non-authentication redirect path $location', () async {
        final api = _discoveryApi([
          (
            'HEAD',
            'https://example.com/forum/user-api-key/new',
            http.Response('', 302, headers: {'location': location}),
          ),
          ('HEAD', 'https://example.com$location', _authResponse()),
        ]);

        await expectLater(
          api.lookup('example.com/forum'),
          throwsA(
            isA<SiteLookupException>().having(
              (error) => error.failure,
              'failure',
              SiteLookupFailure.notDiscourse,
            ),
          ),
        );
      });
    }

    test(
      'does not discover a forum by shortening a pasted topic URL',
      () async {
        final api = _discoveryApi([
          (
            'HEAD',
            'https://example.com/forum/t/welcome/42/user-api-key/new',
            http.Response('', 404),
          ),
        ]);

        await expectLater(
          api.lookup(
            'https://example.com/forum/t/welcome/42?source=link#post_2',
          ),
          throwsA(
            isA<SiteLookupException>().having(
              (error) => error.failure,
              'failure',
              SiteLookupFailure.notDiscourse,
            ),
          ),
        );
      },
    );
  });
}

http.Response _authResponse() =>
    http.Response('', 200, headers: {'auth-api-version': '4'});

http.Response _basicInfoResponse() => http.Response(
  jsonEncode({
    'title': 'Community',
    'apple_touch_icon_url': '/uploads/icon.png',
  }),
  200,
);

DiscourseApi _discoveryApi(List<(String, String, http.Response)> exchanges) {
  final requested = <(String, Uri)>[];
  final expected = [
    for (final (method, url, _) in exchanges) (method, Uri.parse(url)),
  ];
  final api = DiscourseApi(
    client: MockClient((request) async {
      final index = requested.length;
      requested.add((request.method, request.url));
      expect(index, lessThan(exchanges.length), reason: 'Unexpected request');
      expect((request.method, request.url), expected[index]);
      return exchanges[index].$3;
    }),
  );
  addTearDown(api.close);
  addTearDown(() => expect(requested, expected));
  return api;
}
