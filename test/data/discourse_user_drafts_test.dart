import 'dart:convert';
import 'dart:isolate';

import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _siteUrl = 'https://drafts.example';

void main() {
  test(
    'takes raw positions before filtering and preserves order and duplicates',
    () async {
      final client = _ResourceClient(
        _jsonResponse({
          'drafts': [
            null,
            {'draft_key': ''},
            {'draft_key': 'topic_12', 'sequence': 1},
            false,
            {'draft_key': 'topic_12', 'sequence': 2},
            {'draft_key': 'new_topic', 'sequence': 3},
            {'draft_key': 'beyond_limit', 'sequence': 4},
          ],
        }),
      );
      final api = DiscourseApi(client: client);
      addTearDown(api.close);

      final page = await api.userDrafts(
        siteUrl: _siteUrl,
        apiKey: 'private-key',
        clientId: 'private-client',
        offset: 30,
        limit: 6,
      );

      expect(client.requests.single.url.path, '/drafts.json');
      expect(client.requests.single.url.queryParameters, {
        'offset': '30',
        'limit': '6',
      });
      expect(client.requests.single.headers['User-Api-Key'], 'private-key');
      expect(
        client.requests.single.headers['User-Api-Client-Id'],
        'private-client',
      );
      expect(page.rawItemCount, 6);
      expect(page.drafts.map((draft) => (draft.key, draft.sequence)), [
        ('topic_12', 1),
        ('topic_12', 2),
        ('new_topic', 3),
      ]);
      expect(() => page.drafts.clear(), throwsUnsupportedError);
    },
  );

  for (final encodedData in [false, true]) {
    test(
      'transfers lossless ${encodedData ? 'string' : 'map'} resume data and bounded Unicode excerpt',
      () async {
        final reply = '${'😀 e\u0301 👩\u200d💻 paragraph\n' * 2500}end';
        final data = <String, Object?>{
          'reply': reply,
          'action': 'privateMessage',
          'title': 'A full draft',
          'categoryId': 5,
          'tags': [
            {'id': 2, 'name': 'drafts'},
            {'name': 'unicode'},
          ],
          'archetypeId': 'private_message',
          'recipients': 'sam,alex',
          'reply_to_post_number': 7,
          'reply_to_user': {'username': 'sam'},
          'whisper': true,
          'typingTime': 1234,
          'composerTime': 5678,
        };
        final api = _api(
          _jsonResponse({
            'drafts': [
              {
                'draft_key': 'topic_12',
                'sequence': 4,
                'topic_id': 12,
                'created_at': '2026-10-16T08:00:00.000Z',
                'title': 'Remote title',
                'slug': 'remote-title',
                'category_id': 8,
                'archetype': 'private_message',
                'data': encodedData ? jsonEncode(data) : data,
              },
            ],
          }),
        );

        final page = await api.userDrafts(siteUrl: _siteUrl, apiKey: 'key');
        final draft = page.drafts.single;

        expect(page.rawItemCount, 1);
        expect(draft.data?.toJson(), data);
        expect(draft.data?.reply, endsWith('end'));
        expect(draft.excerpt, isNotEmpty);
        expect(draft.excerpt.length, lessThanOrEqualTo(512));
        expect(utf8.decode(utf8.encode(draft.excerpt)), draft.excerpt);
        expect(draft.createdAt, DateTime.utc(2026, 10, 16, 8));
        expect(draft.topicId, 12);
        expect(draft.title, 'Remote title');
        expect(draft.slug, 'remote-title');
        expect(draft.categoryId, 8);
        expect(draft.archetype, 'private_message');
        expect(draft.canResume, isTrue);
      },
    );
  }

  test('malformed nested data leaves valid sibling drafts available', () async {
    final api = _api(
      _jsonResponse({
        'drafts': [
          {'draft_key': 'broken_json', 'data': '{'},
          {'draft_key': 'wrong_json_root', 'data': '[]'},
          {'draft_key': 'wrong_value', 'data': false},
          {'draft_key': 'empty_string', 'data': '{"reply":""}'},
          {'draft_key': 'empty_map', 'data': <String, Object?>{}},
          {
            'draft_key': 'new_topic',
            'data': {'reply': 'A valid sibling'},
          },
        ],
      }),
    );

    final page = await api.userDrafts(siteUrl: _siteUrl, apiKey: 'key');

    expect(page.rawItemCount, 6);
    expect(page.drafts, hasLength(6));
    expect(
      page.drafts.take(4).map((draft) => draft.data),
      everyElement(isNull),
    );
    expect(page.drafts[4].data?.reply, '');
    expect(page.drafts.last.data?.reply, 'A valid sibling');
  });

  test('retains the existing encoded limit and map-form acceptance', () async {
    final reply = 'x' * (ComposerDraft.maximumEncodedCharacters + 1);
    final api = _api(
      _jsonResponse({
        'drafts': [
          {
            'draft_key': 'encoded',
            'data': jsonEncode({'reply': reply}),
          },
          {
            'draft_key': 'map',
            'data': {'reply': reply},
          },
        ],
      }),
    );

    final page = await api.userDrafts(siteUrl: _siteUrl, apiKey: 'key');

    expect(page.drafts.first.data, isNull);
    expect(page.drafts.last.data?.reply, reply);
    expect(page.drafts.last.excerpt, 'x' * 512);
  });

  test(
    'preserves declared charset and the missing-type latin1 fallback',
    () async {
      for (final headers in [
        {'content-type': 'application/json; charset="iso-8859-1"'},
        <String, String>{},
      ]) {
        final api = _api(
          http.Response.bytes(
            latin1.encode(
              jsonEncode({
                'drafts': [
                  {
                    'draft_key': 'new_topic',
                    'data': {'reply': 'café'},
                  },
                ],
              }),
            ),
            200,
            headers: headers,
          ),
        );

        final page = await api.userDrafts(siteUrl: _siteUrl, apiKey: 'key');

        expect(page.drafts.single.excerpt, 'café');
      }
    },
  );

  for (final source in ['{', '[]']) {
    test('outer failure $source retains its cause, stack and site', () async {
      final api = _api(http.Response(source, 200));

      await expectLater(
        api.userDrafts(siteUrl: _siteUrl, apiKey: 'key'),
        throwsA(
          isA<SiteLookupException>()
              .having(
                (error) => error.failure,
                'failure',
                SiteLookupFailure.unreachable,
              )
              .having((error) => error.term, 'site', _siteUrl)
              .having((error) => error.statusCode, 'status', isNull)
              .having((error) => error.cause, 'cause', isA<FormatException>())
              .having(
                (error) => error.causeStackTrace?.toString(),
                'cause stack',
                isNotEmpty,
              ),
        ),
      );
      if (source == '[]') {
        await expectLater(
          api.userDrafts(siteUrl: _siteUrl, apiKey: 'key'),
          throwsA(
            isA<SiteLookupException>().having(
              (error) => (error.cause! as FormatException).message,
              'caller-localized root error',
              appL10n.expectedAJSONObject,
            ),
          ),
        );
      }
    });
  }

  for (final status in [403, 503]) {
    test('HTTP $status retains transport status and site provenance', () async {
      final api = _api(
        http.Response(
          '{"error_type":"invalid_access"}',
          status,
          headers: {'content-type': 'application/json'},
        ),
      );

      await expectLater(
        api.userDrafts(siteUrl: _siteUrl, apiKey: 'key'),
        throwsA(
          isA<SiteLookupException>()
              .having(
                (error) => error.failure,
                'failure',
                status == 403
                    ? SiteLookupFailure.notDiscourse
                    : SiteLookupFailure.unreachable,
              )
              .having((error) => error.term, 'site', _siteUrl)
              .having((error) => error.statusCode, 'status', status)
              .having(
                (error) => error.errorType,
                'error type',
                status == 403 ? 'invalid_access' : isNull,
              )
              .having((error) => error.cause, 'cause', isNull),
        ),
      );
    });
  }
}

http.Response _jsonResponse(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

DiscourseApi _api(http.Response response) {
  final api = DiscourseApi(client: _ResourceClient(response));
  addTearDown(api.close);
  return api;
}

final class _ResourceClient extends http.BaseClient {
  _ResourceClient(this.response);

  final http.Response response;
  final RawReceivePort _unsendableResource = RawReceivePort();
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  @override
  void close() => _unsendableResource.close();
}
