import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/shell/composer/blocks.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/markdown_highlight.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

const _outputPath = String.fromEnvironment('COMPOSER_ANALYSIS_OUTPUT');
const _cpuOnly = bool.fromEnvironment('COMPOSER_ANALYSIS_CPU_ONLY');
const _warmupEdits = 20;
const _frameWarmupEdits = 3;
const _samples = 7;
const _editsPerSample = 5;
const _diagnosticEdits = 20;
const _timeout = Duration(seconds: 10);

Future<void> main() async {
  final report = _Report();
  final total = Stopwatch()..start();
  try {
    final binding = _BenchmarkBinding();
    FlutterError.onError = (details) =>
        report.recordFailure('flutter', details.exception, details.stack);
    PlatformDispatcher.instance.onError = (error, stack) {
      report.recordFailure('platform', error, stack);
      return true;
    };
    _require(kProfileMode, 'Run this benchmark in Flutter profile mode.');
    if (!_cpuOnly) {
      runApp(const _BenchmarkApp());
      await _nextFrame(binding);
    }
    for (final sections in [6, 60, 300]) {
      final source = _draft(sections);
      for (final position in _Position.values) {
        for (final kind in _CpuKind.values) {
          report.stage = '${sections}_${position.name}_${kind.name}';
          report.rows.add(
            _measureCpu(source, sections, position, kind, report),
          );
          report.checkFailures();
        }
        if (!_cpuOnly) {
          report.stage = '${sections}_${position.name}_frame';
          report.rows.add(
            await _measureFrames(source, sections, position, binding, report),
          );
          report.checkFailures();
        }
      }
    }
    report.stage = 'diagnostics';
    report.diagnostics = await _diagnostics(report);
    report.checkFailures();
  } catch (error, stack) {
    if (error is! _RecordedFailure) {
      report.recordFailure('benchmark', error, stack);
    }
  }
  total.stop();
  report.elapsedMicroseconds = total.elapsedMicroseconds;
  await report.write();
  exit(report.failures.isEmpty ? 0 : 1);
}

enum _Position { beginning, middle, end }

enum _CpuKind { blockIndex, markdown, markdownWhitespace, controller }

String _draft(int sections) => List.generate(
  sections,
  (i) =>
      '''## Section $i

A realistic paragraph with **emphasis**, a [link](https://example.test/$i), and enough words to edit in the middle of a structured draft.

- First item
  - Nested child
- Another item

```text
literal [example] and *code* $i
```

> A quoted paragraph for section $i.

''',
).join();

final class _EditStream {
  _EditStream(this.source, int sections, _Position position) {
    final section = switch (position) {
      _Position.beginning => 0,
      _Position.middle => sections ~/ 2,
      _Position.end => sections - 1,
    };
    final heading = source.indexOf('## Section $section\n');
    final word = source.indexOf('enough words', heading);
    _require(heading >= 0 && word >= 0, 'The edit anchor is missing.');
    offset = word + 3;
  }

  String source;
  late int offset;
  int edits = 0;

  TextEditingValue get value => TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: offset),
  );

  TextEditingValue next([String? insertion]) {
    final letter = insertion ?? String.fromCharCode(0x61 + edits % 26);
    source = source.replaceRange(offset, offset, letter);
    offset++;
    edits++;
    return value;
  }
}

ComposerController _composer(TextEditingValue value) => ComposerController(
  const ReplyComposerTarget(
    privateMessageTopic: false,
    siteUrl: 'https://example.test',
    topicId: 1,
    slug: 'topic',
    topicTitle: 'Topic',
  ),
)..text.value = value;

