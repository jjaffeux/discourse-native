import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

/// Opt-in detailed tracing for the isolated chat fixture. These events add
/// substantial overhead; use an ordinary run for before/after frame timings.
class ChatScrollTrace {
  ChatScrollTrace._(this._service, this._previousStreams, this._startUs);

  final vm.VmService _service;
  final List<String> _previousStreams;
  final int _startUs;

  static Future<ChatScrollTrace> start() async {
    final info = await Service.getInfo();
    final service = await vmServiceConnectUri(
      info.serverWebSocketUri!.toString(),
    );
    final streams = (await service.getVMTimelineFlags()).recordedStreams ?? [];
    await service.setVMTimelineFlags(
      {...streams, 'Dart', 'Embedder', 'GC'}.toList(),
    );
    await service.clearVMTimeline();
    debugProfileBuildsEnabled = true;
    debugProfileLayoutsEnabled = true;
    return ChatScrollTrace._(service, streams, Timeline.now);
  }

  Future<void> finish(String label) async {
    final endUs = Timeline.now;
    debugProfileBuildsEnabled = false;
    debugProfileLayoutsEnabled = false;
    try {
      final timeline = await _service.getVMTimeline(
        timeOriginMicros: _startUs,
        timeExtentMicros: endUs - _startUs,
      );
      final file = File('${Directory.systemTemp.path}/chat-trace-$label.json');
      await file.writeAsString(jsonEncode(timeline.toJson()));
      stdout.writeln('CHAT_SCROLL_TRACE ${file.path}');
    } finally {
      await _service.setVMTimelineFlags(_previousStreams);
      await _service.dispose();
    }
  }
}
