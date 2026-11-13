import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/dashboard_api.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/dashboard.dart';
import 'package:discourse_native/src/shell/dashboard_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test/support/dashboard_fixture.dart';

const _site = 'https://forum.example';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final times = <int>[];
  for (var i = 0; i < 7; i++) {
    final sample = await _dashboard();
    if (i >= 2) times.add(sample);
  }
  times.sort();
  stdout.writeln(jsonEncode({'refresh_warm_dashboard': times[2]}));
  exit(0);
}

Future<int> _dashboard() async {
  final now = DateTime(2026, 10, 25);
  final range = DashboardPeriod.last30Days.rangeAt(now);
  final seen = <String>[];
  final transport = DiscourseApi(
    client: MockClient((request) async {
      if (request.headers['user-api-key'] != 'staff-key') {
        throw StateError('Dashboard request lost its staff identity');
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (request.url.path == '/admin/dashboard.json') {
        seen.add('dashboard');
        return http.Response(jsonEncode(dashboardFixture), 200);
      }
      if (request.url.path != '/admin/dashboard/reports/bulk.json') {
        throw StateError('Unexpected dashboard route');
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final filters = body['filters'] as Map<String, dynamic>;
      final from = filters['start_date'];
      final prior = from == range.previous.query['start_date'];
      if (!prior && from != range.query['start_date'] ||
          (body['items'] as List<Object?>).length != 2) {
        throw StateError('Wrong report range or requested items');
      }
      seen.add(prior ? 'previous' : 'current');
      return http.Response(
        jsonEncode({
          'items': [
            for (final identifier in [
              'daily_engaged_users',
              'time_to_first_response',
            ])
              {
                'key': 'core_report:$identifier',
                'data': {
                  'data': [
                    {'x': from, 'y': prior ? 10 : 15},
                  ],
                },
              },
          ],
        }),
        200,
      );
    }),
  );
  final lifecycle = SiteLifecycle();
  final controller = DashboardController(
    api: DiscourseDashboardApi(transport),
    credentials: const _StaffCredentials(),
    lease: lifecycle.capture(_site),
    siteUrl: _site,
    staff: true,
    admin: true,
    now: () => now,
  );
  try {
    await controller.refresh();
    if (controller.state.reports.length != 2) {
      throw StateError("Could not prime the dashboard");
    }
    seen.clear();
    final watch = Stopwatch()..start();
    await controller.refresh();
    watch.stop();
    final state = controller.state;
    final report = state.reports['core_report:daily_engaged_users'];
    if (state.loading ||
        state.error ||
        state.snapshot == null ||
        state.reports.length != 2 ||
        report?.value != 15 ||
        report?.previousValue != 10 ||
        report?.change != 50 ||
        seen.length != 3 ||
        !seen.toSet().containsAll(['dashboard', 'current', 'previous'])) {
      throw StateError('Dashboard did not publish compared report values');
    }
    return watch.elapsedMicroseconds;
  } finally {
    controller.dispose();
    lifecycle.close();
    transport.close();
  }
}

final class _StaffCredentials implements ApiCredentialReader {
  const _StaffCredentials();

  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'staff-key';

  @override
  Future<String> clientId() async => '';
}
