import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:discourse_native/src/data/composer_image_optimizer.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../test/support/event_fixtures.dart';

const _remote = Duration(milliseconds: 30);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await Directory.systemTemp.createTemp('image-operation-');
  try {
    final image = img.Image(width: 1200, height: 800);
    img.fill(image, color: img.ColorRgb8(20, 50, 110));
    final bytes = img.encodePng(image, level: 0);
    stdout.writeln(
      jsonEncode({
        'prepare_cloud_backed_composer_image': await _median(
          () => _image(directory, bytes),
        ),
        'reconcile_rsvp_and_topic': await _median(_event),
      }),
    );
  } finally {
    await directory.delete(recursive: true);
  }
  exit(0);
}

Future<int> _median(Future<int> Function() action) async {
  final times = <int>[];
  for (var i = 0; i < 7; i++) {
    final time = await action();
    if (i >= 2) times.add(time);
  }
  times.sort();
  return times[2];
}

Future<int> _image(Directory directory, Uint8List bytes) async {
  const lookup = Duration(milliseconds: 15);
  final optimizer = ComposerImageOptimizer(
    temporaryDirectory: () async {
      await Future<void>.delayed(lookup);
      return directory;
    },
  );
  final aborted = Completer<void>();
  final watch = Stopwatch()..start();
  final prepared = await optimizer.prepare(
    ComposerUploadFile(
      name: 'photo.png',
      length: () async {
        await Future<void>.delayed(lookup);
        return bytes.length;
      },
      openRead: () => Stream.value(bytes),
    ),
    settings: const ComposerImageOptimization(
      resizeDimensionsThreshold: 1000,
      resizeWidthTarget: 800,
    ),
    canUpload: (_) => true,
    abortTrigger: aborted.future,
  );
  watch.stop();
  try {
    final output = await prepared.file
        .openRead()
        .expand((chunk) => chunk)
        .toList();
    final decoded = img.decodeImage(Uint8List.fromList(output));
    if (!prepared.file.imageOptimizationApplied ||
        output.length >= bytes.length ||
        decoded?.width != 800) {
      throw StateError('The image was not encoded and resized');
    }
    return watch.elapsedMicroseconds;
  } finally {
    await prepared.dispose();
    aborted.complete();
  }
}

Future<int> _event() async {
  final refreshed = Completer<void>();
  final ports = EventTestPorts(
    onTopicReload: (site, id) async {
      if (site != eventSite || id != 700) throw StateError('Unexpected topic');
      await Future<void>.delayed(_remote);
      refreshed.complete();
    },
  );
  var current = eventJson();
  var eventReads = 0;
  ports.transport.responders['GET /discourse-post-event/events/42.json'] =
      (_) async {
        eventReads++;
        await Future<void>.delayed(_remote);
        return {'event': current};
      };
  ports
          .transport
          .responders['POST /discourse-post-event/events/42/invitees.json'] =
      (_) async {
        await Future<void>.delayed(_remote);
        current = eventJson(overrides: {'watching_invitee': watching()});
        return {'invitee': watching()};
      };
  final handle = ports.controller.acquire(
    eventSite,
    PostEvent.decode(current)!,
  );
  try {
    await handle.refresh();
    final watch = Stopwatch()..start();
    await handle.respond('going');
    await refreshed.future.timeout(const Duration(seconds: 2));
    watch.stop();
    if (!handle.authoritative ||
        handle.event?.watching == null ||
        eventReads != 2 ||
        ports.transport.writes.length != 1 ||
        ports.refreshedTopics.length != 1) {
      throw StateError('RSVP and topic did not reconcile');
    }
    return watch.elapsedMicroseconds;
  } finally {
    handle.dispose();
    ports.close();
  }
}
