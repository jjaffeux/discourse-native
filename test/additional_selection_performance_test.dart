import 'dart:collection';
import 'dart:math';

import 'package:discourse_native/src/data/discover_site.dart';
import 'package:discourse_native/src/shell/image_decode.dart';
import 'package:flutter_test/flutter_test.dart';

const baseline = bool.fromEnvironment('PERF_BASELINE');

void main() {
  test('discovery reads only through the tenth eligible distinct site', () {
    final sites = _ReadSites([
      const DiscoverSite(url: 'bad', title: 'Invalid'),
      const DiscoverSite(url: 'https://added.example', title: 'Added'),
      const DiscoverSite(url: 'https://one.example/', title: 'First'),
      const DiscoverSite(url: 'https://one.example', title: 'Duplicate'),
      for (var i = 0; i < 100; i++)
        DiscoverSite(url: 'https://forum-$i.example', title: 'Forum $i'),
    ]);
    final selected = DiscoverSite.suggestions(sites, [
      'https://added.example/',
    ]);
    expect(selected.map((site) => site.title), [
      'First',
      for (var i = 0; i < 9; i++) 'Forum $i',
    ]);
    if (!baseline) expect(sites.reads, 13);
    // ignore: avoid_print
    print('WORK discovery_site_reads=${sites.reads}');
    expect(() => selected.add(sites.values.last), throwsUnsupportedError);
  });

  test(
    'discovery returns all available entries when fewer than ten qualify',
    () {
      const sites = [
        DiscoverSite(url: 'https://a.example/sub', title: 'A'),
        DiscoverSite(url: 'https://a.example/sub/', title: 'Duplicate'),
        DiscoverSite(url: 'https://a.example/other', title: 'B'),
      ];
      expect(DiscoverSite.suggestions(sites, []).map((s) => s.title), [
        'A',
        'B',
      ]);
      expect(DiscoverSite.suggestions(sites, [sites.first.url]), [sites.last]);
    },
  );

  test(
    'density selection matches sorted reference including nonfinite DPR',
    () {
      final random = Random(125);
      for (var trial = 0; trial < 100; trial++) {
        final entries = [
          for (var i = 0; i < random.nextInt(40); i++)
            ('/image-$i.png', random.nextInt(16) / 4),
        ];
        final srcset = entries.map((e) => '${e.$1} ${e.$2}x').join(', ');
        for (final src in ['', '/original.png']) {
          final densities = <double, String>{};
          for (final (url, density) in entries) {
            densities.putIfAbsent(density, () => url);
          }
          if (src.isNotEmpty) densities.putIfAbsent(1, () => src);
          final ordered = densities.keys.toList()..sort();
          for (final dpr in [
            0.0,
            1.0,
            1.009,
            1.011,
            1.5,
            2.0,
            5.0,
            double.nan,
            double.infinity,
            double.negativeInfinity,
          ]) {
            final expected = ordered.isEmpty
                ? src
                : densities[ordered.firstWhere(
                    (density) => density >= dpr - 0.01,
                    orElse: () => ordered.last,
                  )]!;
            expect(
              srcsetCandidate(src: src, srcset: srcset, devicePixelRatio: dpr),
              expected,
              reason: '$src $srcset $dpr',
            );
          }
        }
      }
    },
  );
}

class _ReadSites extends IterableBase<DiscoverSite> {
  _ReadSites(this.values);
  final List<DiscoverSite> values;
  var reads = 0;

  @override
  Iterator<DiscoverSite> get iterator => values.map((site) {
    reads++;
    return site;
  }).iterator;
}
