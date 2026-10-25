import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/shell/composer/blocks.dart';
import 'package:discourse_native/src/shell/composer/components/list_source.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/markdown_highlight.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

const _outputPath = String.fromEnvironment('COMPOSER_ANALYSIS_OUTPUT');
const _cpuOnly = bool.fromEnvironment('COMPOSER_ANALYSIS_CPU_ONLY');
const _structure = bool.fromEnvironment('COMPOSER_ANALYSIS_STRUCTURE');
const _caret = bool.fromEnvironment('COMPOSER_ANALYSIS_CARET');
const _structureSections = 160;
const _structureWarmup = 12;
const _structureSamples = 100;
const _warmupEdits = 20;
const _frameWarmupEdits = 3;
const _samples = 7;
const _editsPerSample = 5;
const _diagnosticEdits = 20;
const _timeout = Duration(seconds: 10);

final _benchmarkTheme = AppTheme.light;

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
    if (_caret) {
      runApp(const _BenchmarkApp());
      await _nextFrame(binding);
      BuildContext? context;
      void findContext(Element element) {
        if (element.widget is DPageSurface) context = element;
        element.visitChildren(findContext);
      }

      findContext(binding.rootElement!);
      final spanContext = context;
      if (spanContext == null || !spanContext.mounted) {
        throw const _BenchmarkFailure('The benchmark theme is not mounted.');
      }
      for (final sections in [6, 60, 300]) {
        report.stage = 'caret_$sections';
        report.rows.add(_measureCaret(_draft(sections), spanContext, report));
        report.rows.add(
          _measureCaret(_draft(sections), spanContext, report, editing: true),
        );
      }
      final inlineDraft = _draft(60).replaceAll(
        'and enough words',
        'with @sam #general :smile: <kbd>**Ctrl** + K</kbd> and enough words',
      );
      report.rows.add(_measureCaret(inlineDraft, spanContext, report));
      report.rows.add(
        _measureCaret(inlineDraft, spanContext, report, editing: true),
      );
      if (Platform.environment['COMPOSER_CARET_DIAGNOSTICS'] == '1') {
        report.diagnostics = await _caretDiagnostics(spanContext, report);
      }
      for (final sections in [6, 60, 300]) {
        report.stage = 'caret_frame_$sections';
        report.rows.add(
          await _measureFrames(
            _draft(sections),
            sections,
            _Position.middle,
            binding,
            report,
            caret: true,
          ),
        );
      }
    } else if (_structure) {
      for (final draft in _StructureDraft.values) {
        for (final edit in _StructureEdit.values) {
          report.stage = 'structure_${draft.name}_${edit.name}';
          report.rows.add(_measureStructure(draft, edit, report));
          report.checkFailures();
        }
      }
      report.stage = 'structure_diagnostics';
      report.diagnostics = await _structureDiagnostics(report);
      report.checkFailures();
    } else {
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
    }
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

Map<String, Object?> _measureCaret(
  String source,
  BuildContext context,
  _Report report, {
  bool editing = false,
}) {
  final composer = _composer(
    TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(
        offset: source.indexOf('enough words'),
      ),
    ),
  );
  final controller = composer.text;
  final style = Theme.of(context).textTheme.bodyLarge;
  final initialSourceUnits = source.length;
  final offset = controller.selection.start;
  final buildSamples = <int>[];
  final totalSamples = <int>[];
  final checksums = <int>[];
  var reused = 0;
  TextSpan? previous;
  try {
    for (var sample = 0; sample < 120; sample++) {
      if (editing) source = source.replaceRange(offset, offset, 'x');
      final next = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(
          offset: offset + (editing ? 0 : sample % 6),
        ),
      );
      final total = Stopwatch()..start();
      controller.value = next;
      final build = Stopwatch()..start();
      final span = controller.buildTextSpan(
        context: context,
        style: style,
        withComposing: true,
      );
      build.stop();
      total.stop();
      final painted = span.toPlainText(includeSemanticsLabels: false);
      _require(
        painted.length == source.length,
        'The caret projection lost offsets.',
      );
      _require(controller.text == source, 'Caret movement changed the source.');
      final checksum = _sourceChecksum(painted);
      report.consume(checksum);
      if (sample >= 20) {
        buildSamples.add(build.elapsedMicroseconds);
        totalSamples.add(total.elapsedMicroseconds);
        checksums.add(checksum);
        if (identical(previous, span)) reused++;
      }
      previous = span;
    }
    return {
      'kind': editing ? 'editBuild' : 'caretBuild',
      'initialSourceUnits': initialSourceUnits,
      'sourceUnits': source.length,
      'warmupOperations': 20,
      'buildMicroseconds': buildSamples,
      'setterAndBuildMicroseconds': totalSamples,
      'sourceChecksum': _sourceChecksum(source),
      'paintedChecksums': checksums,
      'reusedSpans': reused,
    };
  } finally {
    composer.dispose();
  }
}