Map<String, Object?> _measureCpu(
  String source,
  int sections,
  _Position position,
  _CpuKind kind,
  _Report report,
) {
  final markdown =
      kind == _CpuKind.markdown || kind == _CpuKind.markdownWhitespace;
  final edits = _EditStream(source, sections, position);
  var index = ComposerBlockIndex.parse(source);
  final composer = kind == _CpuKind.controller ? _composer(edits.value) : null;
  var runs = <MarkdownRun>[];
  final samples = <double>[];
  int run() {
    final value = edits.next(kind == _CpuKind.markdownWhitespace ? ' ' : null);
    final watch = Stopwatch()..start();
    switch (kind) {
      case _CpuKind.blockIndex:
        index = ComposerBlockIndex.parse(value.text, previous: index);
      case _CpuKind.markdown:
      case _CpuKind.markdownWhitespace:
        runs = scanMarkdown(value.text, deferHighlight: (_, _) {});
      case _CpuKind.controller:
        composer!.text.value = value;
    }
    watch.stop();
    if (composer != null) {
      _require(
        composer.text.value == value,
        'The controller changed the edit.',
      );
      index = composer.blocks.index;
    }
    report.consume(markdown ? _runsChecksum(runs) : _indexChecksum(index));
    return watch.elapsedMicroseconds;
  }

  try {
    for (var i = 0; i < _warmupEdits; i++) {
      run();
    }
    for (var sample = 0; sample < _samples; sample++) {
      var elapsed = 0;
      for (var edit = 0; edit < _editsPerSample; edit++) {
        elapsed += run();
      }
      samples.add(elapsed / _editsPerSample);
      report.checkFailures();
    }
    final outputChecksum = markdown
        ? _validateRuns(runs, edits.source.length)
        : _validateIndex(index, edits.source);
    report.consume(outputChecksum);
    return {
      'kind': kind.name,
      'sections': sections,
      'sourceUnits': source.length,
      'position': position.name,
      'warmupEdits': _warmupEdits,
      'editsPerSample': _editsPerSample,
      'microsecondsPerEdit': samples,
      'edits': edits.edits,
      'finalSourceUnits': edits.source.length,
      'sourceChecksum': _sourceChecksum(edits.source),
      'outputChecksum': outputChecksum,
      'outputCount': markdown ? runs.length : index.blocks.length,
    };
  } finally {
    composer?.dispose();
  }
}

Future<Map<String, Object?>> _measureFrames(
  String source,
  int sections,
  _Position position,
  _BenchmarkBinding binding,
  _Report report,
) async {
  final edits = _EditStream(source, sections, position);
  final composer = _composer(edits.value);
  final key = GlobalKey();
  final setterSamples = <int>[];
  final frameSamples = <int>[];
  final framesPerEdit = <int>[];
  try {
    runApp(_BenchmarkApp(composer: composer, editorKey: key));
    await _nextFrame(binding);
    await _nextFrame(binding);
    final editable = _editableFor(key, composer);
    _require(
      editable.renderEditable.hasSize,
      'The actual editor has no layout.',
    );
    for (var edit = 0; edit < _frameWarmupEdits + _samples; edit++) {
      final value = edits.next();
      final beforeFrame = binding.frames;
      final watch = Stopwatch()..start();
      composer.text.value = value;
      final setterMicroseconds = watch.elapsedMicroseconds;
      await _nextFrame(binding);
      watch.stop();
      final frames = binding.frames - beforeFrame;
      _require(frames > 0, 'The edit did not complete a frame.');
      _require(composer.text.value == value, 'The rendered edit changed.');
      final render = _editableFor(key, composer).renderEditable;
      _require(
        render.hasSize && !render.size.isEmpty,
        'The editor is not laid out.',
      );
      _require(
        render.text?.toPlainText().isNotEmpty ?? false,
        'The editor painted no text.',
      );
      report.consume(_indexChecksum(composer.blocks.index));
      report.checkFailures();
      if (edit >= _frameWarmupEdits) {
        setterSamples.add(setterMicroseconds);
        frameSamples.add(watch.elapsedMicroseconds);
        framesPerEdit.add(frames);
      }
    }
    final outputChecksum = _validateIndex(composer.blocks.index, edits.source);
    report.consume(outputChecksum);
    return {
      'kind': 'mountedEditor',
      'sections': sections,
      'sourceUnits': source.length,
      'position': position.name,
      'warmupEdits': _frameWarmupEdits,
      'editsPerSample': 1,
      'setterMicroseconds': setterSamples,
      'updateToEndOfFrameMicroseconds': frameSamples,
      'framesPerEdit': framesPerEdit,
      'edits': edits.edits,
      'finalSourceUnits': edits.source.length,
      'sourceChecksum': _sourceChecksum(edits.source),
      'outputChecksum': outputChecksum,
      'outputCount': composer.blocks.index.blocks.length,
      'renderedTextChecksum': _sourceChecksum(
        editable.renderEditable.text!.toPlainText(),
      ),
      'renderedTextUnits': editable.renderEditable.text!.toPlainText().length,
      'editorSize': {
        'width': editable.renderEditable.size.width,
        'height': editable.renderEditable.size.height,
      },
    };
  } finally {
    runApp(const _BenchmarkApp());
    await _nextFrame(binding);
    composer.dispose();
  }
}

