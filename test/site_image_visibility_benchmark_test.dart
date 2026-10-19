import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:discourse_native/src/data/media_request_coordinator.dart';
import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/fakes.dart';
import 'support/post_image_visibility_benchmark_request.dart';

void main() {
  test('visible post image delivery over a shared constrained link', () async {
    final useLeases = Platform.environment['POST_IMAGE_LEASES'] == '1';
    final scenarios = <Map<String, Object?>>[];
    for (final name in ['scroll16', 'promotion32']) {
      final workload = _Workload(name, useLeases: useLeases);
      try {
        scenarios.add(await workload.run());
      } finally {
        workload.close();
      }
    }
    final output = Platform.environment['POST_IMAGE_VISIBILITY_OUTPUT'];
    final results = {
      'revision': Platform.environment['POST_IMAGE_REVISION'] ?? _revision(),
      'adapter': useLeases ? 'consumer-leases' : 'load-without-cancellation',
      'model': {
        'bytesPerSecond': _Link.bytesPerSecond,
        'imageBytes': _Link.imageBytes,
        'tickMs': _Link.tickMs,
        'headerDelayMs': _Link.headerDelayMs,
        'timeSource': 'explicit-link-ticks',
        'partialBuffers': 'sent bytes in unfinished active bodies',
      },
      'scenarios': scenarios,
    };
    if (output != null) {
      File(
        output,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    }
  });
}

String _revision() {
  final result = Process.runSync('git', ['rev-parse', 'HEAD']);
  return result.exitCode == 0 ? '${result.stdout}'.trim() : 'unknown';
}

final class _Workload {
  _Workload(this.name, {required this.useLeases}) {
    repository = SiteImageRepository(
      credentials: FakeApiCredentialReader(clientIdValue: 'benchmark-client')
        ..keys[siteUrl] = 'benchmark-key',
      lifecycle: SiteLifecycle(),
      client: link,
    );
  }

  static const siteUrl = 'https://forum.example';
  final String name;
  final bool useLeases;
  final link = _Link();
  late final SiteImageRepository repository;
  final consumers = <_Consumer>[];
  int usefulReadyMs = -1;
  int usefulDone = 0;
  int settled = 0;
  int validatedBytes = 0;
  int checksum = 0;
  int usefulChecksum = 0;

  int get usefulStart => name == 'scroll16' ? 32 : 24;
  int get visibleAtMs => name == 'scroll16' ? 500 : 250;
  int get expectedConsumers => name == 'scroll16' ? 48 : 32;

  Future<Map<String, Object?>> run() async {
    if (name == 'scroll16') {
      _enqueue(0, 16, firstFourVisible: true);
    } else {
      _enqueue(0, 32);
    }
    await _settle();
    while (settled < expectedConsumers) {
      if (name == 'scroll16' && (link.timeMs == 250 || link.timeMs == 500)) {
        for (final consumer in consumers) {
          if (consumer.releasedAtMs == null) _release(consumer);
        }
        _enqueue(link.timeMs == 250 ? 16 : 32, 16, firstFourVisible: true);
        await _settle();
      }
      if (name == 'promotion32' && link.timeMs == 250) {
        for (final consumer in consumers.where(
          (consumer) => _useful(consumer.index),
        )) {
          consumer.visibleAtMs = link.timeMs;
          consumer.request.setVisible(true);
        }
        await _settle();
      }
      link.tick();
      await _settle();
      if (link.timeMs > 20000) fail('$name did not settle');
    }
    await Future.wait(consumers.map((consumer) => consumer.done));
    expect(consumers.length, expectedConsumers);
    expect(
      consumers.where((consumer) => consumer.outcome == 'failed'),
      isEmpty,
    );
    expect(usefulDone, 4);
    expect(link.activeCount, 0);
    final cancelled = consumers
        .where((consumer) => consumer.outcome == 'cancelled')
        .length;
    expect(cancelled, useLeases && name == 'scroll16' ? 32 : 0);
    expect(
      link.wireBytes,
      link.transfers.fold<int>(0, (sum, transfer) => sum + transfer.sentBytes),
    );
    expect(link.wireBytes, validatedBytes + link.cancelledPartialWireBytes);
    expect(link.wireBytes, lessThanOrEqualTo(link.capacityBytes));
    expect(
      validatedBytes,
      consumers.where((consumer) => consumer.outcome == 'success').length *
          _Link.imageBytes,
    );
    final allReadyMs = link.timeMs;
    for (final consumer in consumers) {
      if (consumer.releasedAtMs == null) _release(consumer);
    }
    final revisits = await _revisitCache();
    return {
      'scenario': name,
      'usefulBytesReadyMs': usefulReadyMs,
      'usefulCompletionDelayMs': usefulReadyMs - visibleAtMs,
      'allConsumersSettledMs': allReadyMs,
      'requested': consumers.length,
      'completed': consumers
          .where((consumer) => consumer.outcome == 'success')
          .length,
      'cancelled': consumers
          .where((consumer) => consumer.outcome == 'cancelled')
          .length,
      'failed': consumers
          .where((consumer) => consumer.outcome == 'failed')
          .length,
      'validatedPayloadBytes': validatedBytes,
      'validatedPayloadChecksum': checksum,
      'usefulValidatedPayloadBytes': usefulDone * _Link.imageBytes,
      'usefulValidatedPayloadChecksum': usefulChecksum,
      'startedRequests': link.transfers.length,
      'wireBytes': link.wireBytes,
      'obsoleteWireBytesAfterRelease': link.obsoleteWireBytes,
      'cancelledPartialWireBytes': link.cancelledPartialWireBytes,
      'cancelledTransfers': link.transfers
          .where((transfer) => transfer.cancelledAtMs != null)
          .length,
      'cancelledBeforeHeaders': link.transfers
          .where(
            (transfer) =>
                transfer.cancelledAtMs != null && transfer.headersAtMs == null,
          )
          .length,
      'peakActiveTransfers': link.peakActive,
      'peakPartialBodyBytes': link.peakPartialBytes,
      'peakObsoletePartialBodyBytes': link.peakObsoletePartialBytes,
      'capacityBytesThroughDrain': allReadyMs * _Link.bytesPerSecond ~/ 1000,
      'usefulQueueWaitMs': [
        for (final transfer in link.transfers.where(
          (transfer) => _useful(transfer.index),
        ))
          transfer.startedAtMs - consumers[transfer.index].requestedAtMs,
      ],
      'usefulQueueWaitAfterVisibleMs': [
        for (final transfer in link.transfers.where(
          (transfer) => _useful(transfer.index),
        ))
          math.max(0, transfer.startedAtMs - visibleAtMs),
      ],
      ...revisits,
      'consumers': consumers.map((consumer) => consumer.toJson()).toList(),
      'transfers': link.transfers.map((transfer) => transfer.toJson()).toList(),
      'timelineColumns': [
        'timeMs',
        'wireBytes',
        'obsoleteWireBytes',
        'activeTransfers',
        'partialBodyBytes',
      ],
      'timeline': link.timeline,
    };
  }

  bool _useful(int index) => index >= usefulStart && index < usefulStart + 4;

  void _enqueue(int start, int count, {bool firstFourVisible = false}) {
    for (var index = start; index < start + count; index++) {
      final visible = firstFourVisible && index < start + 4;
      final consumer = _Consumer(
        index,
        requestedAtMs: link.timeMs,
        visibleAtMs: visible ? link.timeMs : null,
        request: _request(index, visible: visible),
      );
      consumers.add(consumer);
      consumer.done = consumer.request.result.then<void>(
        (image) {
          consumer.completedAtMs = link.timeMs;
          if (image == null) {
            consumer.outcome = consumer.releasedAtMs == null
                ? 'failed'
                : 'cancelled';
            if (consumer.outcome == 'failed') {
              consumer.error = 'unreleased request returned null';
            }
          } else {
            final error = _validate(image, index);
            consumer.outcome = error == null ? 'success' : 'failed';
            consumer.error = error;
            if (error == null) {
              validatedBytes += image.bytes.length;
              for (final byte in image.bytes) {
                checksum += byte;
                if (_useful(index)) usefulChecksum += byte;
              }
              if (_useful(index) && ++usefulDone == 4) {
                usefulReadyMs = link.timeMs;
              }
            }
          }
          settled++;
        },
        onError: (Object error, StackTrace stackTrace) {
          consumer.completedAtMs = link.timeMs;
          final expectedCancellation =
              consumer.releasedAtMs != null &&
              (error is http.RequestAbortedException ||
                  error is MediaRequestCancelledException);
          consumer.outcome = expectedCancellation ? 'cancelled' : 'failed';
          if (!expectedCancellation) consumer.error = '$error\n$stackTrace';
          settled++;
        },
      );
    }
  }

  PostImageBenchmarkRequest _request(int index, {required bool visible}) =>
      postImageBenchmarkRequest(
        repository,
        siteUrl: siteUrl,
        url: '$siteUrl/image-$index',
        useLeases: useLeases,
        visible: visible,
      );

  void _release(_Consumer consumer) {
    consumer.releasedAtMs = link.timeMs;
    link.releasedAtMs[consumer.index] = link.timeMs;
    consumer.request.release();
  }

  Future<Map<String, Object?>> _revisitCache() async {
    final before = link.wireBytes;
    final starts = link.transfers.length;
    final startMs = link.timeMs;
    final requests = <PostImageBenchmarkRequest>[];
    final results = <Future<void>>[];
    var completed = 0;
    var bytes = 0;
    for (var index = usefulStart; index < usefulStart + 4; index++) {
      expect(
        repository.isCached(siteUrl: siteUrl, url: '$siteUrl/image-$index'),
        isTrue,
      );
      final request = _request(index, visible: true);
      requests.add(request);
      results.add(
        request.result.then((image) {
          expect(image, isNotNull);
          expect(_validate(image!, index), isNull);
          bytes += image.bytes.length;
          completed++;
        }),
      );
    }
    await _settle();
    expect(
      completed,
      4,
      reason: 'cached revisits must finish without another link tick',
    );
    await Future.wait(results);
    for (final request in requests) {
      request.release();
    }
    expect(link.wireBytes - before, 0);
    expect(link.transfers.length - starts, 0);
    return {
      'cacheRevisitCompleted': completed,
      'cacheRevisitValidatedBytes': bytes,
      'cacheRevisitWireBytes': link.wireBytes - before,
      'cacheRevisitDurationMs': link.timeMs - startMs,
    };
  }

  String? _validate(SiteImageBytes image, int index) {
    if (image.bytes.length != _Link.imageBytes) return 'incorrect image length';
    for (var offset = 0; offset < image.bytes.length; offset++) {
      if (image.bytes[offset] != _payloadByte(index, offset)) {
        return 'incorrect payload for image $index at byte $offset';
      }
    }
    return null;
  }

  Future<void> _settle() => Future<void>.delayed(Duration.zero);

  void close() {
    repository.dispose();
    link.close();
  }
}

final class _Consumer {
  _Consumer(
    this.index, {
    required this.requestedAtMs,
    required this.request,
    this.visibleAtMs,
  });
  final int index;
  final int requestedAtMs;
  final PostImageBenchmarkRequest request;
  int? visibleAtMs;
  int? releasedAtMs;
  int? completedAtMs;
  String? outcome;
  String? error;
  late final Future<void> done;

  Map<String, Object?> toJson() => {
    'index': index,
    'requestedAtMs': requestedAtMs,
    'visibleAtMs': visibleAtMs,
    'releasedAtMs': releasedAtMs,
    'completedAtMs': completedAtMs,
    'outcome': outcome,
    if (error != null) 'error': error,
  };
}

int _payloadByte(int index, int offset) => (index * 17 + offset) % 251 + 1;

enum _TransferState {
  waitingHeaders,
  waitingBody,
  streaming,
  complete,
  cancelled,
}

final class _Link extends http.BaseClient {
  static const bytesPerSecond = 512 * 1024;
  static const imageBytes = 64 * 1024;
  static const tickMs = 10;
  static const headerDelayMs = 20;
  final transfers = <_Transfer>[];
  final releasedAtMs = <int, int>{};
  final timeline = <List<int>>[];
  int timeMs = 0;
  int wireBytes = 0;
  int obsoleteWireBytes = 0;
  int peakActive = 0;
  int peakPartialBytes = 0;
  int peakObsoletePartialBytes = 0;
  int _capacityRemainder = 0;
  int _rotation = 0;
  bool _closed = false;

  int get capacityBytes => timeMs * bytesPerSecond ~/ 1000;
  int get activeCount =>
      transfers.where((transfer) => !transfer.terminal).length;
  int get cancelledPartialWireBytes => transfers
      .where((transfer) => transfer.cancelledAtMs != null)
      .fold(0, (sum, transfer) => sum + transfer.sentBytes);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) throw StateError('Link is closed');
    expect(request.url.origin, _Workload.siteUrl);
    expect(request.headers['User-Api-Key'], 'benchmark-key');
    expect(request.headers['User-Api-Client-Id'], 'benchmark-client');
    expect(request.followRedirects, isFalse);
    expect(request, isA<http.AbortableRequest>());
    final index = int.parse(request.url.path.substring('/image-'.length));
    final transfer = _Transfer(index, request: request, startedAtMs: timeMs);
    transfers.add(transfer);
    peakActive = math.max(peakActive, activeCount);
    transfer.body
      ..onListen = () {
        if (!transfer.terminal) transfer.state = _TransferState.streaming;
      }
      ..onCancel = () => _cancel(transfer, 'subscription');
    final abort = (request as http.AbortableRequest).abortTrigger;
    if (abort != null) {
      unawaited(abort.then((_) => _cancel(transfer, 'abort-trigger')));
    }
    return transfer.response.future;
  }

  void tick() {
    timeMs += tickMs;
    for (final transfer in transfers) {
      if (transfer.state != _TransferState.waitingHeaders ||
          timeMs - transfer.startedAtMs < headerDelayMs) {
        continue;
      }
      transfer.state = _TransferState.waitingBody;
      transfer.headersAtMs = timeMs;
      transfer.response.complete(
        http.StreamedResponse(
          transfer.body.stream,
          200,
          contentLength: imageBytes,
          request: transfer.request,
          headers: const {'content-type': 'application/octet-stream'},
        ),
      );
    }
    _capacityRemainder += bytesPerSecond * tickMs;
    var budget = _capacityRemainder ~/ 1000;
    _capacityRemainder %= 1000;
    var active = transfers
        .where((transfer) => transfer.state == _TransferState.streaming)
        .toList();
    if (active.isNotEmpty) {
      final rotation = _rotation++ % active.length;
      active = [...active.skip(rotation), ...active.take(rotation)];
    }
    while (budget > 0 && active.isNotEmpty) {
      final share = budget ~/ active.length;
      final remainder = budget % active.length;
      for (var index = 0; index < active.length; index++) {
        final transfer = active[index];
        final count = math.min(
          share + (index < remainder ? 1 : 0),
          imageBytes - transfer.sentBytes,
        );
        if (count == 0) continue;
        final chunk = Uint8List(count);
        for (var offset = 0; offset < count; offset++) {
          chunk[offset] = _payloadByte(
            transfer.index,
            transfer.sentBytes + offset,
          );
        }
        transfer.firstByteAtMs ??= timeMs;
        transfer.lastByteAtMs = timeMs;
        transfer.sentBytes += count;
        wireBytes += count;
        budget -= count;
        if (releasedAtMs.containsKey(transfer.index)) {
          transfer.obsoleteWireBytes += count;
          obsoleteWireBytes += count;
        }
        transfer.body.add(chunk);
        if (transfer.sentBytes == imageBytes) {
          transfer.state = _TransferState.complete;
          transfer.completedAtMs = timeMs;
          unawaited(transfer.close());
        }
      }
      active = active
          .where((transfer) => transfer.state == _TransferState.streaming)
          .toList();
    }
    final partial = transfers
        .where((transfer) => !transfer.terminal)
        .fold<int>(0, (sum, transfer) => sum + transfer.sentBytes);
    final obsoletePartial = transfers
        .where(
          (transfer) =>
              !transfer.terminal && releasedAtMs.containsKey(transfer.index),
        )
        .fold<int>(0, (sum, transfer) => sum + transfer.sentBytes);
    peakPartialBytes = math.max(peakPartialBytes, partial);
    peakObsoletePartialBytes = math.max(
      peakObsoletePartialBytes,
      obsoletePartial,
    );
    timeline.add([timeMs, wireBytes, obsoleteWireBytes, activeCount, partial]);
  }

  void _cancel(_Transfer transfer, String reason) {
    if (transfer.terminal) return;
    transfer.state = _TransferState.cancelled;
    transfer.cancelledAtMs = timeMs;
    transfer.cancelReason = reason;
    if (!transfer.response.isCompleted) {
      transfer.response.completeError(
        http.RequestAbortedException(transfer.request.url),
      );
    } else if (reason != 'subscription') {
      transfer.body.addError(
        http.RequestAbortedException(transfer.request.url),
      );
    }
    unawaited(transfer.close());
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final transfer in transfers) {
      _cancel(transfer, 'client-close');
    }
  }
}

final class _Transfer {
  _Transfer(this.index, {required this.request, required this.startedAtMs});
  final int index;
  final http.BaseRequest request;
  final int startedAtMs;
  final body = StreamController<List<int>>();
  final response = Completer<http.StreamedResponse>();
  _TransferState state = _TransferState.waitingHeaders;
  int sentBytes = 0;
  int obsoleteWireBytes = 0;
  int? headersAtMs;
  int? firstByteAtMs;
  int? lastByteAtMs;
  int? completedAtMs;
  int? cancelledAtMs;
  String? cancelReason;

  Future<void> close() => body.close();

  bool get terminal =>
      state == _TransferState.complete || state == _TransferState.cancelled;

  Map<String, Object?> toJson() => {
    'index': index,
    'startedAtMs': startedAtMs,
    'headersAtMs': headersAtMs,
    'firstByteAtMs': firstByteAtMs,
    'lastByteAtMs': lastByteAtMs,
    'completedAtMs': completedAtMs,
    'cancelledAtMs': cancelledAtMs,
    'cancelReason': cancelReason,
    'sentBytes': sentBytes,
    'obsoleteWireBytesAfterRelease': obsoleteWireBytes,
  };
}
