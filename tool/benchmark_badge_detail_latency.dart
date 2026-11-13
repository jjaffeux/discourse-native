import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_badges_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/badges_controller.dart';
import 'package:discourse_plugin_api/testing.dart';

import '../test/support/badge_fixtures.dart';
import '../test/support/fakes.dart' show FakeApiCredentialReader;

const _site = DiscourseInstance(
  url: 'https://forum.example',
  title: 'Forum',
  user: DiscourseUser(username: 'sam'),
);
const _latency = Duration(milliseconds: 30);

Future<void> main() async {
  final times = <int>[];
  for (var i = 0; i < 7; i++) {
    final sample = await _open();
    if (i >= 2) times.add(sample);
  }
  times.sort();
  stdout.writeln(jsonEncode({'open_badge_detail_and_recipients': times[2]}));
  exit(0);
}

Future<int> _open() async {
  final route = BadgeRoute.detail(1);
  final transport = RecordingPluginTransport(
    responders: {
      'GET /badges/1.json': (_) async {
        await Future<void>.delayed(_latency);
        return {'badge': badgeWire};
      },
      'GET /user_badges.json?badge_id=1&offset=0': (_) async {
        await Future<void>.delayed(_latency);
        return badgeGrantsWire(count: 96);
      },
    },
  );
  final controller = BadgesController(
    api: DiscourseBadgesApi(transport),
    credentials: FakeApiCredentialReader()..keys[_site.url] = 'key',
    lifecycle: SiteLifecycle(),
  );
  try {
    final watch = Stopwatch()..start();
    await controller.load(_site, route);
    watch.stop();
    final state = controller.stateFor(_site.url, route);
    if (state.badge?.name != 'Autobiographer' ||
        state.grants.length != 96 ||
        state.nextOffset != 96 ||
        !state.loaded ||
        state.loading ||
        state.error != null ||
        state.recipientsError != null ||
        transport.requests.length != 2 ||
        transport.requests.any((request) => request.apiKey != 'key')) {
      throw StateError('Badge detail and recipients did not publish');
    }
    return watch.elapsedMicroseconds;
  } finally {
    controller.dispose();
  }
}
