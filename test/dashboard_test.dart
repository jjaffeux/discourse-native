import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/dashboard_api.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/dashboard.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/json.dart';
import 'package:discourse_native/src/shell/dashboard_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/dashboard_fixture.dart';

const site = 'https://forum.example/discuss';
final snapshot = DashboardSnapshot.fromJson(dashboardFixture);

void main() {
  test('calendar presets include today and clamp calendar months', () {
    final march = DateTime(2024, 3, 31);
    expect(DashboardPeriod.last7Days.rangeAt(march).query, {
      'start_date': '2024-03-25',
      'end_date': '2024-03-31',
    });
    expect(
      DashboardPeriod.last3Months.rangeAt(march).query['start_date'],
      '2024-01-01',
    );
    expect(
      DashboardPeriod.last3Months
          .rangeAt(DateTime(2024, 5, 31))
          .query['start_date'],
      '2024-03-01',
    );
    expect(
      DashboardPeriod.lastYear
          .rangeAt(DateTime(2024, 2, 29))
          .query['start_date'],
      '2023-03-01',
    );
  });
  test('real section schemas preserve zero, absence, and entry URLs', () {
    final parsed = DashboardSnapshot.fromJson(dashboardFixture);
    expect(parsed.sections.length, 6);
    final traffic = parsed.sections.whereType<DashboardTraffic>().single;
    final entry = traffic.rankings[1].rows.single;
    expect(entry.label, '/t/sailing/42');
    expect(entry.link!.value, '/t/sailing/42');
    expect(entry.link!.origin, DashboardLinkOrigin.server);
    expect(traffic.series.last.crawler, isTrue);
    expect(
      parsed.sections.whereType<DashboardReports>().single.items.first.path,
      '/admin/reports/daily_engaged_users',
    );
    expect(parsed.problems.single.message, 'Email is failing.');
    expect(DashboardMetric.fromJson('test', const {'value': 0}).value, 0);
    expect(DashboardMetric.fromJson('test', const {}).value, isNull);
    expect(
      DashboardMetric.fromJson('test', const {'value': double.nan}).value,
      isNull,
    );
    expect(() => parsed.sections.clear(), throwsUnsupportedError);
    expect(parsed.configuration!.last.id, 'plugin_health');
  });
  test(
    'legacy, plugin, failed sections, and disabled search stay explicit',
    () {
      expect(
        DashboardSnapshot.fromJson(const {'updated_at': 'now'}).supported,
        isFalse,
      );
      final parsed = DashboardSnapshot.fromJson(const {
        'sections': [
          {
            'id': 'plugin_health',
            'data': {'healthy': true},
          },
          {'id': 'traffic', 'data': null, 'error': true},
          {
            'id': 'search',
            'data': {'logging_enabled': false},
          },
        ],
      });
      expect(
        (parsed.sections[0] as DashboardUnavailableSection).failed,
        isFalse,
      );
      expect(
        (parsed.sections[1] as DashboardUnavailableSection).failed,
        isTrue,
      );
      expect((parsed.sections[2] as DashboardSearch).loggingEnabled, isFalse);
    },
  );
  test('report results parse series, tables, and unsupported payloads', () {
    final result = DashboardReportResult.fromJson(
      jsonObjects(dashboardReportsFixture['items']).first,
    );
    expect(result.value, 180);
    final table = DashboardReportResult.fromJson(const {
      'data': {
        'labels': [
          {'property': 'name', 'title': 'Member'},
        ],
        'data': [
          {'name': '<b>Sam</b>'},
        ],
      },
      'error': false,
    });
    expect(table.headings, ['Member']);
    expect(table.rows, [
      ['Sam'],
    ]);
    final xColumn = DashboardReportResult.fromJson(const {
      'data': {
        'labels': [
          {'property': 'x', 'title': 'Name'},
        ],
        'data': [
          {'x': 'Sailing'},
        ],
      },
    });
    expect(xColumn.points, isEmpty);
    expect(xColumn.rows, [
      ['Sailing'],
    ]);
    expect(
      DashboardReportResult.fromJson(const {
        'data': {
          'data': [
            {'custom': true},
          ],
        },
      }).unsupported,
      isTrue,
    );
  });
  test('report tables resolve core user, topic, post, and link labels', () {
    final table = DashboardReportResult.fromJson(const {
      'data': {
        'labels': [
          {
            'type': 'user',
            'properties': {'username': 'author_username', 'id': 'author_id'},
            'title': 'Author',
          },
          {
            'type': 'topic',
            'properties': {'title': 'topic_title', 'id': 'topic_id'},
            'title': 'Topic',
          },
          {
            'type': 'post',
            'properties': {
              'truncated_raw': 'post_raw',
              'number': 'post_number',
            },
            'title': 'Post',
          },
          {
            'type': 'link',
            'properties': ['file_url', 'file_name'],
            'title': 'File',
          },
          {
            'type': 'number',
            'properties': ['ignores_count'],
            'title': 'Ignored',
          },
          {'property': 'qtt_like', 'type': 'number', 'title': 'Likes'},
        ],
        'data': [
          {
            'author_username': 'sam',
            'author_id': 7,
            'topic_title': 'Sailing <b>together</b>',
            'topic_id': 42,
            'post_raw': 'A <b>post</b>',
            'post_number': 3,
            'file_url': '/uploads/manual.pdf',
            'file_name': 'Sailing manual.pdf',
            'ignores_count': 0,
            'qtt_like': 12,
          },
        ],
      },
    });
    expect(table.unsupported, isFalse);
    expect(table.rows, [
      ['sam', 'Sailing together', 'A post', 'Sailing manual.pdf', '0', '12'],
    ]);
  });
  test('unknown mapped report labels use the unsupported report fallback', () {
    for (final properties in <Object>[
      {'display': 'custom_name'},
      ['custom_id', 'custom_name'],
    ]) {
      final result = DashboardReportResult.fromJson({
        'data': {
          'labels': [
            {
              'type': 'custom_identity',
              'properties': properties,
              'title': 'Identity',
            },
          ],
          'data': const [
            {'custom_id': 7, 'custom_name': 'Sam'},
          ],
        },
      });
      expect(result.unsupported, isTrue);
      expect(result.rows, isEmpty);
    }
  });
  test('dated report gaps survive parsing and do not become zero totals', () {
    DashboardReportResult report(List<num?> values, {bool average = false}) =>
        DashboardReportResult.fromJson({
          'data': {
            'average': average,
            'total': 99,
            'data': [
              for (var i = 0; i < values.length; i++)
                {'x': '2026-10-${23 + i}', 'y': values[i]},
            ],
          },
        });
    final sparse = report([2, null, 4], average: true);
    expect(sparse.points.map((point) => point.value), [2, null, 4]);
    expect(sparse.value, 3);
    expect(report([2, null, 4]).value, isNull);
    expect(report([null, null]).value, isNull);
    expect(report([null, null], average: true).value, isNull);
    expect(report([0, null], average: true).value, 0);
  });
  test('native dashboard routes are durable and only resolve staff links', () {
    final route = ContentRoute.dashboard();
    expect(
      ContentRoute.fromJson(route.toJson()).isPage(CorePage.dashboard),
      isTrue,
    );
    for (final staff in [false, true]) {
      final instance = DiscourseInstance(
        url: site,
        title: 'Forum',
        user: DiscourseUser(username: 'sam', staff: staff),
      );
      for (final path in ['/admin', '/admin/dashboard']) {
        final decoded = ContentRouteCodec.fromUrl(
          '$site$path',
          instance: instance,
          config: instance.config,
          defaultTopPeriod: TopPeriod.all,
        );
        expect(decoded?.isPage(CorePage.dashboard), staff ? isTrue : isNull);
      }
    }
  });
  test(
    'API binds inclusive range and report POST to subfolder credentials',
    () async {
      final sent = <http.Request>[];
      final raw = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          final body = request.url.path.endsWith('bulk.json')
              ? dashboardReportsFixture
              : request.method == 'GET'
              ? dashboardFixture
              : <String, dynamic>{};
          return http.Response(jsonEncode(body), 200);
        }),
      );
      addTearDown(raw.close);
      final api = DiscourseDashboardApi(raw);
      final range = DashboardPeriod.last7Days.rangeAt(DateTime(2026, 10, 25));
      final loaded = await api.load(
        siteUrl: site,
        apiKey: 'key',
        clientId: '',
        range: range,
      );
      final items = loaded.sections.whereType<DashboardReports>().single.items;
      final reports = await api.reports(
        siteUrl: site,
        apiKey: 'key',
        clientId: '',
        range: range,
        items: items,
      );
      expect(sent.first.url.path, '/discuss/admin/dashboard.json');
      expect(sent.first.url.queryParameters, {
        'start_date': '2026-10-19',
        'end_date': '2026-10-25',
      });
      expect(sent[1].method, 'POST');
      expect(sent[1].url.path, '/discuss/admin/dashboard/reports/bulk.json');
      expect(jsonObject(jsonDecode(sent[1].body))['filters'], range.query);
      expect(sent[1].headers['user-api-key'], 'key');
      expect(reports.length, 2);
      await api.configure(
        siteUrl: site,
        apiKey: 'key',
        clientId: '',
        sections: loaded.configuration!,
      );
      expect(sent.last.method, 'PUT');
      expect(
        jsonObjects(
          jsonObject(jsonDecode(sent.last.body))['sections'],
        ).last['id'],
        'plugin_health',
      );
      await api.dismissProblem(
        siteUrl: site,
        apiKey: 'key',
        clientId: '',
        id: 1,
      );
      expect(sent.last.method, 'DELETE');
      expect(sent.last.url.path, '/discuss/admin/admin_notices/1.json');
    },
  );
  test('members never read credentials or call staff endpoints', () async {
    final api = FakeDashboardApi();
    final credentials = FakeCredentials();
    final owner = makeController(api, credentials, staff: false);
    addTearDown(owner.dispose);
    await owner.refresh();
    await owner.refreshProblems();
    await owner.configure([]);
    await owner.dismissProblem(snapshot.problems.single);
    expect(credentials.reads, 0);
    expect(api.loads, isEmpty);
    expect(api.writes, 0);
  });
  test('moderators read but cannot configure or dismiss', () async {
    final api = FakeDashboardApi();
    final owner = makeController(api, FakeCredentials(), admin: false);
    addTearDown(owner.dispose);
    await owner.refresh();
    await owner.configure([]);
    await owner.dismissProblem(snapshot.problems.single);
    expect(owner.state.snapshot!.sections.length, 6);
    expect(api.writes, 0);
  });
  test('range races publish only the selected response', () async {
    final api = FakeDashboardApi()..deferLoad = true;
    final owner = makeController(api, FakeCredentials());
    addTearDown(owner.dispose);
    final first = owner.refresh();
    await flush();
    final second = owner.selectPeriod(DashboardPeriod.last7Days);
    await flush();
    api.pendingLoads[1].complete(DashboardSnapshot(supported: true));
    await second;
    api.pendingLoads[0].complete(snapshot);
    await first;
    expect(owner.state.period, DashboardPeriod.last7Days);
    expect(owner.state.snapshot!.sections, isEmpty);
  });
  test(
    'retirement during credential read sends no request and clears state',
    () async {
      final credentials = FakeCredentials()..pending = Completer<String?>();
      final api = FakeDashboardApi();
      final lifecycle = SiteLifecycle();
      final owner = makeController(api, credentials, lifecycle: lifecycle);
      addTearDown(owner.dispose);
      final read = owner.refresh();
      lifecycle.invalidate(site);
      credentials.pending!.complete('key');
      await read;
      expect(api.loads, isEmpty);
      expect(owner.state.snapshot, isNull);
      expect(owner.state.loading, isFalse);
    },
  );
  test(
    'retirement fences completed network response and successor owner',
    () async {
      final api = FakeDashboardApi()..deferLoad = true;
      final lifecycle = SiteLifecycle();
      final owner = makeController(
        api,
        FakeCredentials(),
        lifecycle: lifecycle,
      );
      addTearDown(owner.dispose);
      final old = owner.refresh();
      await flush();
      lifecycle.invalidate(site);
      final successor = makeController(
        FakeDashboardApi(),
        FakeCredentials(),
        lifecycle: lifecycle,
      );
      addTearDown(successor.dispose);
      await successor.refresh();
      api.pendingLoads.single.complete(snapshot);
      await old;
      expect(owner.state.snapshot, isNull);
      expect(successor.state.snapshot, isNotNull);
    },
  );
  test(
    'configuration preserves unknown entries and waits for confirmation',
    () async {
      final api = FakeDashboardApi();
      final owner = makeController(api, FakeCredentials());
      addTearDown(owner.dispose);
      await owner.refresh();
      api.writeGate = Completer<void>();
      final write = owner.configure([
        const DashboardConfiguration('traffic', false),
      ]);
      await flush();
      expect(
        owner.state.snapshot!.configuration!
            .firstWhere((item) => item.id == 'traffic')
            .visible,
        isTrue,
      );
      expect(api.configuration!.last.id, 'plugin_health');
      expect(api.configuration!.last.visible, isFalse);
      api.writeGate!.complete();
      await write;
      expect(owner.state.mutating, isFalse);
    },
  );
  test(
    'configuration admission survives a range change during credential read',
    () async {
      final api = FakeDashboardApi();
      final credentials = FakeCredentials();
      final owner = makeController(api, credentials);
      addTearDown(owner.dispose);
      await owner.refresh();
      credentials.pending = Completer<String?>();
      final write = owner.configure(const [
        DashboardConfiguration('traffic', false),
      ]);
      final read = owner.selectPeriod(DashboardPeriod.last7Days);
      credentials.pending!.complete('key');
      await Future.wait([write, read]);
      expect(api.writes, 1);
      expect(
        api.configuration!
            .firstWhere((section) => section.id == 'traffic')
            .visible,
        isFalse,
      );
      expect(api.configuration!.last.id, 'plugin_health');
      expect(owner.state.period, DashboardPeriod.last7Days);
    },
  );
  test('failed mutation retains confirmed advice and enables retry', () async {
    final api = FakeDashboardApi()..failWrite = true;
    final owner = makeController(api, FakeCredentials());
    addTearDown(owner.dispose);
    await owner.refresh();
    await owner.dismissProblem(snapshot.problems.single);
    expect(owner.state.snapshot!.problems.length, 1);
    expect(owner.state.mutationError, isTrue);
    expect(owner.state.mutating, isFalse);
    api.failWrite = false;
    await owner.dismissProblem(snapshot.problems.single);
    expect(owner.state.snapshot!.problems, isEmpty);
  });
  test(
    'advice dismissal does not cancel a new range read or revive a notice',
    () async {
      final api = FakeDashboardApi();
      final owner = makeController(api, FakeCredentials());
      addTearDown(owner.dispose);
      await owner.refresh();
      api.writeGate = Completer<void>();
      final write = owner.dismissProblem(snapshot.problems.single);
      await flush();
      api.deferLoad = true;
      final read = owner.selectPeriod(DashboardPeriod.last7Days);
      await flush();
      api.writeGate!.complete();
      await write;
      expect(owner.state.loading, isTrue);
      api.pendingLoads.single.complete(snapshot);
      await read;
      expect(owner.state.snapshot!.sections.length, 6);
      expect(owner.state.snapshot!.problems, isEmpty);
      expect(owner.state.period, DashboardPeriod.last7Days);
    },
  );
  test(
    'refreshed advice survives an index that started before refresh',
    () async {
      final api = FakeDashboardApi();
      final owner = makeController(api, FakeCredentials());
      addTearDown(owner.dispose);
      await owner.refresh();
      api.deferLoad = true;
      final read = owner.refresh();
      await flush();
      await owner.refreshProblems();
      api.pendingLoads.single.complete(snapshot);
      await read;
      expect(owner.state.snapshot!.problems.single.message, 'New advice');
    },
  );
}

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

