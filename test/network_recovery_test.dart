import 'dart:io';

import 'package:discourse_native/src/data/origin_reachability.dart';
import 'package:discourse_native/src/shell/network_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

const _neverConnected = SocketException("Failed host lookup: 'forum.example'");

final class _Reachability implements SiteReachabilityApi {
  @override
  final OriginReachability reachability = OriginReachability();

  final Set<String> coolingDown = {};

  @override
  bool isCoolingDown(String siteUrl) => coolingDown.contains(siteUrl);
}

void main() {
  const site = 'https://forum.example';
  final forum = Uri.parse('$site/latest.json');
  final other = Uri.parse('https://other.example/latest.json');

  late _Reachability api;
  late String? current;
  late List<String> reloads;
  late NetworkRecovery recovery;

  void lose(Uri url) => api.reachability.failed(
    url,
    _neverConnected,
    api.reachability.dispatched(),
  );
  void regain(Uri url) =>
      api.reachability.succeeded(url, api.reachability.dispatched());

  setUp(() {
    api = _Reachability();
    current = site;
    reloads = [];
    recovery = NetworkRecovery(
      api: api,
      currentSiteUrl: () => current,
      reload: reloads.add,
    )..attach();
  });

  tearDown(() {
    recovery.dispose();
    api.reachability.dispose();
  });

  test('the current site answering again reloads its failed loads', () {
    lose(forum);
    expect(reloads, isEmpty);

    regain(forum);

    expect(reloads, [site]);
  });

  test('another origin answering again reloads nothing', () {
    lose(other);
    regain(other);

    expect(reloads, isEmpty);
  });

  test('a site that was never away is not reloaded by its responses', () {
    regain(forum);
    regain(forum);

    expect(reloads, isEmpty);
  });

  test('no site, or one that cannot load, reloads nothing', () {
    current = null;
    lose(forum);
    regain(forum);
    recovery.resumed();

    expect(reloads, isEmpty);
  });

  test('returning to a reachable site reloads its failed loads', () {
    recovery.resumed();

    expect(reloads, [site]);
  });

  test('returning to an unreachable site probes it instead', () async {
    final probed = <Uri>[];
    api.reachability.probe = (origin) async => probed.add(origin);
    lose(forum);

    recovery.resumed();
    await pumpEventQueue();

    expect(reloads, isEmpty);
    expect(probed, [Uri.parse(site)]);

    regain(forum);
    expect(reloads, [site]);
  });

  test('nothing is reloaded while the site is rate limiting', () {
    api.coolingDown.add(site);

    recovery.resumed();
    lose(forum);
    regain(forum);

    expect(reloads, isEmpty);

    api.coolingDown.clear();
    recovery.resumed();
    expect(reloads, [site]);
  });

  test('a disposed owner neither listens nor reloads', () {
    lose(forum);
    recovery.dispose();

    regain(forum);
    recovery.resumed();

    expect(reloads, isEmpty);
  });

  test('held work can wait on a site through the same signal', () {
    final origins = <String>[];
    final remove = recovery.onSiteRecovered(origins.add);

    lose(other);
    regain(other);
    remove();
    lose(other);
    regain(other);

    expect(origins, ['https://other.example']);
  });
}
