import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _site = 'https://forum.example/community';
final _token = 'a' * 64;

void main() {
  test(
    'regression nov8: guest sessions accept matching parent cookie domains',
    () async {
      for (final (site, domain, expectedCookie) in [
        (
          'https://forum.example.com/community',
          'example.com',
          '_forum_session=anonymous',
        ),
        (
          'https://forum.example.com/community',
          '.EXAMPLE.COM',
          '_forum_session=anonymous',
        ),
        ('https://forum.example.com/community', 'otherexample.com', null),
        (
          'https://forum.example.com/community',
          'forum.example.com.evil.test',
          null,
        ),
        ('https://127.0.0.1/community', '0.0.1', null),
      ]) {
        String? cookie;
        final api = DiscourseApi(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/session/csrf.json')) {
              return http.Response(
                '{"csrf":"csrf-token"}',
                200,
                headers: {
                  'set-cookie':
                      '_forum_session=anonymous; Path=/; Secure; Domain=$domain',
                },
              );
            }
            cookie = request.headers['Cookie'];
            return http.Response(jsonEncode({'token': _token}), 202);
          }),
        );
        addTearDown(api.close);
        final connection = api.dsaNoticeConnection(siteUrl: site, apiKey: null);
        addTearDown(connection.dispose);
        await connection.requestVerification('guest@example.com');
        expect(cookie, expectedCookie, reason: '$site, $domain');
      }
    },
  );

  test('regression nov8: guest cookies honor Max-Age before Expires', () async {
    final cookies = <String?>[];
    final api = DiscourseApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/session/csrf.json')) {
          return http.Response(
            '{"csrf":"csrf-token"}',
            200,
            headers: {
              'set-cookie':
                  '_forum_session=anonymous; Path=/; Secure; Max-Age=3600; '
                  'Expires=Thu, 01 Jan 1970 00:00:00 GMT',
            },
          );
        }
        cookies.add(request.headers['Cookie']);
        if (request.url.path.endsWith('/verify-email')) {
          return http.Response(
            jsonEncode({'token': _token}),
            202,
            headers: {
              'set-cookie':
                  '_forum_session=deleted; Path=/; Secure; Max-Age=-1',
            },
          );
        }
        return http.Response('{"success":"OK"}', 200);
      }),
    );
    addTearDown(api.close);
    final connection = api.dsaNoticeConnection(siteUrl: _site, apiKey: null);
    addTearDown(connection.dispose);
    await connection.requestVerification('guest@example.com');
    await connection.verifyEmail('guest@example.com', _token, '123456');
    expect(cookies, ['_forum_session=anonymous', null]);
  });

  test(
    'guest notice establishes CSRF session and retains it through verification',
    () async {
      final requests = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          expect(request.url.origin, 'https://forum.example');
          expect(request.headers['User-Api-Key'], isNull);
          if (request.url.path == '/community/session/csrf.json') {
            expect(request.method, 'GET');
            return http.Response(
              jsonEncode({'csrf': 'csrf-token'}),
              200,
              headers: {
                'set-cookie':
                    '_forum_session=anonymous; Path=/community; HttpOnly; Secure',
              },
            );
          }
          expect(request.method, 'POST');
          expect(request.headers['X-CSRF-Token'], 'csrf-token');
          expect(request.headers['Cookie'], '_forum_session=anonymous');
          expect(request.headers['X-Requested-With'], 'XMLHttpRequest');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path.endsWith('/verify-email')) {
            expect(body, {'email': 'guest@example.com'});
            return http.Response(jsonEncode({'token': _token}), 202);
          }
          if (request.url.path.endsWith('/verify-code')) {
            expect(body, {
              'email': 'guest@example.com',
              'token': _token,
              'verification_code': '123456',
            });
            return http.Response('{"success":"OK"}', 200);
          }
          expect(body['token'], _token);
          expect(body['notice'], {
            'email': 'guest@example.com',
            'declaration': true,
          });
          return http.Response('{"reference":"DSA-1"}', 201);
        }),
      );
      final connection = api.dsaNoticeConnection(siteUrl: _site, apiKey: null);
      expect(await connection.requestVerification('guest@example.com'), _token);
      await connection.verifyEmail('guest@example.com', _token, '123456');
      expect(
        await connection.submit({
          'email': 'guest@example.com',
          'declaration': true,
        }, token: _token),
        'DSA-1',
      );
      expect(requests.map((r) => r.method), ['GET', 'POST', 'POST', 'POST']);
      connection.dispose();
      api.close();
    },
  );

  test(
    'account notice uses API credentials without creating browser session',
    () async {
      final api = DiscourseApi(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/community/dsa/report-illegal-content');
          expect(request.headers['User-Api-Key'], 'key');
          expect(request.headers['User-Api-Client-Id'], 'client');
          expect(request.headers['Cookie'], isNull);
          return http.Response('{"reference":"DSA-2"}', 201);
        }),
      );
      expect(
        await api
            .dsaNoticeConnection(
              siteUrl: _site,
              apiKey: 'key',
              clientId: 'client',
            )
            .submit({'name': 'Member'}),
        'DSA-2',
      );
      api.close();
    },
  );

  test('expired email verification is a recoverable typed refusal', () async {
    var posts = 0;
    final api = DiscourseApi(
      client: MockClient((request) async {
        posts++;
        return http.Response(
          '{"errors":["Verify again"],"error_type":"verification_required"}',
          422,
        );
      }),
    );
    await expectLater(
      api.dsaNoticeConnection(siteUrl: _site, apiKey: 'key').submit({}),
      throwsA(
        isA<DsaVerificationRequired>().having((e) => e.errors, 'errors', [
          'Verify again',
        ]),
      ),
    );
    expect(posts, 1);
    api.close();
  });

  test(
    'retiring a pending CSRF session prevents the subsequent guest write',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      var sent = 0;
      final api = DiscourseApi(
        client: MockClient((request) {
          sent++;
          started.complete();
          return response.future;
        }),
      );
      final connection = api.dsaNoticeConnection(siteUrl: _site, apiKey: null);
      final pending = connection.requestVerification('guest@example.com');
      await started.future;
      connection.dispose();
      response.complete(
        http.Response(
          '{"csrf":"late-token"}',
          200,
          headers: {'set-cookie': '_forum_session=late; Path=/; Secure'},
        ),
      );
      await expectLater(pending, throwsA(isA<WriteException>()));
      expect(sent, 1);
      api.close();
    },
  );

  test('disposed guest session sends neither CSRF nor a report', () async {
    var sent = 0;
    final api = DiscourseApi(
      client: MockClient((request) async {
        sent++;
        return http.Response('{}', 200);
      }),
    );
    final connection = api.dsaNoticeConnection(siteUrl: _site, apiKey: null)
      ..dispose();
    await expectLater(
      connection.requestVerification('guest@example.com'),
      throwsA(isA<WriteException>()),
    );
    expect(sent, 0);
    api.close();
  });
}