DashboardController makeController(
  FakeDashboardApi api,
  FakeCredentials credentials, {
  bool staff = true,
  bool admin = true,
  SiteLifecycle? lifecycle,
}) => DashboardController(
  api: api,
  credentials: credentials,
  lease: (lifecycle ?? SiteLifecycle()).capture(site),
  siteUrl: site,
  staff: staff,
  admin: admin,
  now: () => DateTime(2026, 10, 25),
);

class FakeCredentials implements ApiCredentialReader {
  int reads = 0;
  Completer<String?>? pending;
  @override
  Future<String?> apiKeyFor(String _) {
    reads++;
    return pending?.future ?? Future.value('key');
  }

  @override
  Future<String> clientId() async => '';
}

class FakeDashboardApi implements DashboardApi {
  final loads = <DashboardRange>[];
  final pendingLoads = <Completer<DashboardSnapshot>>[];
  bool deferLoad = false, failWrite = false;
  int writes = 0;
  Completer<void>? writeGate;
  List<DashboardConfiguration>? configuration;
  @override
  Future<DashboardSnapshot> load({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardRange range,
  }) {
    loads.add(range);
    if (deferLoad) {
      final result = Completer<DashboardSnapshot>();
      pendingLoads.add(result);
      return result.future;
    }
    return Future.value(snapshot);
  }

  @override
  Future<Map<String, DashboardReportResult>> reports({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardRange range,
    required List<DashboardReport> items,
  }) async => {};
  Future<void> write() async {
    writes++;
    if (failWrite) throw StateError('failed');
    await writeGate?.future;
  }

  @override
  Future<void> configure({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required List<DashboardConfiguration> sections,
  }) async {
    configuration = sections;
    await write();
  }

  @override
  Future<void> dismissProblem({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int id,
  }) => write();
  @override
  Future<List<DashboardProblem>> refreshProblems({
    required String siteUrl,
    required String apiKey,
    required String clientId,
  }) async {
    await write();
    return [const DashboardProblem(2, 'New advice', 'high')];
  }
}
