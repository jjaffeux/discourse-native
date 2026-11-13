import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/sidebar_icon_loader.dart';
import 'package:discourse_native/src/models/plugin_icon_catalog.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final names = List.generate(12, (i) => 'site-artwork-$i');
  final json = [
    {
      'title': 'Community links',
      'links': [
        for (final name in names)
          {'name': name, 'value': '/$name', 'icon': name},
      ],
    },
  ];
  final samples = <int>[];
  for (var run = 0; run < 9; run++) {
    var requests = 0;
    var inFlight = 0;
    final loader = SidebarIconLoader((
      url, {
      required siteUrl,
      required accept,
    }) async {
      final name = url.pathSegments.last;
      final index = names.indexOf(name.substring(0, name.length - 4));
      if (index < 0 || ++inFlight > 4) {
        throw StateError('Unexpected artwork request');
      }
      requests++;
      // Two assets are slower to produce, as can happen with an uncached
      // sprite or uneven upstream latency.
      await Future<void>.delayed(
        Duration(milliseconds: index % 4 == 0 ? 65 : 18),
      );
      inFlight--;
      return http.Response(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M0 0h24v24z"/></svg>',
        200,
      );
    }, const CoreIconNameDecoder());
    final watch = Stopwatch()..start();
    final result = await loader.load(json, 'https://forum.example');
    watch.stop();
    final icons = result.single.destinations;
    if (requests != names.length ||
        icons.length != names.length ||
        !List.generate(
          names.length,
          (i) => icons[i].icon.name == names[i],
        ).every((value) => value)) {
      throw StateError(
        'The sidebar did not resolve every custom icon in order',
      );
    }
    if (run >= 2) samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  stdout.writeln(
    jsonEncode({
      'load_custom_sidebar_artwork': samples[3],
      'resolve_composite_sidebar_artwork': await _composite(),
    }),
  );
  exit(0);
}

Future<int> _composite() async {
  final samples = <int>[];
  const references = ['site-badge', 'site-decoration'];
  const artwork = 'site-emblem';
  for (var run = 0; run < 9; run++) {
    final requests = <String>[];
    final loader = SidebarIconLoader((
      url, {
      required siteUrl,
      required accept,
    }) async {
      final name = url.pathSegments.last.split('.').first;
      requests.add(name);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final body = switch (name) {
        artwork =>
          '<use href="#${references.first}"/><use href="#${references.last}"/>',
        'site-badge' => '<path d="M0 0h24v24z"/>',
        'site-decoration' => '<circle cx="8" cy="8" r="4"/>',
        _ => throw StateError('Unexpected symbol $name'),
      };
      return http.Response(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">$body</svg>',
        200,
      );
    }, const CoreIconNameDecoder());
    final watch = Stopwatch()..start();
    final result = await loader.load([
      {
        'title': 'Community links',
        'links': [
          {'name': 'Site emblem', 'value': '/emblem', 'icon': artwork},
        ],
      },
    ], 'https://forum.example');
    watch.stop();
    final icon = result.single.destinations.single.icon;
    if (icon.name != artwork ||
        references.any((id) => !icon.svg.contains('id="$id"')) ||
        requests.length != 3 ||
        !requests.toSet().containsAll([artwork, ...references])) {
      throw StateError('The composite icon did not resolve');
    }
    if (run >= 2) samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  return samples[3];
}
