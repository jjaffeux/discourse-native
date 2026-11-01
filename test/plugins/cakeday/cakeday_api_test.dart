import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_api.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_data.dart';
import 'package:flutter_test/flutter_test.dart';

const site = 'https://forum.example/community';
const credentials = PluginRequestCredentials(
  apiKey: 'secret',
  clientId: 'client',
);
Map<String, dynamic> member(int id, {String date = '1992-11-01'}) => {
  'id': id,
  'username': 'member$id',
  'cakedate': date,
};
void main() {
  test(
    'exact endpoint uses viewer-authoritative order and credentials',
    () async {
      final transport = RecordingPluginTransport(
        responders: {
          'GET /cakeday/birthdays.json?page=0&filter=today': (_) => {
            'birthdays': [member(5), member(2)],
            'total_rows_birthdays': 2,
            'load_more_birthdays':
                '/community/cakeday/birthdays?page=1&filter=today',
          },
        },
      );
      final page = await CakedayApi(transport).load(
        site,
        const CakedayQuery(CakedayKind.birthdays, CakedayPeriod.today),
        0,
        credentials,
      );
      expect(page.members.map((m) => m.id), [5, 2]);
      expect(page.members.first.birthday!.wire, '1904-11-1');
      expect(page.nextPage, isNull);
      expect(transport.requests.single.apiKey, 'secret');
      expect(transport.requests.single.clientId, 'client');
    },
  );
  test(
    'anniversary timestamp retains server-normalized civil components without timezone shift',
    () async {
      final transport = RecordingPluginTransport(
        responders: {
          'GET /cakeday/anniversaries.json?page=0&month=11': (_) => {
            'anniversaries': [member(4, date: '2020-11-01T23:50:00.000-08:00')],
            'total_rows_anniversaries': 1,
          },
        },
      );
      final page = await CakedayApi(transport).load(
        site,
        const CakedayQuery(
          CakedayKind.anniversaries,
          CakedayPeriod.month,
          month: 11,
        ),
        0,
        credentials,
      );
      expect(page.members.single.joined!.day, 1);
      expect(page.members.single.joined!.year, 2020);
    },
  );
  for (final continuation in [
    'https://evil.example/cakeday/birthdays?page=1&filter=today',
    '/other?page=1&filter=today',
    '/cakeday/anniversaries?page=1&filter=today',
    '/cakeday/birthdays?page=0&filter=today',
    '/cakeday/birthdays?page=1&filter=tomorrow',
    '/cakeday/birthdays?page=1&page=2&filter=today',
    'javascript:/cakeday/birthdays?page=1&filter=today',
  ]) {
    test('rejects continuation $continuation', () async {
      final transport = RecordingPluginTransport(
        responders: {
          'GET /cakeday/birthdays.json?page=0&filter=today': (_) => {
            'birthdays': [member(1)],
            'total_rows_birthdays': 100,
            'load_more_birthdays': continuation,
          },
        },
      );
      await expectLater(
        CakedayApi(transport).load(
          site,
          const CakedayQuery(CakedayKind.birthdays, CakedayPeriod.today),
          0,
          credentials,
        ),
        throwsFormatException,
      );
    });
  }
  test(
    'malformed successful response is a protocol failure rather than empty results',
    () async {
      final transport = RecordingPluginTransport(
        responders: {
          'GET /cakeday/birthdays.json?page=0&filter=today': (_) => {
            'birthdays': [member(1, date: 'broken')],
            'total_rows_birthdays': 1,
          },
        },
      );
      await expectLater(
        CakedayApi(transport).load(
          site,
          const CakedayQuery(CakedayKind.birthdays, CakedayPeriod.today),
          0,
          credentials,
        ),
        throwsFormatException,
      );
    },
  );
}
