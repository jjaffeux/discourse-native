import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/data/dashboard_api.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/report_api.dart';
import 'package:discourse_native/src/plugins/data_explorer/data_explorer_reports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const query = DashboardReport(
  source: 'data_explorer_query',
  identifier: '-31',
  title: 'AI Sentiment Per Category and Trust Level',
  path: '/admin/plugins/discourse-data-explorer/queries/-31',
);
const payload = <String, dynamic>{
  'success': true,
  'columns': ['category_id', 'trust_level', 'positive', 'negative'],
  'colrender': {'0': 'category'},
  'rows': [
    [7, 2, '11', '0'],
  ],
};

void main() {
  test(
    'plugin dispatch runs the query HTTP API with selected dates and account',
    () async {
      final sent = <http.Request>[];
      final transport = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('site.json')
                  ? {
                      'categories': [
                        {'id': 7, 'name': 'Sailing'},
                      ],
                    }
                  : payload,
            ),
            200,
          );
        }),
      );
      addTearDown(transport.close);
      final loaded =
          await DiscourseReportApi(
            transport,
            sources: const [DataExplorerReports()],
          ).load(
            siteUrl: 'https://forum.example/discuss',
            apiKey: 'staff-key',
            clientId: '',
            report: query,
            range: DashboardRange(
              DateTime(2026, 10, 1),
              DateTime(2026, 10, 27),
            ),
            filters: const {},
          );
      expect(sent.first.method, 'GET');
      expect(
        sent.first.url.path,
        '/discuss/data-explorer/queries/-31/run.json',
      );
      expect(sent.first.headers['user-api-key'], 'staff-key');
      expect(jsonDecode(sent.first.url.queryParameters['params']!), {
        'start_date': '2026-10-01',
        'end_date': '2026-10-27',
      });
      expect(loaded.result.rows, [
        ['Sailing', '2', '11', '0'],
      ]);
      expect(loaded.result.headings, [
        'category',
        'trust level',
        'positive',
        'negative',
      ]);
    },
  );

  test(
    'dashboard bulk results are decoded only by the registered source',
    () async {
      final transport = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'items': [
                {'key': query.key, 'source': query.source, 'data': payload},
              ],
            }),
            200,
          ),
        ),
      );
      addTearDown(transport.close);
      final range = DashboardRange(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 27),
      );
      final core = await DiscourseDashboardApi(transport).reports(
        siteUrl: 'https://forum.example',
        apiKey: 'key',
        clientId: '',
        range: range,
        items: const [query],
      );
      expect(core[query.key]!.unsupported, isTrue);
      final extended =
          await DiscourseDashboardApi(
            transport,
            sources: const [DataExplorerReports()],
          ).reports(
            siteUrl: 'https://forum.example',
            apiKey: 'key',
            clientId: '',
            range: range,
            items: const [query],
          );
      expect(extended[query.key]!.rows, [
        ['7', '2', '11', '0'],
      ]);
    },
  );

  test(
    'empty, errored, numeric, null, and literal query cells stay distinct',
    () {
      const source = DataExplorerReports();
      expect(
        source.decode({
          'data': {
            'columns': ['name'],
            'rows': <Object?>[],
          },
        }).unsupported,
        isFalse,
      );
      expect(source.decode({'error': true}).error, isTrue);
      final result = source.decode({
        'data': {
          'columns': ['day', 'count'],
          'rows': [
            ['2026-10-01', '0'],
            ['2026-10-02', null],
            ['<b>literal</b>', '3'],
          ],
        },
      });
      expect(result.points.map((point) => point.value), [0, null, 3]);
      expect(result.rows.last, ['<b>literal</b>', '3']);
      expect(
        source.decode({
          'data': {
            'columns': ['name'],
            'rows': [
              ['Alice'],
            ],
          },
        }).rows,
        [
          ['Alice'],
        ],
      );
    },
  );
}
