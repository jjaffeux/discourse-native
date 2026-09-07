import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:vm_service/vm_service.dart' as vm;

typedef TopicCpuFrame = ({int frameNumber, int startUs, int endUs});

typedef TopicCpuProfileCollector =
    Future<Map<String, Object?>> Function({
      required int startUs,
      required int endUs,
      required List<TopicCpuFrame> slowFrames,
    });

/// Reads existing samples only on export. No profiler flags, buffers, or
/// recording settings are changed, and no connection is opened while scrolling.
Future<Map<String, Object?>> collectTopicCpuProfile({
  required int startUs,
  required int endUs,
  required List<TopicCpuFrame> slowFrames,
}) async {
  if (const bool.fromEnvironment('dart.vm.product')) {
    return const {'status': 'unavailable', 'reason': 'release-build'};
  }
  final isolateId = Service.getIsolateId(Isolate.current);
  final info = await Service.getInfo().timeout(const Duration(seconds: 2));
  final uri = info.serverWebSocketUri;
  if (uri == null || isolateId == null) {
    return const {'status': 'unavailable', 'reason': 'vm-service-unavailable'};
  }
  // Keep the service URL, raw stacks, parsing, and aggregation off the UI
  // isolate. Only bounded summaries of function names return to the caller.
  return Isolate.run(
    () => _readProfile(uri, isolateId, startUs, endUs, slowFrames),
  );
}

Future<Map<String, Object?>> _readProfile(
  Uri uri,
  String isolateId,
  int startUs,
  int endUs,
  List<TopicCpuFrame> slowFrames,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  vm.VmService? service;
  try {
    final socket = await WebSocket.connect(
      uri.toString(),
      customClient: client,
    ).timeout(const Duration(seconds: 3));
    service = vm.VmService(socket, socket.add, disposeHandler: socket.close);
    final samples = await service
        .getCpuSamples(isolateId, startUs, endUs - startUs)
        .timeout(const Duration(seconds: 4));
    return summarizeTopicCpuProfile(
      samples,
      startUs: startUs,
      endUs: endUs,
      slowFrames: slowFrames,
    );
  } on vm.RPCError catch (error) {
    return {
      'status': 'unavailable',
      'reason': error.code == 100 ? 'profiler-disabled' : 'vm-request-failed',
    };
  } on Object {
    // Exceptions may contain authenticated debugger URLs or local paths.
    return const {'status': 'unavailable', 'reason': 'vm-connection-failed'};
  } finally {
    await service?.dispose();
    client.close(force: true);
  }
}

/// CPU timestamps and Flutter frame timings share Timeline.now's monotonic
/// clock. Match only the UI portion of over-budget frames with topic activity.
Map<String, Object?> summarizeTopicCpuProfile(
  vm.CpuSamples profile, {
  required int startUs,
  required int endUs,
  required List<TopicCpuFrame> slowFrames,
}) {
  final functions = [
    for (final function in profile.functions ?? <vm.ProfileFunction>[])
      _functionName(function),
  ];
  final frames = List.of(slowFrames)
    ..sort((a, b) => a.startUs.compareTo(b.startUs));
  final capture = _CpuSamples();
  final slow = _CpuSamples();
  final byFrame = <int, _CpuSamples>{};
  for (final sample in profile.samples ?? <vm.CpuSample>[]) {
    final timestamp = sample.timestamp;
    if (timestamp == null || timestamp < startUs || timestamp >= endUs) {
      continue;
    }
    capture.add(sample, functions);
    // Find the last UI interval starting at or before this sample.
    var low = 0;
    var high = frames.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (frames[middle].startUs <= timestamp) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0 || timestamp >= frames[low - 1].endUs) continue;
    final frame = frames[low - 1];
    slow.add(sample, functions);
    (byFrame[frame.frameNumber] ??= _CpuSamples()).add(sample, functions);
  }
  return {
    'status': 'available',
    'samplePeriodUs': profile.samplePeriod,
    'capture': capture.summary(),
    'slowTopicFrames': slow.summary(),
    'frames': [
      for (final entry in byFrame.entries)
        {'frameNumber': entry.key, ...entry.value.summary()},
    ],
  };
}

String _functionName(vm.ProfileFunction function) {
  final json = function.toJson()['function'];
  if (json is! Map) return 'Unknown';
  final name = json['name'];
  if (name is! String || name.isEmpty) return 'Unknown';
  final owner = json['owner'];
  final ownerName = owner is Map && owner['type'] == '@Class'
      ? owner['name']
      : null;
  final qualified = ownerName is String && !name.startsWith('$ownerName.')
      ? '$ownerName.$name'
      : name;
  // Function names only: never export resolved URLs, script locations, user
  // tags, service object IDs, or any other fields from the VM response.
  return qualified.length <= 120 ? qualified : qualified.substring(0, 120);
}

final class _CpuSamples {
  int count = 0;
  int truncated = 0;
  final _leafCounts = <String, int>{};
  final _stackCounts = <String, int>{};
  final _tags = <String, int>{};

  void add(vm.CpuSample sample, List<String> functions) {
    count++;
    if (sample.truncated == true) truncated++;
    final tag = sample.vmTag;
    if (tag != null) _increment(_tags, tag);
    final stack = sample.stack ?? const <int>[];
    final names = [
      for (final index in stack.take(6))
        if (index >= 0 && index < functions.length) functions[index],
    ];
    if (names.isEmpty) return;
    _increment(_leafCounts, names.first);
    _increment(_stackCounts, names.join(' ← '));
  }

  Map<String, Object?> summary() => {
    'sampleCount': count,
    'truncatedStackCount': truncated,
    'topFunctions': _rank(_leafCounts, 8),
    'topStacks': _rank(_stackCounts, 5),
    'vmTags': _rank(_tags, 8),
  };

  static void _increment(Map<String, int> counts, String key) =>
      counts.update(key, (value) => value + 1, ifAbsent: () => 1);

  static List<Map<String, Object?>> _rank(Map<String, int> counts, int limit) {
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final order = b.value.compareTo(a.value);
        return order == 0 ? a.key.compareTo(b.key) : order;
      });
    return [
      for (final entry in ranked.take(limit))
        {'name': entry.key, 'samples': entry.value},
    ];
  }
}
