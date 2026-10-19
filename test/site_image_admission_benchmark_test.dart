import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/fakes.dart';

void main() {
  test('post image admission over a shared constrained link', () async {
    final results = <Map<String, Object>>[];
    for (final scenario in ['gallery', 'scroll']) {
      final client = _Link();
      final repository = SiteImageRepository(
        credentials: FakeApiCredentialReader()
          ..keys['https://forum.example'] = 'benchmark-key',
        lifecycle: SiteLifecycle(),
        client: client,
      );
      final loads = <Future<void>>[];
      var completed = 0;
      var failed = 0;
      var usefulReadyMs = 0;
      var usefulDone = 0;
      var obsoleteBytes = 0;
      var deliveredBytes = 0;
      final usefulStart = scenario == 'gallery' ? 0 : 32;
      void enqueue(int start, int count) {
        for (var index = start; index < start + count; index++) {
          final useful = index >= usefulStart && index < usefulStart + 4;
          loads.add(
            repository
                .load(
                  siteUrl: 'https://forum.example',
                  url: 'https://forum.example/image-$index',
                )
                .then((image) {
                  completed++;
                  if (image == null ||
                      image.bytes.length != _Link.imageBytes ||
                      image.bytes.any((byte) => byte != 1)) {
                    failed++;
                    return;
                  }
                  deliveredBytes += image.bytes.length;
                  if (scenario == 'scroll' && index < usefulStart) {
                    obsoleteBytes += image.bytes.length;
                  }
                  if (useful && ++usefulDone == 4) {
                    usefulReadyMs = client.timeMs;
                  }
                }),
          );
        }
      }

      enqueue(0, scenario == 'gallery' ? 32 : 16);
      await Future<void>.delayed(Duration.zero);
      while (completed < (scenario == 'gallery' ? 32 : 48)) {
        if (scenario == 'scroll' && client.timeMs == 250) enqueue(16, 16);
        if (scenario == 'scroll' && client.timeMs == 500) enqueue(32, 16);
        client.tick();
        await Future<void>.delayed(Duration.zero);
        if (client.timeMs > 20000) fail('link did not drain');
      }
      await Future.wait(loads);
      expect(failed, 0);
      expect(usefulDone, 4);
      expect(client.wireBytes, completed * _Link.imageBytes);
      results.add({
        'scenario': scenario,
        'usefulBytesReadyMs': usefulReadyMs,
        'allBytesReadyMs': client.timeMs,
        'peakActiveTransfers': client.peakActive,
        'peakPartialBodyBytes': client.peakPartialBytes,
        'deliveredPayloadBytes': deliveredBytes,
        'obsoleteDownloadedBytes': obsoleteBytes,
        'wireBytes': client.wireBytes,
        'completed': completed,
        'failed': failed,
      });
      repository.dispose();
      client.close();
    }
    final output = Platform.environment['POST_IMAGE_BENCHMARK_OUTPUT'];
    if (output != null) File(output).writeAsStringSync(jsonEncode(results));
  });
}

final class _Link extends http.BaseClient {
  static const imageBytes = 64 * 1024;
  static const _bytesPerTick = 512 * 1024 ~/ 100;
  final _active = <_Transfer>[];
  var timeMs = 0;
  var peakActive = 0;
  var peakPartialBytes = 0;
  var wireBytes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.headers['User-Api-Key'], 'benchmark-key');
    final transfer = _Transfer();
    transfer.body
      ..onListen = () {
        _active.add(transfer);
        peakActive = math.max(peakActive, _active.length);
      }
      ..onCancel = () => _active.remove(transfer);
    return http.StreamedResponse(
      transfer.body.stream,
      200,
      contentLength: imageBytes,
      request: request,
    );
  }

  void tick() {
    timeMs += 10;
    if (_active.isEmpty) return;
    final share = _bytesPerTick ~/ _active.length;
    for (final transfer in _active.toList()) {
      final count = math.min(share, imageBytes - transfer.sent);
      transfer.sent += count;
      wireBytes += count;
      transfer.body.add(Uint8List(count)..fillRange(0, count, 1));
      if (transfer.sent == imageBytes) {
        _active.remove(transfer);
        unawaited(transfer.close());
      }
    }
    peakPartialBytes = math.max(
      peakPartialBytes,
      _active.fold<int>(0, (sum, transfer) => sum + transfer.sent),
    );
  }
}

final class _Transfer {
  final body = StreamController<List<int>>();
  var sent = 0;

  Future<void> close() => body.close();
}
