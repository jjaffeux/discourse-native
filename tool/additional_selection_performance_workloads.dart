import 'package:discourse_native/src/models/discover_site.dart';
import 'package:discourse_native/src/shell/image_decode.dart';

Map<String, int> measureAdditionalSelectionPerformance() {
  final results = <String, int>{};
  void measure(String name, int iterations, void Function() action) {
    for (var i = 0; i < 20; i++) {
      action();
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      action();
    }
    results[name] = watch.elapsedMicroseconds;
  }

  for (final count in [30, 300]) {
    final sites = [
      for (var i = 0; i < count; i++)
        DiscoverSite(url: 'https://forum-$i.example', title: 'Forum $i'),
    ];
    measure('discovery_$count', 1000, () {
      final selected = DiscoverSite.suggestions(sites, const []);
      if (selected.length != 10 ||
          selected.first != sites.first ||
          selected.last != sites[9]) {
        throw StateError('Discovery selection changed');
      }
    });
  }

  for (final count in [3, 30]) {
    final srcset = [
      for (var i = count; i > 0; i--) '/image-$i.png ${i / 2}x',
    ].join(', ');
    final requested = count == 3 ? 1.5 : 7.5;
    final expected = count == 3 ? '/image-3.png' : '/image-15.png';
    measure('srcset_$count', 30000, () {
      final selected = srcsetCandidate(
        src: '/original.png',
        srcset: srcset,
        devicePixelRatio: requested,
      );
      if (selected != expected) throw StateError('Srcset selection changed');
    });
  }
  return results;
}
