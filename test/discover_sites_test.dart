import 'dart:convert';

import 'package:discourse_native/src/data/discover_sites.dart';
import 'package:discourse_native/src/models/discover_site.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/discover_sites.dart';

void main() {
  test(
    'fetches one public batch of 50 and caches concurrent and later reads',
    () async {
      var requests = 0;
      final source = DiscoverSites(
        client: MockClient((request) async {
          requests++;
          expect(request.url.origin, 'https://discover.discourse.com');
          expect(request.url.path, '/search.json');
          expect(request.url.queryParameters, {
            'q': '#discover #locale-en order:featured',
            'page': '1',
          });
          expect(
            request.headers.keys.any(
              (key) => key.toLowerCase().contains('api-key'),
            ),
            isFalse,
          );
          return http.Response(
            jsonEncode({'topics': List.generate(55, discoverEntry)}),
            200,
          );
        }),
      );
      addTearDown(source.dispose);

      final results = await Future.wait([source.load(), source.load()]);
      expect(results.first.length, 50);
      expect(identical(results.first, results.last), isTrue);
      expect(await source.load(), same(results.first));
      expect(requests, 1);
    },
  );

  test(
    'failures can be retried; malformed entries do not hide valid sites',
    () async {
      var requests = 0;
      final source = DiscoverSites(
        client: MockClient((_) async {
          if (++requests == 1) return http.Response('{}', 200);
          return http.Response(
            jsonEncode({
              'topics': [
                null,
                {'title': 'Unsafe', 'featured_link': 'javascript:alert(1)'},
                {
                  'title': 'Credentials',
                  'featured_link': 'https://user:secret@forum.example',
                },
                {'featured_link': 'https://missing-title.example'},
                discoverEntry(1),
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(source.dispose);
      await expectLater(source.load(), throwsFormatException);
      expect((await source.load()).single.title, 'Community 1');
      expect(requests, 2);
    },
  );

  test(
    'filters before taking ten, deduplicates, and retains subfolders and ports',
    () {
      final sites = [
        const DiscoverSite(
          url: 'https://community0.example/',
          title: 'Duplicate',
        ),
        ...List.generate(15, (i) => DiscoverSite.tryParse(discoverEntry(i))!),
      ];
      final results = DiscoverSite.suggestions(sites, [
        'https://community0.example',
        'https://COMMUNITY1.example/',
      ]);
      expect(
        results.map((site) => site.title),
        List.generate(10, (i) => 'Community ${i + 2}'),
      );
      expect(
        DiscoverSite.identity('https://forum.example/sub/'),
        'forum.example/sub',
      );
      expect(
        DiscoverSite.identity('https://forum.example:3000/sub'),
        'forum.example:3000/sub',
      );
      expect(
        DiscoverSite.suggestions(
          [
            const DiscoverSite(
              url: 'https://forum.example/sub',
              title: 'Subfolder',
            ),
            const DiscoverSite(
              url: 'https://forum.example:3000',
              title: 'Port',
            ),
          ],
          ['https://forum.example'],
        ).length,
        2,
      );
    },
  );
}
