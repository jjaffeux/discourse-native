import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/diagnostics/topic_scroll_timeline_recording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'retains streamed engine frames after they leave the VM ring buffer',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final subscribed = Completer<WebSocket>();
      final methods = <String>[];
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((message) {
          final call = jsonDecode(message as String) as Map;
          final method = call['method'] as String;
          methods.add(method);
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': call['id'],
              'result': method == 'getVMTimeline'
                  ? {
                      'type': 'Timeline',
                      'traceEvents': [
                        _event('Rasterizer::DrawToSurfaces', 400, 'B'),
                        _event('Rasterizer::DrawToSurfaces', 450, 'E'),
                      ],
                    }
                  : {'type': 'Success'},
            }),
          );
          if (method == 'streamListen') subscribed.complete(socket);
        });
      });
      final recording = await startTopicRasterRecording(
        startUs: 100,
        serviceUri: Uri.parse('ws://127.0.0.1:${server.port}/ws'),
      );
      final socket = await subscribed.future.timeout(
        const Duration(seconds: 5),
      );
      addTearDown(socket.close);
      void sendEvents(List<Map<String, Object?>> events) => socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'streamNotify',
          'params': {
            'streamId': 'Timeline',
            'event': {
              'type': 'Event',
              'kind': 'TimelineEvents',
              'timestamp': 1,
              'timelineEvents': events,
            },
          },
        }),
      );
      sendEvents([
        _event('Rasterizer::DrawToSurfaces', 100, 'B'),
        _event('SkCanvas::Flush', 110, 'B'),
        _event('PRIVATE POST TEXT', 120, 'B'),
      ]);
      sendEvents([
        _event('SkCanvas::Flush', 190, 'E'),
        _event('Rasterizer::DrawToSurfaces', 200, 'E'),
      ]);
      final result = await recording
          .finish(
            endUs: 500,
            frames: [(frameNumber: 42, startUs: 100, endUs: 200)],
          )
          .timeout(const Duration(seconds: 5));
      expect(result['status'], 'available');
      expect(result['streamedEventCount'], 4);
      expect(result['matchedFrameCount'], 1);
      expect(jsonEncode(result), contains('SkCanvas::Flush'));
      expect(jsonEncode(result), isNot(contains('PRIVATE')));
      expect(methods, isNot(contains('setVMTimelineFlags')));
      expect(methods, isNot(contains('clearVMTimeline')));
    },
  );
}

Map<String, Object?> _event(String name, int timestamp, String phase) => {
  'name': name,
  'ts': timestamp,
  'pid': 1,
  'tid': 2,
  'ph': phase,
  'args': {'text': 'PRIVATE POST TEXT'},
};