EditableTextState _editableFor(GlobalKey key, ComposerController composer) {
  EditableTextState? found;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is EditableText &&
        identical(widget.controller, composer.text) &&
        element is StatefulElement &&
        element.state is EditableTextState) {
      found = element.state as EditableTextState;
    }
    element.visitChildren(visit);
  }

  final context = key.currentContext;
  _require(context is Element, 'The actual ComposerEditor is not mounted.');
  visit(context as Element);
  _require(found != null, 'The actual composer EditableText is not mounted.');
  return found!;
}

Future<void> _nextFrame(_BenchmarkBinding binding) =>
    binding.endOfFrame.timeout(_timeout);

final class _BenchmarkBinding extends WidgetsFlutterBinding {
  int frames = 0;

  @override
  void drawFrame() {
    super.drawFrame();
    frames++;
  }
}

final class _BenchmarkApp extends StatelessWidget {
  const _BenchmarkApp({this.composer, this.editorKey});

  final ComposerController? composer;
  final GlobalKey? editorKey;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DPageSurface(
      child: composer == null
          ? const SizedBox.expand()
          : ComposerEditor(
              key: editorKey,
              composer: composer!,
              hintText: '',
              textStyle: AppTheme.light.textTheme.bodyLarge,
              hintStyle: AppTheme.light.textTheme.bodyLarge,
            ),
    ),
  );
}

int _indexChecksum(ComposerBlockIndex index) => index.blocks.fold(
  0,
  (sum, block) =>
      (sum + block.id + block.start + block.end + block.kind.index) &
      0x3fffffff,
);

int _runsChecksum(List<MarkdownRun> runs) => runs.fold(
  0,
  (sum, run) => (sum + run.start + run.end + run.mask) & 0x3fffffff,
);

int _sourceChecksum(String source) {
  var checksum = 0;
  for (final unit in source.codeUnits) {
    checksum = (checksum * 31 + unit) & 0x3fffffff;
  }
  return checksum;
}

int _validateIndex(ComposerBlockIndex index, String source) {
  _require(index.source == source, 'The block index contains a stale source.');
  _require(index.blocks.isNotEmpty, 'The block index is empty.');
  final ids = <int>{};
  var end = 0;
  for (final block in index.blocks) {
    _require(
      block.start >= end &&
          block.end > block.start &&
          block.end <= source.length,
      'The block index has invalid extents.',
    );
    _require(
      source.substring(block.start, block.end) == block.source,
      'A block does not match its source.',
    );
    _require(
      source.substring(end, block.start).trim().isEmpty,
      'The block index omitted source.',
    );
    _require(ids.add(block.id), 'The block index duplicated an identity.');
    end = block.end;
  }
  _require(
    source.substring(end).trim().isEmpty,
    'The block index omitted its tail.',
  );
  final reference = ComposerBlockIndex.parse(source, atoms: index.atoms);
  _require(
    reference.blocks.length == index.blocks.length,
    'The block count differs from a fresh parse.',
  );
  for (var i = 0; i < index.blocks.length; i++) {
    final actual = index.blocks[i];
    final expected = reference.blocks[i];
    _require(
      actual.start == expected.start &&
          actual.end == expected.end &&
          actual.kind == expected.kind &&
          actual.movable == expected.movable,
      'The block output differs from a fresh parse.',
    );
  }
  return _indexChecksum(index);
}

int _validateRuns(List<MarkdownRun> runs, int sourceLength) {
  var end = 0;
  for (final run in runs) {
    _require(
      run.start == end && run.end > run.start && run.end <= sourceLength,
      'The Markdown scan has invalid extents.',
    );
    end = run.end;
  }
  _require(end == sourceLength, 'The Markdown scan did not cover the source.');
  return _runsChecksum(runs);
}

