import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('bookmark writes use core routes and UTC wire fields', () async {
    final requests = <http.Request>[];
    final api = DiscourseApi(
      client: MockClient((request) async {
        requests.add(request);
        return switch ((request.method, request.url.path)) {
          ('POST', '/bookmarks.json') => http.Response('{"id":81}', 200),
          ('DELETE', '/bookmarks/81.json') => http.Response(
            '{"topic_bookmarked":true}',
            200,
          ),
          _ => http.Response('{}', 200),
        };
      }),
    );

    final id = await api.createBookmark(
      siteUrl: 'https://forum.example',
      apiKey: 'secret',
      targetType: BookmarkTargetType.post,
      targetId: 44,
      name: 'Read this',
      reminderAt: DateTime.parse('2030-01-02T04:04:05+01:00'),
      autoDeletePreference: BookmarkAutoDeletePreference.whenReminderSent,
    );
    await api.updateBookmark(
      siteUrl: 'https://forum.example',
      apiKey: 'secret',
      bookmarkId: id,
      autoDeletePreference: BookmarkAutoDeletePreference.clearReminder,
    );
    final topicBookmarked = await api.deleteBookmark(
      siteUrl: 'https://forum.example',
      apiKey: 'secret',
      bookmarkId: id,
    );
    await api.deleteTopicBookmarks(
      siteUrl: 'https://forum.example',
      apiKey: 'secret',
      topicId: 7,
    );

    expect(id, 81);
    expect(topicBookmarked, isTrue);
    expect(requests.map((request) => request.method), [
      'POST',
      'PUT',
      'DELETE',
      'PUT',
    ]);
    expect(requests.map((request) => request.url.path), [
      '/bookmarks.json',
      '/bookmarks/81.json',
      '/bookmarks/81.json',
      '/t/7/remove_bookmarks',
    ]);
    expect(requests.first.headers['User-Api-Key'], 'secret');
    expect(jsonDecode(requests.first.body), {
      'bookmarkable_id': 44,
      'bookmarkable_type': 'Post',
      'name': 'Read this',
      'reminder_at': '2030-01-02T03:04:05.000Z',
      'auto_delete_preference': 1,
    });
    expect(jsonDecode(requests[1].body), {'auto_delete_preference': 3});
  });

  test(
    'bookmark writes reject invalid local drafts before transport',
    () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.createBookmark(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
          targetType: BookmarkTargetType.topic,
          targetId: 0,
        ),
        throwsRangeError,
      );
      await expectLater(
        api.createBookmark(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
          targetType: BookmarkTargetType.topic,
          targetId: 7,
          name: List.filled(101, 'x').join(),
        ),
        throwsA(
          isA<WriteException>().having(
            (error) => error.failure,
            'failure',
            WriteFailure.validation,
          ),
        ),
      );
      await expectLater(
        api.updateBookmark(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
          bookmarkId: 1,
          reminderAt: DateTime.now().subtract(const Duration(minutes: 1)),
          autoDeletePreference: BookmarkAutoDeletePreference.never,
        ),
        throwsA(isA<WriteException>()),
      );
      await expectLater(
        api.updateBookmark(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
          bookmarkId: 1,
          reminderAt: DateTime.now().toUtc().add(const Duration(days: 3654)),
          autoDeletePreference: BookmarkAutoDeletePreference.never,
        ),
        throwsA(
          isA<WriteException>().having(
            (error) => error.failure,
            'failure',
            WriteFailure.validation,
          ),
        ),
      );
      expect(requests, 0);
    },
  );

  test('a malformed delete success is ambiguous', () async {
    final api = DiscourseApi(
      client: MockClient((_) async => http.Response('{"success":true}', 200)),
    );

    await expectLater(
      api.deleteBookmark(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
        bookmarkId: 81,
      ),
      throwsA(
        isA<WriteException>().having(
          (error) => error.failure,
          'failure',
          WriteFailure.unreachable,
        ),
      ),
    );
  });
}
