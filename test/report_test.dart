import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/report_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/dashboard.dart';
import 'package:discourse_native/src/models/report.dart';
import 'package:discourse_native/src/shell/report_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dashboard_test.dart' show FakeCredentials, flush;

const report = DashboardReport(
  source: 'core_report',
  identifier: 'signups',
  title: 'Signups',
  path: '/admin/reports/signups',
);
final range = DashboardRange(DateTime(2026, 10, 1), DateTime(2026, 10, 3));
const reportPayload = <String, dynamic>{
  'title': 'Signups',
  'description': 'New members',
  'modes': ['chart', 'table'],
  'labels': [
    {'property': 'x', 'type': 'date', 'title': 'Day'},
    {'property': 'y', 'type': 'number', 'title': 'Count'},
  ],
  'data': [
    {'x': '2026-10-01', 'y': 12},
    {'x': '2026-10-03', 'y': 0},
  ],
};

void main() {
  test(
    'core report GET uses mounted path, credentials, limit, and Rails filters',
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
                  : {
                      'report': {
                        ...reportPayload,
                        'available_filters': [
                          {'id': 'category', 'type': 'category', 'default': 7},
                        ],
                      },
                    },
            ),
            200,
          );
        }),
      );
      addTearDown(transport.close);
      final loaded = await DiscourseReportApi(transport).load(
        siteUrl: 'https://forum.example/discuss',
        apiKey: 'staff-key',
        clientId: '',
        report: report,
        range: range,
        filters: {
          'category': 7,
          'include_subcategories': false,
          'groups': [2, 4],
        },
      );
      expect(sent.first.method, 'GET');
      expect(sent.first.url.path, '/discuss/admin/reports/signups.json');
      expect(sent.first.url.queryParametersAll, {
        'start_date': ['2026-10-01'],
        'end_date': ['2026-10-03'],
        'limit': ['50'],
        'filters[category]': ['7'],
        'filters[include_subcategories]': ['false'],
        'filters[groups][]': ['2', '4'],
      });
      expect(sent.first.headers['user-api-key'], 'staff-key');
      expect(loaded.result.value, 12);
      expect(loaded.result.rows, [
        ['2026-10-01', '12'],
        ['2026-10-03', '0'],
      ]);
      expect(loaded.filters.single.choices, {'7': 'Sailing'});
    },
  );

  test(
    'uninstalled report source is unsupported and makes no request',
    () async {
      var requests = 0;
      final transport = DiscourseApi(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(transport.close);
      final loaded = await DiscourseReportApi(transport).load(
        siteUrl: 'https://forum.example',
        apiKey: 'key',
        clientId: '',
        range: range,
        filters: const {},
        report: const DashboardReport(
          source: 'optional_source',
          identifier: '1',
          title: 'Optional',
          path: '/optional',
        ),
      );
      expect(loaded.result.unsupported, isTrue);
      expect(requests, 0);
    },
  );

  test('stacked core reports retain every series and table label', () {
    final details = ReportDetails.fromJson({
      'data': {
        'data': [
          {
            'req': 'positive',
            'label': 'Positive',
            'data': [
              {'x': '2026-10-01', 'y': 3},
            ],
          },
          {
            'req': 'negative',
            'label': 'Negative',
            'data': [
              {'x': '2026-10-01', 'y': -2},
            ],
          },
        ],
        'modes': ['stacked_chart'],
      },
    });
    expect(details.result.unsupported, isFalse);
    expect(details.result.series.map((item) => item.label), [
      'Positive',
      'Negative',
    ]);
    expect(details.result.series.last.points.single.value, -2);
  });

  test(
    'latest range wins; retired accounts never restore report data',
    () async {
      final api = PendingReportApi();
      final lifecycle = SiteLifecycle();
      final owner = ReportController(
        api: api,
        credentials: FakeCredentials(),
        lease: lifecycle.capture('https://forum.example'),
        siteUrl: 'https://forum.example',
        report: report,
        range: range,
      );
      addTearDown(owner.dispose);
      final first = owner.refresh();
      await flush();
      final second = owner.selectRange(
        DashboardRange(DateTime(2026, 10, 2), range.end),
      );
      await flush();
      api.pending[1].complete(
        ReportDetails(
          result: DashboardReportResult(
            rows: const [
              ['new'],
            ],
          ),
        ),
      );
      await second;
      api.pending[0].complete(
        ReportDetails(
          result: DashboardReportResult(
            rows: const [
              ['old'],
            ],
          ),
        ),
      );
      await first;
      expect(owner.details!.result.rows, [
        ['new'],
      ]);
      final third = owner.refresh();
      await flush();
      lifecycle.invalidate('https://forum.example');
      expect(owner.details, isNull);
      api.pending[2].complete(
        ReportDetails(
          result: DashboardReportResult(
            rows: const [
              ['private'],
            ],
          ),
        ),
      );
      await third;
      expect(owner.details, isNull);
      expect(owner.loading, isFalse);
    },
  );
}

class PendingReportApi implements ReportApi {
  final pending = <Completer<ReportDetails>>[];
  @override
  Future<ReportDetails> load({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardReport report,
    required DashboardRange range,
    required Map<String, Object?> filters,
  }) {
    final result = Completer<ReportDetails>();
    pending.add(result);
    return result.future;
  }
}