Future<Map<String, Object?>> _diagnostics(_Report report) async {
  vm.VmService? service;
  try {
    final info = await developer.Service.getInfo().timeout(_timeout);
    final uri = info.serverWebSocketUri;
    final isolateId = developer.Service.getIsolateId(Isolate.current);
    if (uri == null || isolateId == null) {
      return {'status': 'unavailable', 'reason': 'VM Service is not enabled.'};
    }
    service = await vmServiceConnectUri(uri.toString()).timeout(_timeout);
    final rows = <Map<String, Object?>>[];
    for (final sections in [6, 60, 300]) {
      final edits = _EditStream(_draft(sections), sections, _Position.middle);
      final composer = _composer(edits.value);
      try {
        for (var i = 0; i < _warmupEdits; i++) {
          composer.text.value = edits.next();
        }
        final before = await service
            .getAllocationProfile(isolateId, reset: true, gc: true)
            .timeout(_timeout);
        final origin = developer.Timeline.now;
        for (var i = 0; i < _diagnosticEdits; i++) {
          composer.text.value = edits.next();
        }
        final extent = developer.Timeline.now - origin;
        final after = await service
            .getAllocationProfile(isolateId)
            .timeout(_timeout);
        final allocations = _allocationDelta(before, after);
        Map<String, Object?> cpu;
        try {
          final profile = await service
              .getCpuSamples(isolateId, origin, extent)
              .timeout(_timeout);
          final functions = [...?profile.functions]
            ..sort(
              (a, b) =>
                  (b.exclusiveTicks ?? 0).compareTo(a.exclusiveTicks ?? 0),
            );
          cpu = {
            'status': 'available',
            'sampleCount': profile.sampleCount,
            'samplePeriodMicroseconds': profile.samplePeriod,
            'intervalMicroseconds': extent,
            'topFunctions': [
              for (final entry in functions.take(12))
                {
                  'name': _profileFunctionName(entry),
                  'script': entry.resolvedUrl,
                  'inclusiveTicks': entry.inclusiveTicks,
                  'exclusiveTicks': entry.exclusiveTicks,
                },
            ],
          };
        } catch (error) {
          cpu = {
            'status': 'unavailable',
            'errorType': error.runtimeType.toString(),
          };
        }
        report.consume(_validateIndex(composer.blocks.index, edits.source));
        rows.add({
          'sections': sections,
          'sourceUnits': edits.source.length,
          'edits': _diagnosticEdits,
          'kind': 'unmountedController',
          'position': 'middle',
          'allocations': allocations,
          'cpu': cpu,
        });
      } finally {
        composer.dispose();
      }
    }
    return {
      'status': 'available',
      'timed': false,
      'allocationScope':
          'Whole isolate, including edit generation and VM Service messages.',
      'allocationCounters':
          'accumulatedSize and bytesCurrent deltas are reported separately.',
      'rows': rows,
    };
  } catch (error, stack) {
    report.recordFailure('diagnostics', error, stack);
    return {
      'status': 'failed',
      'errorType': error.runtimeType.toString(),
      'stack': stack.toString(),
    };
  } finally {
    await service?.dispose().timeout(_timeout);
  }
}

String? _profileFunctionName(vm.ProfileFunction entry) =>
    switch (entry.function) {
      vm.FuncRef(:final name) => name,
      vm.NativeFunction(:final name) => name,
      _ => null,
    };

Map<String, Object?> _allocationDelta(
  vm.AllocationProfile before,
  vm.AllocationProfile after,
) {
  _require(
    before.members?.isNotEmpty ?? false,
    'The initial allocation profile is empty.',
  );
  _require(
    after.members?.isNotEmpty ?? false,
    'The final allocation profile is empty.',
  );
  final previous = {
    for (final row in before.members ?? <vm.ClassHeapStats>[])
      row.classRef?.id: row,
  };
  final totals = <String, List<int>>{
    for (final group in ['overall', 'parser', 'lists', 'strings'])
      group: [0, 0, 0, 0],
  };
  final parserClasses = <Map<String, Object?>>[];
  const parserNames = {
    'ComposerBlockIndex',
    'ComposerBodyBlock',
    'ComposerBlockAtom',
    '_BlockScanner',
    '_Line',
    '_Span',
    '_Scan',
    '_Fence',
    '_RecentScan',
    'MarkdownRun',
    'CodeRanges',
  };
  for (final row in after.members ?? <vm.ClassHeapStats>[]) {
    _require(
      row.classRef?.id != null &&
          (row.accumulatedSize ?? -1) >= 0 &&
          (row.instancesAccumulated ?? -1) >= 0 &&
          (row.bytesCurrent ?? -1) >= 0 &&
          (row.instancesCurrent ?? -1) >= 0,
      'The VM did not expose complete class allocation counters.',
    );
    final old = previous[row.classRef?.id];
    final name = row.classRef?.name ?? '';
    final values = [
      (row.accumulatedSize ?? 0) - (old?.accumulatedSize ?? 0),
      (row.instancesAccumulated ?? 0) - (old?.instancesAccumulated ?? 0),
      (row.bytesCurrent ?? 0) - (old?.bytesCurrent ?? 0),
      (row.instancesCurrent ?? 0) - (old?.instancesCurrent ?? 0),
    ];
    final parser = parserNames.contains(name);
    for (final group in [
      'overall',
      if (parser) 'parser',
      if (name == '_List' ||
          name == '_GrowableList' ||
          name == '_ImmutableList')
        'lists',
      if (name == '_OneByteString' || name == '_TwoByteString') 'strings',
    ]) {
      for (var i = 0; i < values.length; i++) {
        totals[group]![i] += values[i];
      }
    }
    if (parser && values.any((value) => value != 0)) {
      parserClasses.add({'class': name, ..._allocationFields(values)});
    }
  }
  return {
    for (final entry in totals.entries)
      entry.key: _allocationFields(entry.value),
    'parserClasses': parserClasses,
  };
}

