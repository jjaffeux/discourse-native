import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:vm_service/vm_service.dart' as vm;

import 'topic_scroll_raster_profile.dart';

typedef TopicRasterRecordingStarter =
    Future<TopicRasterRecording> Function({required int startUs});

abstract interface class TopicRasterRecording {
  const factory TopicRasterRecording.unavailable(String reason) =
      _UnavailableRecording;

  Future<Map<String, Object?>> finish({
    required int endUs,
    required List<TopicRasterFrame> frames,
  });
}

/// Retains engine events as they arrive, before the VM's ring buffer wraps.
/// The connection, filtering and storage run in a separate isolate. Existing
/// timeline flags and other clients' subscriptions are left untouched.
Future<TopicRasterRecording> startTopicRasterRecording({
  required int startUs,
  Uri? serviceUri,
}) async {
  try {
    if (const bool.fromEnvironment('dart.vm.product')) {
      return const TopicRasterRecording.unavailable('release-build');
    }
    final uri =
        serviceUri ??
        (await Service.getInfo().timeout(
          const Duration(seconds: 2),
        )).serverWebSocketUri;
    if (uri == null) {
      return const TopicRasterRecording.unavailable('vm-service-unavailable');
    }
    final ready = ReceivePort();
    final readyPort = ready.sendPort;
    final result = Isolate.run(() => _recordTimeline(uri, startUs, readyPort))
        .catchError(
          (Object _) => <String, Object?>{
            'status': 'unavailable',
            'reason': 'timeline-worker-failed',
          },
        );
    final control = Future.any<SendPort?>([
      ready.first.then((port) => port as SendPort),
      result.then((_) => null),
    ]).whenComplete(ready.close);
    return _WorkerRecording(control, result);
  } on Object {
    // Service failures can include authenticated URLs. Export fixed reasons.
    return const TopicRasterRecording.unavailable('timeline-start-failed');
  }
}

final class _UnavailableRecording implements TopicRasterRecording {
  const _UnavailableRecording(this.reason);

  final String reason;

  @override
  Future<Map<String, Object?>> finish({
    required int endUs,
    required List<TopicRasterFrame> frames,
  }) async => {'status': 'unavailable', 'reason': reason};
}

final class _WorkerRecording implements TopicRasterRecording {
  _WorkerRecording(this.control, this.result);

  final Future<SendPort?> control;
  final Future<Map<String, Object?>> result;
  bool _finished = false;

  @override
  Future<Map<String, Object?>> finish({
    required int endUs,
    required List<TopicRasterFrame> frames,
  }) async {
    if (!_finished) {
      _finished = true;
      (await control)?.send((endUs: endUs, frames: frames));
    }
    return result;
  }
}

Future<Map<String, Object?>> _recordTimeline(
  Uri uri,
  int startUs,
  SendPort ready,
) async {
  final commands = ReceivePort();
  // Publish before connecting so an immediate Stop or Dispose is not lost.
  ready.send(commands.sendPort);
  final stop = commands.first.catchError(
    (Object _) => (endUs: startUs, frames: <TopicRasterFrame>[]),
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  vm.VmService? service;
  StreamSubscription<vm.Event>? subscription;
  try {
    final socket = await WebSocket.connect(
      uri.toString(),
      customClient: client,
    ).timeout(const Duration(seconds: 3));
    service = vm.VmService(socket, socket.add, disposeHandler: socket.close);
    final buffer = TopicRasterTraceBuffer(startUs: startUs);
    var streamedEventCount = 0;
    subscription = service.onTimelineEvent.listen((event) {
      final before = buffer.length;
      buffer.add(event.timelineEvents ?? const []);
      streamedEventCount += buffer.length - before;
    }, onError: (Object _) {});
    await service
        .streamListen(vm.EventStreams.kTimeline)
        .timeout(const Duration(seconds: 3));
    final request = await stop as ({int endUs, List<TopicRasterFrame> frames});
    // A partial native event block may not have reached the stream yet. Merge
    // the retained buffer tail on Stop and deduplicate overlapping events.
    var tailAvailable = true;
    try {
      final tail = await service
          .getVMTimeline(
            timeOriginMicros: startUs,
            timeExtentMicros: request.endUs - startUs,
          )
          .timeout(const Duration(seconds: 4));
      buffer.add(tail.traceEvents ?? const []);
    } on Object {
      tailAvailable = false;
    }
    return {
      ...summarizeTopicRasterProfile(
        buffer.timeline(endUs: request.endUs),
        request.frames,
      ),
      'source': 'live-stream',
      'streamedEventCount': streamedEventCount,
      'retainedEventCount': buffer.length,
      'discardedEventCount': buffer.discardedEventCount,
      'tailAvailable': tailAvailable,
    };
  } on Object {
    return const {'status': 'unavailable', 'reason': 'timeline-stream-failed'};
  } finally {
    commands.close();
    try {
      await subscription?.cancel();
      await service?.dispose();
    } on Object {
      // A closing debugger connection must not discard a completed summary.
    }
    client.close(force: true);
  }
}
