import 'dart:convert';
import 'dart:io';

import 'package:discourse_cooking/discourse_cooking.dart';

Future<void> main() async {
  final rssBefore = ProcessInfo.currentRss;
  final service = OfflineCookingService();
  try {
    if (!await service.start()) throw StateError('Cooking runtime unavailable');
    final context = CookingSnapshot(
      siteId: 'benchmark',
      accountId: 'anonymous',
      baseUrl: 'https://forum.example',
    );
    final raw =
        '# Hello\n\n**Markdown** with :smile: and @unknown.\n\n```js\nconst answer = 42;\n```\n\n[spoiler]hidden[/spoiler]\n\nhttps://example.com';
    final request = CookingRequest(raw: raw, snapshot: context);
    final warmUs = <int>[];
    final engineUs = <int>[];
    CookingResult? last;
    for (var i = 0; i < 110; i++) {
      final watch = Stopwatch()..start();
      final result = await service.cook(request);
      if (result.isFallback) {
        throw StateError('Benchmark failed: ${result.failure}');
      }
      if (i >= 10) {
        warmUs.add(watch.elapsedMicroseconds);
        engineUs.add(result.elapsedMicroseconds);
      }
      last = result;
    }
    warmUs.sort();
    engineUs.sort();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'platform':
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'dart': Platform.version,
        'startupMicroseconds': service.startupMicroseconds,
        'warmSamples': warmUs.length,
        'warmRoundTripMedianMicroseconds': warmUs[50],
        'warmRoundTripP95Microseconds': warmUs[94],
        'warmEngineMedianMicroseconds': engineUs[50],
        'outputUtf8Bytes': utf8.encode(last!.html).length,
        'quickJsAllocatedBytes': last.memoryUsageBytes,
        'processRssBeforeBytes': rssBefore,
        'processRssAfterBytes': ProcessInfo.currentRss,
        'memoryNote':
            'RSS includes Dart, allocator and native VM; QuickJS allocation excludes Dart and allocator overhead.',
        'html': last.html,
      }),
    );
  } finally {
    await service.dispose();
  }
}