Future<Map<String, Object?>> _caretDiagnostics(
  BuildContext context,
  _Report report,
) async {
  final info = await developer.Service.getInfo().timeout(_timeout);
  final uri = info.serverWebSocketUri;
  final isolateId = developer.Service.getIsolateId(Isolate.current);
  _require(
    uri != null && isolateId != null,
    'The profiling service is unavailable.',
  );
  final service = await vmServiceConnectUri(uri.toString()).timeout(_timeout);
  final source = _draft(300);
  final composer = _composer(TextEditingValue(text: source));
  final offset = source.indexOf('enough words');
  try {
    if (!context.mounted) {
      throw const _BenchmarkFailure('The profiling context was unmounted.');
    }
    final origin = developer.Timeline.now;
    for (var i = 0; i < 10000; i++) {
      composer.text.selection = TextSelection.collapsed(offset: offset + i % 6);
      final span = composer.text.buildTextSpan(
        context: context,
        withComposing: true,
      );
      report.consume(span.children!.length);
    }
    final extent = developer.Timeline.now - origin;
    final profile = await service
        .getCpuSamples(isolateId!, origin, extent)
        .timeout(_timeout);
    final functions = [
      ...?profile.functions,
    ]..sort((a, b) => (b.exclusiveTicks ?? 0).compareTo(a.exclusiveTicks ?? 0));
    return {
      'status': 'available',
      'timed': false,
      'operations': 10000,
      'sampleCount': profile.sampleCount,
      'topFunctions': [
        for (final entry in functions.take(30))
          {
            'name': _profileFunctionName(entry),
            'script': entry.resolvedUrl,
            'inclusiveTicks': entry.inclusiveTicks,
            'exclusiveTicks': entry.exclusiveTicks,
          },
      ],
    };
  } finally {
    composer.dispose();
    await service.dispose();
  }
}

enum _StructureDraft { plain, rich }

enum _StructureEdit { middleInsertion, topInsertion, delimiter, undo }

String _structureDraft(_StructureDraft kind) => List.generate(
  _structureSections,
  (i) => kind == _StructureDraft.plain
      ? '''Section $i

An ordinary editing anchor has enough words to represent a long plain draft. This paragraph contains prose about writing a clear message and reviewing the next sentence before sharing it.

Another paragraph adds enough ordinary prose to retain realistic paragraph boundaries in this draft section.

'''
      : '''## Section $i

An ordinary editing anchor has **emphasis**, _italics_, a [link](https://example.test/$i), and a Unicode sailor ⛵ who checks the next sentence.

- First item $i
  - Nested child with [another link](https://example.test/nested/$i)
- Another item
- [ ] Open task $i
- [x] Completed task $i

```text
literal [grid] and ![not an image](upload://code$i)
```

[quote="sam, post:1, topic:1"]
Quoted paragraph for section $i.
[/quote]

[grid]
![First|100x100](upload://first$i)
![Second|200x100](upload://second$i)
[/grid]

![Standalone|100x100](upload://standalone$i)

[details="More $i"]
A detailed paragraph.
[/details]

| First | Second |
| --- | --- |
| $i | Value |

''',
).join();

