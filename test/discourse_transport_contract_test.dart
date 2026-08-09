import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Discourse API transport contract', () {
    test('cross-origin credentials are rejected before delegation', () async {
      var delegated = 0;
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((_) async {
            delegated += 1;
            return http.Response('{}', 200);
          }),
        ),
        const Duration(seconds: 1),
        1024,
      );

      await expectLater(
        transport.get(
          Uri.parse('https://attacker.example/read.json'),
          siteUrl: 'https://example.com',
          apiKey: 'secret',
        ),
        throwsA(isA<SiteLookupException>()),
      );
      await expectLater(
        transport.write(
          Uri.parse('https://attacker.example/write.json'),
          siteUrl: 'https://example.com',
          method: 'POST',
          apiKey: 'secret',
          body: const {},
        ),
        throwsA(isA<WriteException>()),
      );
      await expectLater(
        transport.get(
          Uri.parse('https://example.com/read.json'),
          siteUrl: 'https://reader:password@example.com',
          apiKey: 'secret',
        ),
        throwsA(isA<SiteLookupException>()),
      );

      expect(delegated, 0);
    });

    test('ordinary reads use one authenticated header envelope', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );

      await api.notificationTotals(
        siteUrl: 'https://example.com',
        apiKey: 'secret',
        clientId: 'client',
      );

      expect(sent.method, 'GET');
      expect(sent.headers, containsPair('User-Api-Key', 'secret'));
      expect(sent.headers, containsPair('User-Api-Client-Id', 'client'));
      expect(sent.headers, containsPair('User-Agent', DiscourseApi.userAgent));
      expect(sent.headers, containsPair('Content-Type', 'application/json'));
      expect(sent.headers, containsPair('Dont-Chunk', 'true'));
    });

    test('malformed object reads preserve a diagnostic cause', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('[]', 200)),
      );

      await expectLater(
        api.notificationTotals(
          siteUrl: 'https://example.com',
          apiKey: 'secret',
        ),
        throwsA(
          isA<SiteLookupException>()
              .having(
                (error) => error.failure,
                'failure',
                SiteLookupFailure.unreachable,
              )
              .having((error) => error.term, 'term', 'https://example.com')
              .having(
                (error) => error.diagnosticCause,
                'diagnosticCause',
                isA<FormatException>(),
              )
              .having(
                (error) => error.diagnosticCauseStackTrace,
                'diagnosticCauseStackTrace',
                isNotNull,
              ),
        ),
      );
    });

    test('writes omit nulls and apply the shared refusal policy', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'errors': ['  Message is too short.  ', ''],
            }),
            422,
          );
        }),
      );

      await expectLater(
        api.sendChatMessage(
          siteUrl: 'https://example.com',
          apiKey: 'secret',
          clientId: 'client',
          channelId: 9,
          message: 'hi',
        ),
        throwsA(
          isA<WriteException>()
              .having(
                (error) => error.failure,
                'failure',
                WriteFailure.validation,
              )
              .having((error) => error.errors, 'errors', [
                'Message is too short.',
              ])
              .having((error) => error.statusCode, 'statusCode', 422),
        ),
      );

      expect(sent.method, 'POST');
      expect(sent.headers, containsPair('User-Api-Key', 'secret'));
      expect(sent.headers, containsPair('User-Api-Client-Id', 'client'));
      expect(jsonDecode(sent.body), {'message': 'hi'});
    });

    test('writes preserve a plugin singular error response', () async {
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient(
            (_) async => http.Response(
              jsonEncode({'error': 'You have reached the assignment limit.'}),
              400,
            ),
          ),
        ),
        const Duration(seconds: 1),
        1024,
      );

      await expectLater(
        transport.write(
          Uri.parse('https://example.com/assign/assign.json'),
          siteUrl: 'https://example.com',
          method: 'PUT',
          apiKey: 'secret',
          body: const {},
        ),
        throwsA(
          isA<WriteException>()
              .having(
                (error) => error.failure,
                'failure',
                WriteFailure.validation,
              )
              .having((error) => error.errors, 'errors', [
                'You have reached the assignment limit.',
              ])
              .having((error) => error.statusCode, 'statusCode', 400),
        ),
      );
    });
  });
}
