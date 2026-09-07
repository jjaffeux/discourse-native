import 'dart:convert';

import 'package:discourse_native/src/diagnostics/topic_scroll_cpu_profile.dart';
import 'package:discourse_native/src/diagnostics/topic_scroll_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' as vm;

void main() {
  test('matches CPU samples to UI intervals and excludes other work', () {
    final profile = summarizeTopicCpuProfile(
      vm.CpuSamples(
        samplePeriod: 1000,
        functions: [
          _function('parse', owner: 'HtmlParser'),
          _function('build'),
        ],
        samples: [
          for (final timestamp in [
            99,
            100,
            149,
            150,
            199,
            200,
            249,
            250,
            299,
            300,
          ])
            vm.CpuSample(timestamp: timestamp, stack: [0, 1]),
        ],
      ),
      startUs: 100,
      endUs: 300,
      // Deliberately unsorted; the end of an interval belongs to neither it
      // nor its raster work, which must not be attributed to the UI thread.
      slowFrames: [
        (frameNumber: 2, startUs: 200, endUs: 250),
        (frameNumber: 1, startUs: 100, endUs: 150),
      ],
    );

    expect(profile['samplePeriodUs'], 1000);
    expect((profile['capture'] as Map)['sampleCount'], 8);
    expect((profile['slowTopicFrames'] as Map)['sampleCount'], 4);
    final frames = (profile['frames'] as List).cast<Map<String, Object?>>();
    expect(frames.map((frame) => frame['sampleCount']), [2, 2]);
    expect(frames.map((frame) => frame['frameNumber']), [1, 2]);
    expect((profile['slowTopicFrames'] as Map)['topFunctions'], [
      {'name': 'HtmlParser.parse', 'samples': 4},
    ]);
    expect((profile['slowTopicFrames'] as Map)['topStacks'], [
      {'name': 'HtmlParser.parse ← build', 'samples': 4},
    ]);
  });

  test('exports bounded function names without VM URLs or object metadata', () {
    final profile = summarizeTopicCpuProfile(
      vm.CpuSamples(
        pid: 123456,
        functions: [
          for (var index = 0; index < 30; index++)
            _function('method$index', owner: 'PostWidget'),
        ],
        samples: [
          for (var index = 0; index < 30; index++)
            vm.CpuSample(
              timestamp: 100 + index,
              userTag: 'PRIVATE POST TEXT',
              identityHashCode: 654321,
              tid: 777777,
              vmTag: 'Dart',
              truncated: index == 0,
              stack: [
                index,
                for (var caller = 0; caller < 29; caller++) caller,
              ],
            ),
          vm.CpuSample(timestamp: 135, stack: []),
        ],
      ),
      startUs: 100,
      endUs: 200,
      slowFrames: [],
    );
    final capture = profile['capture'] as Map;
    expect(capture['sampleCount'], 31);
    expect(capture['truncatedStackCount'], 1);
    expect(capture['topFunctions'], hasLength(8));
    expect(capture['topStacks'], hasLength(5));
    expect(capture['vmTags'], [
      {'name': 'Dart', 'samples': 30},
    ]);
    final encoded = jsonEncode(profile);
    for (final private in [
      'PRIVATE',
      'example.test',
      '/Users/',
      'secret-id',
      '123456',
      '654321',
      '777777',
    ]) {
      expect(encoded, isNot(contains(private)));
    }
    expect(encoded, contains('PostWidget.method0'));
  });

  test('report shows CPU evidence and row costs for the same slow frame', () {
    final profile = summarizeTopicCpuProfile(
      vm.CpuSamples(
        samplePeriod: 1000,
        functions: [_function('parse', owner: 'HtmlParser')],
        samples: [
          vm.CpuSample(timestamp: 1100, stack: [0]),
          vm.CpuSample(timestamp: 1200, stack: [0]),
          vm.CpuSample(timestamp: 4000, stack: [0]),
        ],
      ),
      startUs: 0,
      endUs: 100000,
      slowFrames: [(frameNumber: 42, startUs: 1000, endUs: 3000)],
    );
    final report = encodeTopicScrollReport({
      'version': 3,
      'summary': {'slowFrameThresholdUs': 8333},
      'cpuProfile': profile,
      'events': [
        {
          'name': 'frame.timing',
          'data': {'frameNumber': 42, 'buildUs': 20000, 'rasterUs': 1000},
        },
        {
          'name': 'post.layout',
          'frameNumber': 42,
          'data': {'postId': 1, 'topicId': 1, 'durationUs': 2500},
        },
      ],
    }, compact: true);
    expect(report, contains('CPU sampling: 3 capture samples | 2 in slow'));
    expect(report, contains('HtmlParser.parse 2/2 (100.0%)'));
    expect(report, contains('Measured row layout 2.50 ms'));
    expect(report, contains('CPU (2 samples): HtmlParser.parse'));
    expect(report, contains('not exact durations'));
  });

  test('empty and unavailable CPU samples leave the report usable', () {
    for (final profile in [
      summarizeTopicCpuProfile(
        vm.CpuSamples(),
        startUs: 0,
        endUs: 1,
        slowFrames: [],
      ),
      {'status': 'unavailable', 'reason': 'profiler-disabled'},
    ]) {
      final report = encodeTopicScrollReport({
        'version': 3,
        'cpuProfile': profile,
      }, compact: true);
      expect(report, isNot(contains('NaN')));
      expect(report, contains('Topic scrolling performance report (v3)'));
      expect(
        report,
        anyOf(
          contains('No CPU samples remain'),
          contains('--enable-dart-profiling'),
        ),
      );
    }
  });
}

vm.ProfileFunction _function(String name, {String? owner}) =>
    vm.ProfileFunction(
      resolvedUrl: 'file:///Users/PRIVATE/source.dart',
      function: vm.FuncRef(
        id: 'secret-id',
        name: name,
        owner: owner == null
            ? vm.LibraryRef(
                id: 'secret-id',
                uri: 'https://example.test/PRIVATE',
              )
            : vm.ClassRef(id: 'secret-id', name: owner),
      ),
    );