final class _StructureRun {
  _StructureRun(this.draft, this.edit)
    : source = _structureDraft(draft),
      composer = _composer(TextEditingValue(text: _structureDraft(draft))) {
    final section = edit == _StructureEdit.topInsertion
        ? 0
        : _structureSections ~/ 2;
    final heading = source.indexOf('Section $section\n');
    offset = source.indexOf('ordinary editing anchor', heading) + 8;
    _require(
      heading >= 0 && offset >= 8,
      'The structure edit anchor is missing.',
    );
    composer.text.selection = TextSelection.collapsed(offset: offset);
    composer.history.startSession();
    composer.blocks.index;
    composer.text.blockGaps;
    if (draft == _StructureDraft.rich) {
      final kinds = composer.text.syntaxBlocks
          .map((block) => block.kind.id)
          .toSet();
      _require(
        kinds.containsAll({
              'core/list-item',
              'core/code-block',
              'core/details',
              'core/table',
            }) &&
            composer.text.imageBlocks.length == _structureSections * 3 &&
            composer.text.galleryBlocks.length == _structureSections &&
            composer.text.quoteBlocks.length == _structureSections,
        'The rich fixture did not exercise its expected components.',
      );
    }
  }

  final _StructureDraft draft;
  final _StructureEdit edit;
  final ComposerController composer;
  String source;
  late int offset;
  int sequence = 0;
  List<int>? undoIds;

  TextEditingValue _insert() {
    source = source.replaceRange(
      offset,
      offset,
      String.fromCharCode(0x61 + sequence % 26),
    );
    offset++;
    return TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  TextEditingValue prepare() {
    sequence++;
    switch (edit) {
      case _StructureEdit.middleInsertion:
      case _StructureEdit.topInsertion:
        return _insert();
      case _StructureEdit.delimiter:
        final section = 20 + (sequence - 1) % 120;
        final anchor = source.indexOf(
          draft == _StructureDraft.rich
              ? '## Section $section\n'
              : 'Section $section\n',
        );
        _require(anchor >= 0, 'The delimiter edit anchor is missing.');
        source = source.replaceRange(
          anchor,
          anchor + (draft == _StructureDraft.rich ? 3 : 0),
          draft == _StructureDraft.rich ? '' : '# ',
        );
        return TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: anchor),
        );
      case _StructureEdit.undo:
        final before = _insert();
        composer.text.value = before;
        composer.history.flush();
        undoIds = composer.blocks.index.blocks
            .map((block) => block.id)
            .toList();
        composer.text.blockGaps;
        composer.text.value = _insert();
        composer.history.flush();
        composer.blocks.index;
        composer.text.blockGaps;
        _require(composer.history.canUndo, 'The history has no edit to undo.');
        source = before.text;
        offset = before.selection.extentOffset;
        return before;
    }
  }

  ({int elapsed, ComposerBlockIndex index, List<TextRange> gaps}) run(
    _Report report,
  ) {
    final expected = prepare();
    final watch = Stopwatch()..start();
    final restored = edit == _StructureEdit.undo
        ? composer.history.undo()
        : false;
    if (edit != _StructureEdit.undo) composer.text.value = expected;
    final index = composer.blocks.index;
    final gaps = composer.text.blockGaps;
    composer.text.todos;
    watch.stop();
    _require(composer.text.value == expected, 'The structure edit changed.');
    if (edit == _StructureEdit.undo) {
      _require(restored, 'History rejected undo.');
      _require(
        listEquals(undoIds, index.blocks.map((block) => block.id).toList()),
        'Undo did not restore block identities.',
      );
    }
    report.consume(_indexChecksum(index));
    report.consume(_gapsChecksum(gaps));
    return (elapsed: watch.elapsedMicroseconds, index: index, gaps: gaps);
  }
}

