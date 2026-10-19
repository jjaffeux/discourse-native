#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from statistics import median
import time
from urllib.parse import urlencode
from urllib.request import urlopen


SOURCE = 'lib/src/ui/components/d_command.dart'


def block(source, marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def library(source):
    prepared = 'class _DCommandSearchQuery' in source
    parts = [block(source, 'class _DScoredItem<T>')]
    if prepared:
        parts += [block(source, 'class _DCommandSearchQuery'),
                  block(source, 'class _DCommandSearchData')]
    else:
        parts += [block(source, 'double _defaultCommandFilter(')]
    score = block(source, '  List<_DScoredItem<T>> _score(')
    cache = 'final _searchData = Expando<_DCommandSearchData>();' if prepared else ''
    argument = ', _DCommandSearchQuery(query)' if prepared else ''
    return '''
class DCommandItem<T> {
  DCommandItem(this.value, this.searchValue, this.keywords, this.forceMount);
  final T value;
  final String searchValue;
  final List<String> keywords;
  final bool forceMount;
  String get effectiveSearchValue => searchValue;
}
class _Controller { _Controller(this.query); final String query; }
class _DCommandScope<T> {
  _DCommandScope(String query) : controller = _Controller(query);
  final _Controller controller;
  final shouldFilter = true;
''' + ('' if prepared else 'final filter = _defaultCommandFilter;') + '''
}
''' + '\n'.join(parts) + '''
class Engine<T> {
  Engine(this.items);
  final List<DCommandItem<T>> items;
''' + cache + score + '''
  List<(T, double, int)> run(String query) => [
    for (final row in _score(items, _DCommandScope<T>(query)''' + argument + '''))
      (row.item.value, row.score, row.order),
  ];
}
'''


def summarize(samples, keys, metric):
    groups = {}
    for sample in samples:
        key = tuple(sample[k] for k in keys)
        groups.setdefault(key, []).append(sample[metric])
    return [dict(zip(keys, key), median=median(values), minimum=min(values),
                 maximum=max(values), runs=len(values))
            for key, values in groups.items()]


DRIVER = r'''
import 'dart:convert';
import 'dart:io';
import 'baseline.dart' as a;
import 'candidate.dart' as b;

var sink = 0;
int digest(List<(int, double, int)> rows) {
  var sum = rows.length;
  for (final row in rows) {
    sum = (sum * 31 + row.$1 + (row.$2 * 10).toInt() + row.$3) & 0x3fffffff;
  }
  return sum;
}

void main(List<String> args) {
  final profile = args.contains('--profile');
  final results = <Map<String, Object>>[];
  for (final count in [250, 2000, 10000]) {
    final ai = List.generate(count, (i) => a.DCommandItem(
      i, ' Category $i sailing discussion ',
      [' alias-$i ', ' navigation ', 'community ${i % 20}'], i % 111 == 0));
    final bi = List.generate(count, (i) => b.DCommandItem(
      i, ' Category $i sailing discussion ',
      [' alias-$i ', ' navigation ', 'community ${i % 20}'], i % 111 == 0));
    final ae = a.Engine(ai), be = b.Engine(bi);
    final queries = ['', ' ', 'c', 'category 19', 'navigation',
      'sailing 19', 'ALIAS-${count - 1}', 'missing'];
    for (final q in queries) {
      final ar = ae.run(q), br = be.run(q);
      if (ar.length != br.length) throw StateError('count $count $q');
      for (var i = 0; i < ar.length; i++) {
        if (ar[i] != br[i]) throw StateError('ordering $count $q $i');
      }
    }
    if (profile) {
      final watch = Stopwatch()..start();
      while (watch.elapsedMilliseconds < 7000) {
        for (final q in queries) sink ^= digest(ae.run(q));
      }
      continue;
    }
    for (final q in queries) {
      for (var warmup = 0; warmup < 20; warmup++) {
        sink ^= digest(ae.run(q)); sink ^= digest(be.run(q));
      }
      for (var round = 0; round < 6; round++) {
        for (final side in (round.isEven ? ['baseline', 'candidate'] : ['candidate', 'baseline'])) {
          final run = side == 'baseline' ? ae.run : be.run;
          final watch = Stopwatch()..start();
          var iterations = 0;
          do { sink ^= digest(run(q)); iterations++; }
          while (watch.elapsedMicroseconds < 60000);
          results.add({'count':count,'query':q,'side':side,'round':round,
            'us':watch.elapsedMicroseconds / iterations,'iterations':iterations});
        }
      }
    }
    for (var round = 0; round < 6; round++) {
      for (final side in (round.isEven ? ['baseline', 'candidate'] : ['candidate', 'baseline'])) {
        final watch = Stopwatch()..start();
        var iterations = 0;
        do {
          sink ^= digest(side == 'baseline'
            ? a.Engine(ai).run('category 19')
            : b.Engine(bi).run('category 19'));
          iterations++;
        } while (watch.elapsedMicroseconds < 60000);
        results.add({'count':count,'query':'cold category 19','side':side,'round':round,
          'us':watch.elapsedMicroseconds / iterations,'iterations':iterations});
      }
    }
  }
  stdout.writeln(jsonEncode({'samples':results,'sink':sink,'errors':0}));
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--widget', action='store_true')
    parser.add_argument('--profile', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    args.output.mkdir(parents=True, exist_ok=True)
    with (args.output / 'environment.txt').open('w') as output:
        for command in [['uptime'], ['sysctl', '-n', 'hw.ncpu'], ['dart', '--version'],
                        ['ps', '-Ao', 'pid,pcpu,comm', '-r']]:
            subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
    baseline = subprocess.check_output(
        ['git', 'show', f'{args.baseline}:{SOURCE}'], cwd=root, text=True)
    candidate = (root / SOURCE).read_text()
    (args.output / 'baseline-source.dart').write_text(baseline)
    (args.output / 'candidate-source.dart').write_text(candidate)
    for name, source in [('baseline', baseline), ('candidate', candidate)]:
        (args.output / f'{name}.dart').write_text(library(source))
    (args.output / 'driver.dart').write_text(DRIVER)
    subprocess.run(['dart', 'compile', 'exe', str(args.output / 'driver.dart'),
                    '-o', str(args.output / 'command-search')], check=True, cwd=root)
    with (args.output / 'aot.json').open('w') as output:
        subprocess.run([str(args.output / 'command-search')], stdout=output, check=True)
    samples = json.loads((args.output / 'aot.json').read_text())['samples']
    summary = {'aotUs':summarize(samples, ['count','query','side'], 'us')}
    if args.profile:
        with (args.output / 'baseline-profile-vm.log').open('w') as output:
            process = subprocess.Popen(
                ['dart', '--observe=0', '--no-pause-isolates-on-exit',
                 str(args.output / 'driver.dart'), '--profile'],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                for line in process.stdout:
                    output.write(line)
                    match = re.search(r'http://127\.0\.0\.1:\d+/\S+', line)
                    if match:
                        service = match.group(0)
                        break
                else:
                    raise RuntimeError('VM service did not start')

                def rpc(method, **parameters):
                    with urlopen(service + method + '?' + urlencode(parameters)) as response:
                        result = json.load(response)
                    if 'error' in result:
                        raise RuntimeError(result['error'])
                    return result['result']

                isolate = rpc('getVM')['isolates'][0]['id']
                time.sleep(5)
                profile = rpc('getCpuSamples', isolateId=isolate,
                              timeOriginMicros=0, timeExtentMicros=10**16)
                if not profile.get('sampleCount'):
                    raise RuntimeError('CPU profile contained no samples')
                (args.output / 'baseline-cpu-profile.json').write_text(json.dumps(profile))
                output.write(process.communicate(timeout=40)[0])
                if process.returncode:
                    raise RuntimeError('profile workload failed')
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait()
    if args.widget:
        generated = root / 'lib/src/ui/components/_d_command_benchmark_baseline.dart'
        test = root / 'test/ui/_d_command_search_paired.generated_test.dart'
        workload = (root / 'test/ui/d_command_search_performance_test.dart').read_text()
        imports, body = workload.split('void main() {', 1)
        body = 'void main() {' + body
        body = body.replace('run < 6', 'run < 1')
        functions = []
        for side in ['baseline', 'candidate']:
            text = body.replace('void main()', f'void {side}Tests(int round)')
            text = text.replace('command search workload with', f'$round {side} command search workload with')
            text = text.replace("'run': run,", f"'run': round, 'side': '{side}',")
            if side == 'baseline':
                text = text.replace('DCommand', 'baseline.BaselineDCommand')
            functions.append(text)
        try:
            generated.write_text(baseline.replace('DCommand', 'BaselineDCommand'))
            test.write_text(imports +
                "import 'package:discourse_native/src/ui/components/_d_command_benchmark_baseline.dart' as baseline;\n" +
                'void main() { for (var r = 0; r < 6; r++) { if (r.isEven) { baselineTests(r); candidateTests(r); } else { candidateTests(r); baselineTests(r); } } }\n' +
                '\n'.join(functions))
            with (args.output / 'widget.log').open('w') as output:
                subprocess.run(['flutter', 'test', '--no-pub', str(test), '--reporter', 'expanded'],
                               cwd=root, stdout=output, stderr=subprocess.STDOUT, check=True)
        finally:
            generated.unlink(missing_ok=True)
            test.unlink(missing_ok=True)
        widget = []
        for line in (args.output / 'widget.log').read_text().splitlines():
            if 'COMMAND_SEARCH_WIDGET ' in line:
                widget.extend(json.loads(line.split('COMMAND_SEARCH_WIDGET ', 1)[1]))
        widget = [sample for sample in widget if sample['run'] > 0]
        for sample in widget:
            sample['queriesUs'] = sum(sample['queryUs'].values())
        summary['widgetUs'] = {
            metric:summarize(widget, ['count','side'], metric)
            for metric in ['openUs','queriesUs','selectionUs']
        }
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2))
    (args.output / 'revisions.json').write_text(json.dumps({
        'baseline':args.baseline,
        'candidateBase':subprocess.check_output(['git','rev-parse','HEAD'], cwd=root, text=True).strip(),
        'candidateSourceSha256':hashlib.sha256(candidate.encode()).hexdigest(),
        'source':SOURCE,
        'scope':'AOT extracted production scorer with descriptor stubs; widget debug CPU latency',
    }, indent=2))


if __name__ == '__main__':
    main()
