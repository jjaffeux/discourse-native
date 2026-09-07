import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _site = 'https://example.com';

void main() {
  group('channel member pagination payloads', () {
    for (final malformed in [
      null,
      false,
      'not a membership',
      <String, Object?>{},
      {'user': null},
      {'user': <Object?>[]},
      {
        'user': {'id': 0},
      },
      {
        'user': {'id': -1},
      },
      {
        'user': {'id': 'invalid'},
      },
    ]) {
      test('counts the filtered membership $malformed', () async {
        final api = _api({
          'memberships': [malformed, _membership(2)],
          'meta': {'total_rows': 20},
        });

        final page = await api.chatChannelMembers(
          siteUrl: _site,
          apiKey: 'key',
          channelId: 9,
          limit: 2,
        );

        expect(page.members.map((member) => member.id), [2]);
        expect(page.totalRows, 20);
        expect(page.rowCount, 2);
        expect(page.canLoadMore, isTrue);
      });
    }

    for (final sample in [
      (
        name: 'all filtered',
        rows: [null, false],
        ids: <int>[],
        count: 2,
        more: true,
      ),
      (
        name: 'oversized',
        rows: [null, _membership(2), _membership(3)],
        ids: [2],
        count: 2,
        more: true,
      ),
      (
        name: 'short filtered',
        rows: [null],
        ids: <int>[],
        count: 1,
        more: false,
      ),
      (name: 'empty', rows: <Object?>[], ids: <int>[], count: 0, more: false),
      (name: 'missing', rows: null, ids: <int>[], count: 0, more: false),
      (
        name: 'malformed list',
        rows: false,
        ids: <int>[],
        count: 0,
        more: false,
      ),
    ]) {
      test('handles ${sample.name} server pages', () async {
        final api = _api({
          'memberships': sample.rows,
          'meta': {'total_rows': 100, 'load_more_url': '/next'},
        });

        final page = await api.chatChannelMembers(
          siteUrl: _site,
          apiKey: 'key',
          channelId: 9,
          limit: 2,
        );

        expect(page.members.map((member) => member.id), sample.ids);
        expect(page.rowCount, sample.count);
        expect(page.canLoadMore, sample.more);
      });
    }
  });

  group('channel browse pagination payloads', () {
    for (final sample in [
      (
        name: 'partly filtered',
        rows: [null, _channel(2)],
        ids: [2],
        count: 2,
        more: true,
      ),
      (
        name: 'all filtered',
        rows: [null, false],
        ids: <int>[],
        count: 2,
        more: true,
      ),
      (
        name: 'oversized',
        rows: [null, _channel(2), _channel(3)],
        ids: [2],
        count: 2,
        more: true,
      ),
      (name: 'short', rows: [_channel(2)], ids: [2], count: 1, more: false),
      (
        name: 'short filtered',
        rows: [null],
        ids: <int>[],
        count: 1,
        more: false,
      ),
      (name: 'empty', rows: <Object?>[], ids: <int>[], count: 0, more: false),
      (name: 'missing', rows: null, ids: <int>[], count: 0, more: false),
      (
        name: 'malformed list',
        rows: false,
        ids: <int>[],
        count: 0,
        more: false,
      ),
    ]) {
      test(
        'handles ${sample.name} server pages with a load-more URL',
        () async {
          final api = _api({
            'channels': sample.rows,
            'meta': {'load_more_url': '/chat/api/channels?offset=2'},
          });

          final page = await api.browseChatChannels(
            siteUrl: _site,
            apiKey: 'key',
            limit: 2,
          );

          expect(page.channels.map((channel) => channel.id), sample.ids);
          expect(page.rowCount, sample.count);
          expect(page.hasMore, sample.more);
        },
      );
    }

    test('stops at a full page without a load-more URL', () async {
      final api = _api({
        'channels': [null, _channel(2)],
      });

      final page = await api.browseChatChannels(
        siteUrl: _site,
        apiKey: 'key',
        limit: 2,
      );

      expect(page.channels.single.id, 2);
      expect(page.rowCount, 2);
      expect(page.hasMore, isFalse);
    });
  });
}

ChatApiClient _api(Map<String, Object?> payload) {
  final transport = DiscourseApi(
    client: MockClient((_) async => http.Response(jsonEncode(payload), 200)),
  );
  addTearDown(transport.close);
  return ChatApiClient(transport);
}

Map<String, Object?> _membership(int id) => {
  'user': {'id': id, 'username': 'member$id'},
};

Map<String, Object?> _channel(int id) => {
  'id': id,
  'title': 'Channel $id',
  'chatable_type': 'Category',
};