Map<String, Object?> _measureStructure(
  _StructureDraft draft,
  _StructureEdit edit,
  _Report report,
) {
  final run = _StructureRun(draft, edit);
  final initialUnits = run.source.length;
  final samples = <int>[];
  var validated = 0;
  final outputDigests = <String>[];
  try {
    for (var i = 0; i < _structureWarmup + _structureSamples; i++) {
      final result = run.run(report);
      if (i >= _structureWarmup) samples.add(result.elapsed);
      final normalized = jsonEncode(_structureOutput(run.composer));
      outputDigests.add(
        SHA256Digest()
            .process(utf8.encode(normalized))
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
      );
      if (i % 10 == 0 || i + 1 == _structureWarmup + _structureSamples) {
        _validateStructure(run.composer, result.index, result.gaps);
        validated++;
      }
      report.checkFailures();
    }
    return {
      'kind': 'controllerAndStructuralConsumers',
      'draft': draft.name,
      'edit': edit.name,
      'sections': _structureSections,
      'sourceUnits': initialUnits,
      'warmupEdits': _structureWarmup,
      'editsPerSample': 1,
      'microsecondsPerEdit': samples,
      'edits': run.sequence,
      'freshValidatedEdits': validated,
      'outputDigests': outputDigests,
      'finalOutput': _structureOutput(run.composer),
      'finalSourceUnits': run.source.length,
      'sourceChecksum': _sourceChecksum(run.source),
      'outputChecksum': _indexChecksum(run.composer.blocks.index),
      'gapChecksum': _gapsChecksum(run.composer.text.blockGaps),
      'outputCount': run.composer.blocks.index.blocks.length,
      'gapCount': run.composer.text.blockGaps.length,
      'syntaxCount': run.composer.text.syntaxBlocks.length,
      'imageCount': run.composer.text.imageBlocks.length,
      'galleryCount': run.composer.text.galleryBlocks.length,
      'quoteCount': run.composer.text.quoteBlocks.length,
      'todoCount': run.composer.text.todos.length,
    };
  } finally {
    run.composer.dispose();
  }
}

Map<String, Object?> _structureOutput(ComposerController composer) {
  final text = composer.text;
  return {
    'source': text.text,
    'blocks': [
      for (final b in composer.blocks.index.blocks)
        [
          b.id,
          b.start,
          b.end,
          b.kind.name,
          b.source,
          b.movable,
          b.componentLabel,
        ],
    ],
    'atoms': [
      for (final a in composer.blocks.index.atoms) [a.start, a.end, a.label],
    ],
    'gaps': [
      for (final gap in text.blockGaps) [gap.start, gap.end],
    ],
    'separators': [
      for (final gap in text.blockSeparators) [gap.start, gap.end],
    ],
    'syntax': [
      for (final b in text.syntaxBlocks)
        [
          b.start,
          b.end,
          b.kind.id,
          b.source,
          b.projection.runtimeType.toString(),
        ],
    ],
    'listProjections': [
      for (final block in text.syntaxBlocks)
        if (block.kind.id == 'core/list-item')
          _listPayload(
            (block.projection as dynamic).item as ComposerListItem,
            text.text,
          ),
    ],
    'images': [
      for (final b in text.imageBlocks)
        [b.start, b.end, b.source, b.alt, b.url, b.width, b.height, b.scale],
    ],
    'galleries': [
      for (final b in text.galleryBlocks)
        [
          b.start,
          b.end,
          b.contentStart,
          b.contentEnd,
          b.source,
          b.mode.name,
          [
            for (final image in b.images) [image.start, image.end],
          ],
        ],
    ],
    'quotes': [
      for (final b in text.quoteBlocks) [b.start, b.end, b.source],
    ],
    'todos': [
      for (final b in text.todos)
        [
          b.start,
          b.markerStart,
          b.contentStart,
          b.end,
          b.checked,
          b.itemEnd,
          b.continuationIndent,
          b.parentStart,
        ],
    ],
  };
}

List<Object?> _listPayload(ComposerListItem item, String document) => [
  item.document == document,
  item.start,
  item.end,
  item.marker,
  item.indent,
  item.contentIndent,
  item.contentStart,
  item.firstLineEnd,
  item.taskMarker,
  item.taskMarkerStart,
  item.closed,
  item.number,
  item.referenceMarkers.toList()..sort(),
  item.source,
  item.body.text,
  [for (final child in item.children) _listPayload(child, item.body.text)],
];

