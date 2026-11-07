import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/report_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/dashboard.dart';
import 'package:discourse_native/src/models/report.dart';
import 'package:discourse_native/src/shell/report_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _report = DashboardReport(
  source: 'test',
  identifier: 'members',
  title: 'Members',
  path: '/members',
);

void main() {
  test('report filters own inputs before credentials finish', () async {
    final api = _Reports();
    final credentials = _Credentials()..key = Completer<String?>();
    final owner = _controller(api, credentials);
    addTearDown(owner.dispose);
    final groups = <String>['staff'];
    final criteria = <String, Object?>{'groups': groups};
    final pending = owner.filter('criteria', criteria);
    groups[0] = 'everyone';
    criteria['extra'] = true;
    credentials.key!.complete('key');
    await pending;
    expect(api.filters.single, {
      'criteria': {
        'groups': ['staff'],
      },
    });
    await owner.refresh();
    expect(api.filters.last, {
      'criteria': {
        'groups': ['staff'],
      },
    });
  });

  test('report providers receive immutable query values', () async {
    final api = _Reports();
    final owner = _controller(api, _Credentials());
    addTearDown(owner.dispose);
    await owner.filter('groups', <String>['staff']);
    final values = api.filters.single;
    expect(() => values['groups'] = ['everyone'], throwsUnsupportedError);
    expect(() => (values['groups']! as List).clear(), throwsUnsupportedError);
    await owner.refresh();
    expect(api.filters.last, {
      'groups': ['staff'],
    });
  });

  test(
    'unsupported filter values fail before replacing the current query',
    () async {
      final api = _Reports();
      final owner = _controller(api, _Credentials());
      addTearDown(owner.dispose);
      await owner.filter('groups', <String>['staff']);
      await expectLater(owner.filter('groups', Object()), throwsArgumentError);
      await owner.refresh();
      expect(api.filters, hasLength(2));
      expect(api.filters.last, {
        'groups': ['staff'],
      });
    },
  );
}

ReportController _controller(ReportApi api, ApiCredentialReader credentials) =>
    ReportController(
      api: api,
      credentials: credentials,
      lease: SiteLifecycle().capture(_site),
      siteUrl: _site,
      report: _report,
      range: DashboardRange(
        DateTime.utc(2026, 10, 1),
        DateTime.utc(2026, 10, 3),
      ),
    );

final class _Credentials implements ApiCredentialReader {
  Completer<String?>? key;
  @override
  Future<String?> apiKeyFor(String siteUrl) =>
      key?.future ?? Future.value('key');
  @override
  Future<String> clientId() async => 'client';
}

final class _Reports implements ReportApi {
  final filters = <Map<String, Object?>>[];
  @override
  Future<ReportDetails> load({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardReport report,
    required DashboardRange range,
    required Map<String, Object?> filters,
  }) async {
    this.filters.add(filters);
    return ReportDetails(result: DashboardReportResult());
  }
}
