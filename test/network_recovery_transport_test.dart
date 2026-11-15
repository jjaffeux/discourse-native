import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/origin_reachability.dart';
import 'package:discourse_native/src/data/site_lookup_failure.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real sockets on loopback: a closed port refuses the connection, which is
/// the kernel's own proof that nothing was sent.
void main() {
  late HttpServer server;
  late int port;
  late List<String> served;
  late OriginReachability reachability;
  late DiscourseTransport transport;

  Future<void> listen() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.listen((request) async {
      served.add('${request.method} ${request.uri.path}');
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"ok":true}');
      await request.response.close();
    });
  }

  String site() => 'http://127.0.0.1:$port';
  Future<Map<String, dynamic>> latest() =>
      transport.getObject(Uri.parse('${site()}/latest.json'), siteUrl: site());

  setUp(() async {
    served = [];
    port = 0;
    await listen();
    port = server.port;
    reachability = OriginReachability(
      firstProbeDelay: const Duration(milliseconds: 60),
      maximumProbeDelay: const Duration(milliseconds: 120),
    );
    transport = DiscourseTransport(
      SafeHttpClient.create(),
      const Duration(seconds: 5),
      1024 * 1024,
      coordinator: DiscourseRequestCoordinator(
        reachability: reachability,
        neverConnectedRetryDelay: () => const Duration(milliseconds: 40),
      ),
    );
  });

  tearDown(() async {
    transport.close();
    reachability.dispose();
    await server.close(force: true);
  });

  test('a refused GET marks the site unreachable, and it is probed until it '
      'answers', () async {
    expect(await latest(), {'ok': true});
    await server.close(force: true);
    served.clear();

    // The kept-alive connection breaks under a request that may have been
    // written to it, so that failure proves nothing and is not sent again.
    await expectLater(
      latest(),
      throwsA(
        isA<SiteLookupException>().having(
          (error) => connectionNeverOpened(error.cause!),
          'never connected',
          isFalse,
        ),
      ),
    );
    expect(reachability.isReachable(site()), isTrue);

    await expectLater(
      latest(),
      throwsA(
        isA<SiteLookupException>().having(
          (error) => connectionNeverOpened(error.cause!),
          'never connected',
          isTrue,
        ),
      ),
    );
    expect(reachability.isReachable(site()), isFalse);

    final recovered = Completer<String>();
    reachability.onRecovered(recovered.complete);
    await listen();

    expect(await recovered.future.timeout(const Duration(seconds: 5)), site());
    expect(reachability.isReachable(site()), isTrue);
    expect(served, ['HEAD /srv/status']);
    expect(await latest(), {'ok': true});
  });

  test(
    'a GET refused once is answered by its retry without an outage',
    () async {
      await server.close(force: true);
      var changes = 0;
      reachability.addListener(() => changes++);

      final pending = latest();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await listen();

      expect(await pending, {'ok': true});
      expect(served, ['GET /latest.json']);
      expect(changes, 0);
    },
  );
}