int _gapsChecksum(List<TextRange> gaps) =>
    gaps.fold(0, (sum, gap) => (sum + gap.start * 31 + gap.end) & 0x3fffffff);

void _validateStructure(
  ComposerController composer,
  ComposerBlockIndex index,
  List<TextRange> gaps,
) {
  _validateIndex(index, composer.text.text);
  final reference = _composer(composer.text.value);
  try {
    final expected = reference.blocks.index;
    _require(
      listEquals(
        [
          for (final b in index.blocks)
            (b.start, b.end, b.kind, b.source, b.movable, b.componentLabel),
        ],
        [
          for (final b in expected.blocks)
            (b.start, b.end, b.kind, b.source, b.movable, b.componentLabel),
        ],
      ),
      'The structural index differs from a fresh controller.',
    );
    _require(
      listEquals(gaps, reference.text.blockGaps),
      'The structural gaps differ from a fresh controller.',
    );
    _require(
      listEquals(
        [
          for (final b in composer.text.syntaxBlocks)
            (b.start, b.end, b.source, b.kind),
        ],
        [
          for (final b in reference.text.syntaxBlocks)
            (b.start, b.end, b.source, b.kind),
        ],
      ),
      'The syntax occurrences differ from a fresh controller.',
    );
    _require(
      listEquals(
            [
              for (final b in composer.text.imageBlocks)
                (b.start, b.end, b.source),
            ],
            [
              for (final b in reference.text.imageBlocks)
                (b.start, b.end, b.source),
            ],
          ) &&
          listEquals(
            [
              for (final b in composer.text.galleryBlocks)
                (b.start, b.end, b.source, b.images.length),
            ],
            [
              for (final b in reference.text.galleryBlocks)
                (b.start, b.end, b.source, b.images.length),
            ],
          ) &&
          listEquals(
            [
              for (final b in composer.text.quoteBlocks)
                (b.start, b.end, b.source),
            ],
            [
              for (final b in reference.text.quoteBlocks)
                (b.start, b.end, b.source),
            ],
          ),
      'The media or quote analysis differs from a fresh controller.',
    );
  } finally {
    reference.dispose();
  }
}

