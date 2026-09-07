import 'package:discourse_native/src/diagnostics/topic_scroll_capture.dart';
import 'package:discourse_native/src/diagnostics/topic_scroll_timeline_recording.dart';

TopicScrollCaptureController topicScrollCaptureWithoutVm({
  int maximumEvents = TopicScrollCaptureController.defaultMaximumEvents,
}) => TopicScrollCaptureController(
  maximumEvents: maximumEvents,
  rasterRecordingStarter: ({required startUs}) async =>
      const TopicRasterRecording.unavailable('test'),
  cpuProfileCollector:
      ({
        required startUs,
        required endUs,
        required slowFrames,
        required slowRasterFrames,
      }) async => {'status': 'unavailable', 'reason': 'vm-service-unavailable'},
);