Map<String, int> _allocationFields(List<int> values) => {
  'accumulatedBytesDelta': values[0],
  'accumulatedInstancesDelta': values[1],
  'currentBytesDelta': values[2],
  'currentInstancesDelta': values[3],
};

final class _Report {
  String stage = 'initialization';
  int elapsedMicroseconds = 0;
  int checksum = 0;
  final rows = <Map<String, Object?>>[];
  final failures = <Map<String, Object?>>[];
  Map<String, Object?> diagnostics = {'status': 'not-run'};

  void consume(int value) => checksum = (checksum + value) & 0x3fffffff;

  void recordFailure(String kind, Object error, StackTrace? stack) {
    failures.add({
      'kind': kind,
      'stage': stage,
      'errorType': error.runtimeType.toString(),
      if (error is _BenchmarkFailure) 'message': error.message,
      if (stack != null) 'stack': stack.toString(),
    });
  }

  void checkFailures() {
    if (failures.isNotEmpty) throw const _RecordedFailure();
  }

  Map<String, Object?> toJson() => {
    'schema': 1,
    'status': failures.isEmpty ? 'passed' : 'failed',
    'mode': kProfileMode
        ? 'profile'
        : kReleaseMode
        ? 'release'
        : 'debug',
    'platform': Platform.operatingSystem,
    'dartVersion': Platform.version,
    'processors': Platform.numberOfProcessors,
    'surface': _cpuOnly ? 'synchronousController' : 'mountedEditor',
    'fixture': 'composer_analysis_benchmark_test structured draft',
    'edit':
        'Cumulative single-letter insertion inside a prose word; markdownWhitespace inserts spaces for contextual fallback.',
    'cpuTiming':
        'Analysis or synchronous setter only. Excludes edit generation and verification.',
    'frameTiming': _cpuOnly
        ? 'Not measured in CPU-only mode.'
        : 'Controller update through UI-thread endOfFrame, including vsync wait, build, layout and paint.',
    'frameLimitations':
        'Excludes keyboard/IME delivery, engine raster completion and physical display presentation.',
    'elapsedMicroseconds': elapsedMicroseconds,
    'peakRssBytes': ProcessInfo.maxRss,
    'rows': rows,
    'diagnostics': diagnostics,
    'checksum': checksum,
    'failureCount': failures.length,
    'failures': failures,
  };

  Future<void> write() async {
    if (_outputPath.isNotEmpty) {
      try {
        _require(
          File(_outputPath).isAbsolute,
          'The output path must be absolute.',
        );
        final output = File(_outputPath);
        await output.parent.create(recursive: true);
        await output.writeAsString(jsonEncode(toJson()), flush: true);
      } catch (error, stack) {
        recordFailure('output', error, stack);
      }
    }
    stdout.writeln(jsonEncode(toJson()));
    await stdout.flush();
  }
}

void _require(bool condition, String message) {
  if (!condition) throw _BenchmarkFailure(message);
}

final class _BenchmarkFailure implements Exception {
  const _BenchmarkFailure(this.message);
  final String message;
}

final class _RecordedFailure implements Exception {
  const _RecordedFailure();
}