Future<Map<String, Object?>> _measureFrames(
  String source,
  int sections,
  _Position position,
  _BenchmarkBinding binding,
  _Report report, {
  bool caret = false,
}) async {
  final edits = _EditStream(source, sections, position);
  final composer = _composer(edits.value);
  final key = GlobalKey();
  final setterSamples = <int>[];
  final frameSamples = <int>[];
  final framesPerEdit = <int>[];
  try {
    runApp(
      _BenchmarkApp(composer: composer, editorKey: key, autofocus: !caret),
    );
    await _nextFrame(binding);
    await _nextFrame(binding);
    final editable = _editableFor(key, composer);
    _require(
      editable.renderEditable.hasSize,
      'The actual editor has no layout.',
    );
    for (var edit = 0; edit < _frameWarmupEdits + _samples; edit++) {
      final value = caret
          ? edits.value.copyWith(
              selection: TextSelection.collapsed(
                offset: edits.offset + edit % 6,
              ),
            )
          : edits.next();
      final beforeFrame = binding.frames;
      final watch = Stopwatch()..start();
      composer.text.value = value;
      final setterMicroseconds = watch.elapsedMicroseconds;
      await _nextFrame(binding);
      watch.stop();
      final frames = binding.frames - beforeFrame;
      _require(frames > 0, 'The edit did not complete a frame.');
      _require(
        composer.text.value == value,
        'The rendered edit changed. Expected selection ${value.selection} and composing ${value.composing}; got ${composer.text.selection} and ${composer.text.value.composing}.',
      );
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
      'kind': caret ? 'mountedCaret' : 'mountedEditor',
      'autofocus': !caret,
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
  const _BenchmarkApp({this.composer, this.editorKey, this.autofocus = true});

  final ComposerController? composer;
  final GlobalKey? editorKey;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _benchmarkTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DPageSurface(
      child: composer == null
          ? const SizedBox.expand()
          : ComposerEditor(
              key: editorKey,
              composer: composer!,
              autofocus: autofocus,
              hintText: '',
              textStyle: _benchmarkTheme.textTheme.bodyLarge,
              hintStyle: _benchmarkTheme.textTheme.bodyLarge,
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

Future<Map<String, Object?>> _structureDiagnostics(_Report report) async {
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
    for (final draft in _StructureDraft.values) {
      for (final edit in _StructureEdit.values) {
        final run = _StructureRun(draft, edit);
        try {
          for (var i = 0; i < _structureWarmup; i++) {
            run.run(report);
          }
          final before = await service
              .getAllocationProfile(isolateId, reset: true, gc: true)
              .timeout(_timeout);
          final origin = developer.Timeline.now;
          for (var i = 0; i < _diagnosticEdits; i++) {
            run.run(report);
          }
          final extent = developer.Timeline.now - origin;
          final after = await service
              .getAllocationProfile(isolateId)
              .timeout(_timeout);
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
                for (final entry in functions.take(20))
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
          _validateStructure(
            run.composer,
            run.composer.blocks.index,
            run.composer.text.blockGaps,
          );
          rows.add({
            'draft': draft.name,
            'edit': edit.name,
            'sections': _structureSections,
            'sourceUnits': run.source.length,
            'edits': _diagnosticEdits,
            'allocations': _allocationDelta(before, after),
            'cpu': cpu,
          });
        } finally {
          run.composer.dispose();
        }
      }
    }
    return {
      'status': 'available',
      'timed': false,
      'allocationScope':
          'Whole isolate, including edit generation, result consumption and VM Service messages. Undo includes two setup insertions per restored edit.',
      'allocationCounters':
          'accumulatedSize and bytesCurrent deltas are reported separately.',
      'rows': rows,
    };
  } catch (error, stack) {
    report.recordFailure('structure_diagnostics', error, stack);
    return {
      'status': 'failed',
      'errorType': error.runtimeType.toString(),
      'stack': stack.toString(),
    };
  } finally {
    await service?.dispose().timeout(_timeout);
  }
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
    'ComposerSourceAnalysis',
    '_ListAnalysis',
    'ComposerListItem',
    'ComposerListBody',
    'ComposerTodo',
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
    'ComposerImageBlock',
    'ComposerImageGalleryBlock',
    'ComposerQuoteBlock',
    'ComposerSyntaxOccurrence',
    '_ListProjection',
    '_CodeProjection',
    '_TableProjection',
    '_DetailsProjection',
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
    'surface': _caret
        ? 'caretBuildAndMountedEditor'
        : _structure
        ? 'controllerAndStructuralConsumers'
        : _cpuOnly
        ? 'synchronousController'
        : 'mountedEditor',
    'fixture': _structure
        ? '160-section plain and rich drafts with core syntax, media and galleries'
        : 'composer_analysis_benchmark_test structured draft',
    'edit': _caret
        ? 'Collapsed caret movement within prose; editBuild inserts one letter per operation.'
        : _structure
        ? 'Middle and top prose insertion, distinct heading delimiter edits, and actual history undo with exact caret and identity checks.'
        : 'Cumulative single-letter insertion inside a prose word; markdownWhitespace inserts spaces for contextual fallback.',
    'cpuTiming': _caret
        ? 'buildTextSpan and selection setter plus buildTextSpan measured separately. Style resolution, edit generation, result consumption and validation excluded.'
        : _structure
        ? 'Synchronous text.value setter or history.undo plus blocks.index, text.blockGaps and text.todos getters. Excludes edit generation, undo setup, checksum consumption and verification.'
        : 'Analysis or synchronous setter only. Excludes edit generation and verification.',
    'frameTiming': _cpuOnly || _structure
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
