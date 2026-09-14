import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _customSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
    '<path d="M0 16L8 0L16 16Z"/>'
    '<circle cx="8" cy="10" r="2" fill="#ff6600"/></svg>';

Map<String, Object?> _section(List<String?> icons, {bool community = false}) =>
    {
      'id': 2,
      'title': 'Projects',
      if (community) 'section_type': 'community',
      'links': [
        for (var index = 0; index < icons.length; index++)
          {
            'id': index,
            'name': 'Link $index',
            'value': '/link-$index',
            'icon': icons[index],
            if (community) 'segment': 'secondary',
          },
      ],
    };

String _fixture(String name) =>
    File('test/fixtures/sidebar-icons/$name.svg').readAsStringSync();

void main() {
  test(
    'loads solid, regular, brand, custom and composite sidebar icons',
    () async {
      const names = [
        'bicycle',
        'far-address-book',
        'fab-github',
        'theme-logo',
        'table-cells-plus',
      ];
      final requests = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/sidebar_sections.json') {
            return http.Response(
              jsonEncode({
                'sidebar_sections': [_section(names)],
              }),
              200,
            );
          }
          final name = request.url.pathSegments.last.replaceFirst('.svg', '');
          return http.Response(
            name == 'theme-logo' ? _customSvg : _fixture(name),
            200,
          );
        }),
      );
      addTearDown(api.close);

      final section = (await api.customSidebarSections(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
        clientId: 'client',
      )).single;

      expect(section.destinations.map((link) => link.icon.name), names);
      expect(
        section.destinations.every((link) => link.icon.preserveColors),
        isTrue,
      );
      expect(section.destinations.map((link) => link.url), [
        for (var index = 0; index < names.length; index++) '/link-$index',
      ]);
      final composite = section.destinations.last.icon.svg;
      expect(composite, contains('<defs>'));
      expect(composite, contains('<symbol'));
      expect(composite, contains('id="table-cells"'));
      expect(composite, contains('id="plus"'));
      expect(requests.first.headers['User-Api-Key'], 'secret');
      for (final request in requests.skip(1)) {
        expect(request.url.path, startsWith('/svg-sprite/forum.example/icon/'));
        expect(request.headers, isNot(contains('User-Api-Key')));
        expect(request.headers, isNot(contains('User-Api-Client-Id')));
      }
    },
  );

  test('deduplicates and caches artwork by forum and subfolder', () async {
    final iconRequests = <Uri>[];
    final api = DiscourseApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/site.json')) {
          return http.Response(
            jsonEncode({
              'anonymous_sidebar_sections': [
                _section(['theme-logo', 'theme-logo'], community: true),
              ],
            }),
            200,
          );
        }
        iconRequests.add(request.url);
        return http.Response(
          _customSvg.replaceFirst('16 16Z', '${iconRequests.length} 16Z'),
          200,
        );
      }),
    );
    addTearDown(api.close);

    Future<DIconData> load(String site) async =>
        (await api.customSidebarSections(
          siteUrl: site,
        )).single.moreDestinations.first.icon;
    final first = await load('https://forum.example/forum');
    final cached = await load('https://forum.example/forum/');
    final otherFolder = await load('https://forum.example/other');
    final otherSite = await load('https://another.example/forum');

    expect(first.svg, cached.svg);
    expect(otherFolder.svg, isNot(first.svg));
    expect(otherSite.svg, isNot(first.svg));
    expect(iconRequests.map((url) => url.toString()), [
      'https://forum.example/forum/svg-sprite/forum.example/icon/theme-logo.svg',
      'https://forum.example/other/svg-sprite/forum.example/icon/theme-logo.svg',
      'https://another.example/forum/svg-sprite/another.example/icon/theme-logo.svg',
    ]);
  });

  test(
    'does not request bundled, blank, discarded or out-of-limit icons',
    () async {
      final requests = <String>[];
      final valid = _section(['heart', null, '']);
      final links = valid['links']! as List<Map<String, Object?>>;
      links.add({'name': 'No URL', 'icon': 'invalid-link'});
      while (links.length < SidebarSection.maximumCustomLinks) {
        links.add({'name': 'Known', 'value': '/known', 'icon': 'd-liked'});
      }
      links.add({
        'name': 'Beyond limit',
        'value': '/limit',
        'icon': 'beyond-limit',
      });
      final api = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request.url.path);
          return http.Response(
            jsonEncode({
              'sidebar_sections': [
                valid,
                {
                  ..._section(['discarded-section']),
                  'section_type': 'categories',
                },
                {
                  ..._section(['no-title']),
                  'title': null,
                },
                {
                  ..._section(['primary'], community: true),
                  'links': [
                    {
                      'name': 'Primary',
                      'value': '/',
                      'icon': 'primary',
                      'segment': 'primary',
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);

      final sections = await api.customSidebarSections(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
      );
      expect(requests, ['/sidebar_sections.json']);
      expect(sections.first.destinations.first.icon, DIcons.heart);
      expect(sections.first.destinations[1].icon, DIcons.link);
    },
  );

  for (final failure in [
    'missing',
    'offline',
    'html',
    'malformed',
    'empty',
    'empty-body',
    'cycle',
    'dependency',
  ]) {
    test('keeps links usable when artwork is $failure', () async {
      var recovered = false;
      final api = DiscourseApi(
        client: MockClient((request) async {
          if (request.url.path == '/site.json') {
            return http.Response(
              jsonEncode({
                'anonymous_sidebar_sections': [
                  _section(['theme-logo']),
                ],
              }),
              200,
            );
          }
          if (recovered && failure != 'cycle' && failure != 'dependency') {
            return http.Response(_customSvg, 200);
          }
          return switch (failure) {
            'missing' => http.Response('', 404),
            'offline' => throw const SocketException('Offline'),
            'html' => http.Response('<html><body>Log in</body></html>', 200),
            'malformed' => http.Response('<svg><path></svg>', 200),
            'empty' => http.Response('<svg/>', 200),
            'empty-body' => http.Response('', 200),
            'cycle' => http.Response(
              '<svg><use href="#theme-logo"/></svg>',
              200,
            ),
            'dependency' =>
              request.url.path.endsWith('theme-logo.svg')
                  ? http.Response('<svg><use href="#missing"/></svg>', 200)
                  : http.Response('', 404),
            _ => throw StateError(failure),
          };
        }),
      );
      addTearDown(api.close);

      final link = (await api.customSidebarSections(
        siteUrl: 'https://forum.example',
      )).single.destinations.single;
      expect(link.label, 'Link 0');
      expect(link.url, '/link-0');
      expect(link.icon, DIcons.link);
      recovered = true;
      if (failure != 'cycle' && failure != 'dependency') {
        final retry = (await api.customSidebarSections(
          siteUrl: 'https://forum.example',
        )).single.destinations.single;
        expect(retry.icon.name, 'theme-logo');
      }
    });
  }

  testWidgets('server icons render and activate in Native sidebar rows', (
    tester,
  ) async {
    const names = [
      'bicycle',
      'far-address-book',
      'fab-github',
      'table-cells-plus',
      'theme-logo',
    ];
    final api = DiscourseApi(
      client: MockClient((request) async {
        if (request.url.path == '/site.json') {
          return http.Response(
            jsonEncode({
              'anonymous_sidebar_sections': [_section(names)],
            }),
            200,
          );
        }
        final name = request.url.pathSegments.last.replaceFirst('.svg', '');
        return http.Response(
          name == 'theme-logo' ? _customSvg : _fixture(name),
          200,
        );
      }),
    );
    addTearDown(api.close);
    final section = (await tester.runAsync(
      () => api.customSidebarSections(siteUrl: 'https://forum.example'),
    ))!.single;
    String? selected;

    for (final brightness in Brightness.values) {
      for (final width in [220.0, 320.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Center(
              child: SizedBox(
                width: width,
                child: DSidebarMenu(
                  children: [
                    for (final link in section.destinations)
                      DSidebarMenuButton(
                        icon: RepaintBoundary(
                          key: ValueKey(link.icon.name),
                          child: DIcon(link.icon),
                        ),
                        onPressed: () => selected = link.url,
                        child: Text(link.label),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widgetList<DIcon>(find.byType(DIcon))
              .map((icon) => icon.icon.name),
          names,
        );
        for (final name in names) {
          final tokens = DTokens.of(tester.element(find.byKey(ValueKey(name))));
          final tint = IconTheme.of(
            tester.element(find.byKey(ValueKey(name))),
          ).color!;
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(ValueKey(name)),
          );
          final pixelCounts = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              final pixels = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              var painted = 0;
              var background = 0;
              var customColor = 0;
              for (var offset = 3; offset < pixels.length; offset += 4) {
                if (pixels[offset] == 255 &&
                    pixels[offset - 3] == (tint.r * 255).round() &&
                    pixels[offset - 2] == (tint.g * 255).round() &&
                    pixels[offset - 1] == (tint.b * 255).round()) {
                  painted++;
                }
                if (pixels[offset] == 255 &&
                    pixels[offset - 3] == (tokens.background.r * 255).round() &&
                    pixels[offset - 2] == (tokens.background.g * 255).round() &&
                    pixels[offset - 1] == (tokens.background.b * 255).round()) {
                  background++;
                }
                if (pixels[offset] == 255 &&
                    pixels[offset - 3] == 255 &&
                    pixels[offset - 2] == 102 &&
                    pixels[offset - 1] == 0) {
                  customColor++;
                }
              }
              return (painted, background, customColor);
            } finally {
              image.dispose();
            }
          });
          expect(
            pixelCounts!.$1,
            greaterThan(0),
            reason: '$name rendered blank',
          );
          if (name == 'table-cells-plus') {
            expect(
              pixelCounts.$2,
              greaterThan(0),
              reason: 'badge background lost',
            );
          }
          if (name == 'theme-logo') {
            expect(pixelCounts.$3, greaterThan(0), reason: 'custom color lost');
          }
        }
        await tester.tap(find.text('Link 3'));
        expect(selected, '/link-3');
      }
    }
  });
}
