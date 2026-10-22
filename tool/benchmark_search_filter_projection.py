#!/usr/bin/env python3
"""Compare production search getters and panel pumps with baseline getter bodies."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
from statistics import median
import subprocess

CONTROLLER = Path('lib/src/shell/global_search_controller.dart')
FILTERS = Path('lib/src/shell/global_search_filters.dart')
PROBE = Path('test/search_filter_projection_paired_probe_test.dart')

WORKLOAD = r'''
  testWidgets('paired filter projection benchmark', (tester) async {
    var checksum = 0;
    final references = <String, List<String>>{};
    final panelReferences = <String, List<String>>{};
    String projection(GlobalSearchController c) => jsonEncode([
      c.availableFilters.map((f) => [f.id, f.label]).toList(),
      c.orderedConditionIndices.map((i) => [c.conditions[i].filterId, c.conditions[i].operator, c.conditions[i].value]).toList(),
      c.stagedFilter?.id, c.stagedTerm, c.stagedOperator,
      c.hintedFilters.map((f) => f.id).toList(), c.wordsQuery,
    ]);
    for (final scenario in ['forum', 'messages', 'chat', 'restricted']) {
      final scope = switch (scenario) {
        'messages' => GlobalSearchScope.messages,
        'chat' => chatSearchScope,
        _ => GlobalSearchScope.forum,
      };
      final ids = switch (scenario) {
        'messages' => ['messageAuthor', 'messagePostDate'],
        'chat' => ['chatAuthor', 'chatChannel'],
        'restricted' => ['author', 'topicAuthor'],
        _ => ['author', 'topicAuthor', 'category', 'tags'],
      };
      final inputs = switch (scenario) {
        'messages' => ['d', 'de', 'design', 'design messageAu', 'design messageAuthor:s',
          'design messageAuthor:sam', 'design before:2026-01-01', 'design '],
        'chat' => ['d', 'de', 'design', 'design chatAu', 'design chatAuthor:s',
          'design chatAuthor:sam', 'design chatChannel:12', 'design '],
        _ => ['d', 'de', 'des', 'design', 'design au', 'design aut',
          'design author:', 'design author:s', 'design author:sam',
          'design -tag:bug', 'design category:1', 'design '],
      };
      for (var round = -1; round < 5; round++) {
        for (final side in round.isEven ? ['baseline', 'candidate'] : ['candidate', 'baseline']) {
          final opening = Stopwatch()..start();
          final controller = side == 'baseline'
              ? await _pumpBaseline(tester) : await _pump(tester);
          opening.stop();
          if (scenario == 'restricted') {
            controller.configure(siteUrl: controller.siteUrl,
              capabilities: const GlobalSearchCapabilities(tagging: false));
          }
          controller.setScope(scope);
          expect(controller.scope, scope);
          for (final id in ids) {
            controller.addCondition(GlobalSearchCondition(filterId: id,
              operator: ['category', 'tags'].contains(id) ? 'any' : id.endsWith('PostDate') ? 'after' : 'is',
              value: [id == 'category' || id == 'chatChannel' ? '1' : id.endsWith('PostDate') ? '2026-01-01' : 'sam']));
          }
          final signatures = <String>[];
          for (final input in inputs) {
            controller.setQuery(input);
            signatures.add(projection(controller));
          }
          if (references.containsKey(scenario)) {
            expect(signatures, references[scenario]);
          } else {
            references[scenario] = signatures;
          }
          final before = benchmarkCounts();
          final watch = Stopwatch()..start();
          for (var repeat = 0; repeat < 10; repeat++) {
            for (final input in inputs) {
              controller.setQuery(input);
              checksum += controller.availableFilters.length;
              checksum += controller.orderedConditionIndices.length;
              checksum += controller.stagedFilter?.id.length ?? 0;
              checksum += controller.stagedTerm.length;
              checksum += controller.stagedOperator.length;
              checksum += controller.hintedFilters.length;
              checksum += controller.wordsQuery.length;
            }
          }
          watch.stop();
          final after = benchmarkCounts();
          final panel = Stopwatch();
          final panelSignatures = <String>[];
          for (final input in inputs) {
            panel.start();
            controller.setQuery(input);
            await tester.pump();
            panel.stop();
            panelSignatures.add(jsonEncode([
              find.byType(DItem).evaluate().map((e) => e.widget.key.toString()).toList(),
              find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList(),
            ]));
          }
          if (panelReferences.containsKey(scenario)) {
            expect(panelSignatures, panelReferences[scenario]);
          } else {
            panelReferences[scenario] = panelSignatures;
          }
          controller.clearConditions();
          final small = Stopwatch()..start();
          for (var repeat = 0; repeat < 100; repeat++) {
            controller.setQuery(repeat.isEven ? 'foo' : 'bar');
            checksum += controller.wordsQuery.length;
          }
          small.stop();
          final full = controller.capabilities;
          final replacement = Stopwatch()..start();
          final replacementSignatures = <String>[];
          for (final capabilities in [const GlobalSearchCapabilities(tagging: false), full]) {
            controller.configure(siteUrl: controller.siteUrl, capabilities: capabilities);
            controller.setScope(GlobalSearchScope.forum);
            controller.setQuery('tags:blue');
            replacementSignatures.add(projection(controller));
          }
          for (final locale in ['en', 'fr', 'en']) {
            Intl.withLocale(locale, () => replacementSignatures.add(projection(controller)));
          }
          replacement.stop();
          final replacementKey = '$scenario-replacement';
          if (references.containsKey(replacementKey)) {
            expect(replacementSignatures, references[replacementKey]);
          } else {
            references[replacementKey] = replacementSignatures;
          }
          if (round >= 0) {
            debugPrint('FILTER_SAMPLE ${jsonEncode({
              'case': scenario, 'round': round, 'side': side,
              'opening_us': opening.elapsedMicroseconds, 'controller_us': watch.elapsedMicroseconds,
              'panel_us': panel.elapsedMicroseconds, 'small_us': small.elapsedMicroseconds,
              'replacement_us': replacement.elapsedMicroseconds,
              'core_builds': after[0] - before[0], 'message_builds': after[1] - before[1],
              'tail_parses': after[2] - before[2],
            })}');
          }
          expect(tester.takeException(), isNull);
          await tester.pumpAndSettle();
        }
      }
    }
    debugPrint('FILTER_CHECKSUM $checksum');
    expect(checksum, greaterThan(1000));
  });
'''


PROFILE = r'''
  testWidgets('filter projection cpu profile', (tester) async {
    final controller = await _pumpBaseline(tester);
    controller.setScope(GlobalSearchScope.forum);
    controller.addCondition(const GlobalSearchCondition(filterId: 'author', value: ['sam']));
    controller.addCondition(const GlobalSearchCondition(filterId: 'topicAuthor', value: ['sam']));
    await tester.runAsync(() async {
      final uri = (await developer.Service.getInfo()).serverUri!;
      final vm = await vmServiceConnectUri(uri.replace(scheme: 'ws', path: '${uri.path}ws').toString());
      final id = developer.Service.getIsolateID(Isolate.current)!;
      final start = (await vm.getVMTimelineMicros()).timestamp!;
      final watch = Stopwatch()..start();
      var sink = 0;
      while (watch.elapsedMilliseconds < 4000) {
        for (final input in ['design au', 'design author:sam', 'cat']) {
          controller.setQuery(input);
          sink += controller.availableFilters.length + controller.orderedConditionIndices.length;
          sink += controller.stagedTerm.length + controller.stagedOperator.length;
          sink += controller.hintedFilters.length + controller.wordsQuery.length;
        }
      }
      final end = (await vm.getVMTimelineMicros()).timestamp!;
      final samples = await vm.getCpuSamples(id, start, end - start);
      File(const String.fromEnvironment('PROFILE_OUTPUT')).writeAsStringSync(jsonEncode(samples.toJson()));
      debugPrint('FILTER_PROFILE_SINK $sink');
      await vm.dispose();
    });
    await tester.pumpAndSettle();
  });
'''


def between(source, start, end):
    return source[source.index(start):source.index(end, source.index(start))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--counts', action='store_true')
    parser.add_argument('--profile', action='store_true')
    args = parser.parse_args()
    if PROBE.exists():
        parser.error(f'Refusing to overwrite {PROBE}')
    if args.counts and args.profile:
        parser.error('Count instrumentation and CPU profiling require separate runs')
    args.output.mkdir(parents=True, exist_ok=True)
    original_controller = CONTROLLER.read_text()
    original_filters = FILTERS.read_text()
    old = subprocess.check_output(['git', 'show', f'{args.baseline}:{CONTROLLER}'], text=True)
    (args.output/'baseline-controller.dart').write_text(old)
    (args.output/'candidate-controller.dart').write_text(original_controller)
    metadata = dict(baseline=args.baseline, candidate_head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        controller_sha256=hashlib.sha256(original_controller.encode()).hexdigest(),
        baseline_sha256=hashlib.sha256(old.encode()).hexdigest(),
        load_average=os.getloadavg(), cpu_count=os.cpu_count(),
        counts=args.counts, profile=args.profile)
    (args.output/'metadata.json').write_text(json.dumps(metadata, indent=2))
    getters = '\n'.join([
        between(old, '  List<GlobalSearchFilter> get availableFilters', '  List<GlobalSearchOrder> get orders'),
        between(old, '  List<int> get orderedConditionIndices', '  String get order'),
        between(old, '  GlobalSearchFilter? get stagedFilter', '  void beginFilter'),
    ])
    baseline_class = '''\nclass BenchmarkBaselineController extends GlobalSearchController {
      BenchmarkBaselineController({required super.api, required super.credentials,
        required super.lifecycle, super.debounceDuration});
    ''' + getters + '\n}\n'
    fixture = Path('test/global_search_panel_test.dart').read_text()
    pump = between(fixture, 'Future<GlobalSearchController> _pump(', 'class _PanelApi')
    baseline_pump = pump.replace('_pump(', '_pumpBaseline(', 1).replace(
        'GlobalSearchController(', 'BenchmarkBaselineController(')
    source = fixture[:fixture.index('void main() {')] + 'void main() {' + (PROFILE if args.profile else WORKLOAD) + '}\n'
    source += fixture[fixture.index('Finder _key'):]
    source += baseline_pump + baseline_class
    source = "import 'package:intl/intl.dart';\nimport 'dart:convert';\nimport 'package:discourse_native/src/shell/global_search_filters.dart';\n" + source
    if args.profile:
        source = "import 'dart:developer' as developer;\nimport 'dart:isolate';\nimport 'dart:io';\nimport 'package:vm_service/vm_service_io.dart';\n" + source
    counter_function = 'List<int> benchmarkCounts() => [0, 0, 0];\n'
    try:
        if args.counts:
            counters = '''
int benchmarkCoreBuilds = 0, benchmarkMessageBuilds = 0, benchmarkTailParses = 0;
List<GlobalSearchFilter> benchmarkCoreHit() { benchmarkCoreBuilds++; return const []; }
List<GlobalSearchFilter> benchmarkMessageHit() { benchmarkMessageBuilds++; return const []; }
String benchmarkTail(String query) { benchmarkTailParses++; return query.split(RegExp(r'\\s+')).last; }
'''
            filters = original_filters.replace(
                'get globalSearchFilters => <GlobalSearchFilter>[',
                'get globalSearchFilters => <GlobalSearchFilter>[...benchmarkCoreHit(),').replace(
                'get globalMessageSearchFilters => [',
                'get globalMessageSearchFilters => [...benchmarkMessageHit(),')
            FILTERS.write_text(filters + counters)
            tail = "query.split(RegExp(r'\\s+')).last"
            CONTROLLER.write_text(original_controller.replace(tail, 'benchmarkTail(query)'))
            source = source.replace(tail, 'benchmarkTail(query)')
            counter_function = 'List<int> benchmarkCounts() => [benchmarkCoreBuilds, benchmarkMessageBuilds, benchmarkTailParses];\n'
        PROBE.write_text(source + counter_function)
        options = ['--enable-vmservice', f'--dart-define=PROFILE_OUTPUT={args.output.resolve() / "cpu-samples.json"}'] if args.profile else []
        name = 'filter projection cpu profile' if args.profile else 'paired filter projection benchmark'
        run = subprocess.run(['flutter', 'test', '--no-pub', *options, str(PROBE),
            '--plain-name', name, '--reporter', 'expanded'],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (args.output/'run.log').write_text(run.stdout)
        print(run.stdout)
        if run.returncode:
            raise SystemExit(run.returncode)
        if args.profile:
            return
        samples = [json.loads(s) for s in re.findall(r'FILTER_SAMPLE (\{[^\n]+\})', run.stdout)]
        if len(samples) != 40:
            raise RuntimeError(f'Expected forty consumed samples, got {len(samples)}')
        summary = {}
        for case in ['forum', 'messages', 'chat', 'restricted']:
            summary[case] = {}
            for side in ['baseline', 'candidate']:
                summary[case][side] = {}
                for metric in ['opening_us', 'controller_us', 'panel_us', 'small_us', 'replacement_us', 'core_builds', 'message_builds', 'tail_parses']:
                    values = [s[metric] for s in samples if s['side'] == side and s['case'] == case]
                    summary[case][side][metric] = dict(median=median(values), minimum=min(values), maximum=max(values))
        result = dict(baseline=args.baseline, counts=args.counts, errors=0, samples=samples, summary=summary,
            limits='Flutter debug widget-test CPU and pump timing; no network/device/frame-rate claim')
        (args.output/'summary.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(summary, indent=2))
    finally:
        if args.counts:
            CONTROLLER.write_text(original_controller)
            FILTERS.write_text(original_filters)
        PROBE.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
