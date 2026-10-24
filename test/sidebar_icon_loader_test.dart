import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/account_request_session.dart';
import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/custom_sidebar_sections.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/sidebar_icon_loader.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/plugin_api/plugin_icon_catalog.dart';
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
  sidebarArtworkReuseTests();
  signedInArtworkTests();
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

      final lifecycle = SiteLifecycle();
      final credentials = await AccountRequestSession(
        'https://forum.example',
        lifecycle.capture('https://forum.example'),
      ).credentials(const _SignedInCredentials());
      final section = (await credentials.run(
        () => api.customSidebarSections(
          siteUrl: 'https://forum.example',
          apiKey: credentials.apiKey,
          clientId: credentials.clientId,
        ),
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
    const instance = DiscourseInstance(
      url: 'https://forum.example',
      title: 'Forum',
      user: DiscourseUser(id: 7, username: 'reader'),
    );
    final owner = CustomSidebarSections(
      api: api,
      credentials: const _SignedInCredentials(),
      lifecycle: SiteLifecycle(),
      instanceFor: (_) => instance,
      selectedSite: () => instance.url,
      onChanged: () {},
    );
    addTearDown(owner.dispose);
    await tester.runAsync(() => owner.ensure(instance.url));
    final section = owner.customFor(instance.url).single;
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

SidebarIconLoader _artworkLoader(
  Future<http.Response> Function(http.Request) respond, {
  DateTime Function()? clock,
}) {
  final transport = DiscourseTransport.create(client: MockClient(respond));
  addTearDown(transport.close);
  return SidebarIconLoader(
    transport,
    const CoreIconNameDecoder(),
    clock: clock,
  );
}

Future<DIconData> _loadArtwork(SidebarIconLoader loader, String name) async =>
    (await loader.load([
      _section([name]),
    ], 'https://forum.example')).single.destinations.single.icon;

String _requestedArtwork(http.Request request) =>
    request.url.pathSegments.last.replaceFirst('.svg', '');

void sidebarArtworkReuseTests() {
  test('reuses completed immutable sidebar artwork', () async {
    var requests = 0;
    final loader = _artworkLoader((request) async {
      requests++;
      return http.Response(_customSvg, 200);
    });

    final first = await _loadArtwork(loader, 'theme-logo');
    final repeated = await _loadArtwork(loader, 'theme-logo');

    expect(identical(first, repeated), isTrue);
    expect(repeated.preserveColors, isTrue);
    expect(requests, 1);
  });

  test('composite artwork expires with its oldest dependency', () async {
    var now = DateTime.utc(2026, 1, 1);
    var generation = 'first';
    final requests = <String, int>{};
    final loader = _artworkLoader((request) async {
      final name = _requestedArtwork(request);
      requests.update(name, (value) => value + 1, ifAbsent: () => 1);
      return http.Response(
        name == 'composite'
            ? '<svg><use href="#shared"/></svg>'
            : '<svg><path data-generation="$generation"/></svg>',
        200,
      );
    }, clock: () => now);

    await _loadArtwork(loader, 'shared');
    now = now.add(const Duration(hours: 12));
    final first = await _loadArtwork(loader, 'composite');
    expect(identical(first, await _loadArtwork(loader, 'composite')), isTrue);
    now = now.add(const Duration(hours: 12));
    generation = 'second';
    final refreshed = await _loadArtwork(loader, 'composite');

    expect(first.svg, contains('data-generation="first"'));
    expect(refreshed.svg, contains('data-generation="second"'));
    expect(requests, {'shared': 2, 'composite': 1});
  });

  test('evicting a shared source invalidates completed composites', () async {
    var generation = 'first';
    final requests = <String, int>{};
    final loader = _artworkLoader((request) async {
      final name = _requestedArtwork(request);
      requests.update(name, (value) => value + 1, ifAbsent: () => 1);
      return http.Response(
        name == 'composite'
            ? '<svg><use href="#shared"/></svg>'
            : '<svg><path data-generation="$generation"/></svg>',
        200,
      );
    });

    await _loadArtwork(loader, 'shared');
    final first = await _loadArtwork(loader, 'composite');
    for (var index = 0; index < 255; index++) {
      await _loadArtwork(loader, 'filler-$index');
    }
    generation = 'second';
    final refreshed = await _loadArtwork(loader, 'composite');

    expect(first.svg, contains('data-generation="first"'));
    expect(refreshed.svg, contains('data-generation="second"'));
    expect(requests['shared'], 2);
    expect(requests['composite'], 1);
  });

  test(
    'does not retain an assembly invalidated while awaiting artwork',
    () async {
      var generation = 'first';
      final blockedStarted = Completer<void>();
      final releaseBlocked = Completer<void>();
      final loader = _artworkLoader((request) async {
        final name = _requestedArtwork(request);
        if (name == 'blocked') {
          blockedStarted.complete();
          await releaseBlocked.future;
        }
        return http.Response(
          name == 'composite'
              ? '<svg><use href="#shared"/><use href="#blocked"/></svg>'
              : '<svg><path data-generation="$generation"/></svg>',
          200,
        );
      });

      await _loadArtwork(loader, 'shared');
      final pending = _loadArtwork(loader, 'composite');
      await blockedStarted.future;
      for (var index = 0; index < 255; index++) {
        await _loadArtwork(loader, 'filler-$index');
      }
      generation = 'second';
      releaseBlocked.complete();
      final interrupted = await pending;
      final refreshed = await _loadArtwork(loader, 'composite');

      expect(interrupted.svg, contains('data-generation="first"'));
      expect(refreshed.svg, isNot(contains('data-generation="first"')));
      expect(refreshed.svg, contains('data-generation="second"'));
    },
  );

  test('concurrent sidebar loads assemble isolated XML trees', () async {
    final requests = <String, int>{};
    final loader = _artworkLoader((request) async {
      final name = _requestedArtwork(request);
      requests.update(name, (value) => value + 1, ifAbsent: () => 1);
      await Future<void>.delayed(Duration.zero);
      return http.Response(
        name == 'composite'
            ? '<svg><use href="#shared"/></svg>'
            : '<svg><path fill="#ff6600"/></svg>',
        200,
      );
    });

    final concurrent = await Future.wait([
      _loadArtwork(loader, 'composite'),
      _loadArtwork(loader, 'composite'),
    ]);
    final shared = await _loadArtwork(loader, 'shared');

    for (final icon in concurrent) {
      expect('<defs>'.allMatches(icon.svg).length, 1);
      expect('id="shared"'.allMatches(icon.svg).length, 1);
      expect(icon.svg, contains('fill="#ff6600"'));
      expect(icon.preserveColors, isTrue);
    }
    expect(concurrent.first.svg, concurrent.last.svg);
    expect(shared.svg, isNot(contains('<defs>')));
    expect(shared.svg, isNot(contains('<symbol')));
    expect(requests, {'composite': 1, 'shared': 1});
  });

  test('bounds retained raw source characters', () async {
    final requests = <String, int>{};
    final padding = 'x' * (1100 * 1024);
    final loader = _artworkLoader((request) async {
      final name = _requestedArtwork(request);
      requests.update(name, (value) => value + 1, ifAbsent: () => 1);
      return http.Response('<!--$padding--><svg><path/></svg>', 200);
    });

    await _loadArtwork(loader, 'large-one');
    await _loadArtwork(loader, 'large-two');
    final reloaded = await _loadArtwork(loader, 'large-one');

    expect(reloaded.name, 'large-one');
    expect(requests, {'large-one': 2, 'large-two': 1});
  });

  test('bounds completed artwork separately from shared raw sources', () async {
    final requests = <String, int>{};
    final padding = 'x' * (1100 * 1024);
    final loader = _artworkLoader((request) async {
      final name = _requestedArtwork(request);
      requests.update(name, (value) => value + 1, ifAbsent: () => 1);
      return http.Response(
        name == 'shared'
            ? '<svg><path data-padding="$padding"/></svg>'
            : '<svg><use href="#shared"/></svg>',
        200,
      );
    });

    final first = await _loadArtwork(loader, 'large-one');
    final cached = await _loadArtwork(loader, 'large-one');
    expect(identical(first, cached), isTrue);
    await _loadArtwork(loader, 'large-two');
    final reassembled = await _loadArtwork(loader, 'large-one');

    expect(identical(first, reassembled), isFalse);
    expect(reassembled.svg, first.svg);
    expect(requests, {'large-one': 1, 'shared': 1, 'large-two': 1});
    expect(
      identical(reassembled, await _loadArtwork(loader, 'large-one')),
      isTrue,
    );
  });

  test(
    'oversized raw sources never retain their compact assembled artwork',
    () async {
      var requests = 0;
      final padding = 'x' * (2 * 1024 * 1024);
      final loader = _artworkLoader((request) async {
        requests++;
        return http.Response('<!--$padding--><svg><path/></svg>', 200);
      });

      final first = await _loadArtwork(loader, 'oversized');
      final repeated = await _loadArtwork(loader, 'oversized');

      expect(first.svg, '<svg><path/></svg>');
      expect(repeated.svg, first.svg);
      expect(identical(first, repeated), isFalse);
      expect(requests, 2);
    },
  );
}

final class _SignedInCredentials implements ApiCredentialReader {
  const _SignedInCredentials();

  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'secret';

  @override
  Future<String> clientId() async => 'client';
}

Future<AccountRequestCredentials> _signedIn(SiteLifecycle lifecycle) =>
    AccountRequestSession(
      'https://forum.example',
      lifecycle.capture('https://forum.example'),
    ).credentials(const _SignedInCredentials());

void signedInArtworkTests() {
  for (final offOrigin in [false, true]) {
    test(
      'signed-in artwork ${offOrigin ? 'rejects off-origin' : 'follows same-origin'} redirects anonymously',
      () async {
        final requests = <http.Request>[];
        var redirect = true;
        final loader = _artworkLoader((request) async {
          requests.add(request);
          if (redirect && request.url.path.endsWith('theme-logo.svg')) {
            return http.Response(
              '',
              302,
              headers: {
                'location': offOrigin
                    ? 'https://other.example/icon.svg'
                    : '/redirected.svg',
              },
            );
          }
          return http.Response(_customSvg, 200);
        });
        final credentials = await _signedIn(SiteLifecycle());
        final first = await credentials.run(
          () => _loadArtwork(loader, 'theme-logo'),
        );
        expect(first.name, offOrigin ? 'link' : 'theme-logo');
        expect(requests, hasLength(offOrigin ? 1 : 2));
        expect(requests.every((r) => r.url.host == 'forum.example'), isTrue);
        for (final request in requests) {
          expect(request.headers['User-Api-Key'], isNull);
          expect(request.headers['User-Api-Client-Id'], isNull);
        }
        redirect = false;
        final recovered = await credentials.run(
          () => _loadArtwork(loader, 'theme-logo'),
        );
        expect(recovered.name, 'theme-logo');
        final cached = await credentials.run(
          () => _loadArtwork(loader, 'theme-logo'),
        );
        expect(cached, same(recovered));
        expect(requests, hasLength(2));
      },
    );
  }

  for (final dependency in [false, true]) {
    test(
      'retired ${dependency ? 'dependency' : 'artwork'} cannot populate replacement account cache',
      () async {
        final lifecycle = SiteLifecycle();
        final oldResponse = Completer<http.Response>();
        var pendingRequests = 0;
        final name = dependency ? 'table-cells-plus' : 'theme-logo';
        final loader = _artworkLoader((request) async {
          final requested = _requestedArtwork(request);
          if (dependency && requested != 'plus') {
            return http.Response(_fixture(requested), 200);
          }
          pendingRequests++;
          if (pendingRequests == 1) return oldResponse.future;
          return http.Response(dependency ? _fixture('plus') : _customSvg, 200);
        });
        final oldCredentials = await _signedIn(lifecycle);
        final retired = oldCredentials.run(() => _loadArtwork(loader, name));
        await pumpEventQueue();
        expect(pendingRequests, 1);
        lifecycle.invalidate('https://forum.example');
        final replacement = await _signedIn(lifecycle);
        final current = replacement.run(() => _loadArtwork(loader, name));
        expect((await retired).name, 'link');
        final icon = await current;
        expect(icon.name, name);
        expect(pendingRequests, 2);
        oldResponse.complete(
          http.Response('<svg><path id="stale"/></svg>', 200),
        );
        await pumpEventQueue();
        final cached = await replacement.run(() => _loadArtwork(loader, name));
        expect(cached, same(icon));
        expect(cached.svg, isNot(contains('stale')));
        expect(pendingRequests, 2);
      },
    );
  }

  test(
    'retirement before queued artwork admission never dispatches SVG',
    () async {
      var requests = 0;
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((request) async {
            requests++;
            return http.Response(_customSvg, 200);
          }),
        ),
        const Duration(seconds: 5),
        4096,
        maxConcurrentPerOrigin: 1,
      );
      addTearDown(transport.close);
      final blocker = Completer<http.Response>();
      final occupied = transport.coordinator.run(
        Uri.parse('https://forum.example'),
        () => blocker.future,
      );
      final loader = SidebarIconLoader(transport, const CoreIconNameDecoder());
      final lifecycle = SiteLifecycle();
      final credentials = await _signedIn(lifecycle);
      final loading = credentials.run(() => _loadArtwork(loader, 'theme-logo'));
      await pumpEventQueue();
      expect(requests, 0);
      lifecycle.invalidate('https://forum.example');
      expect((await loading).name, 'link');
      blocker.complete(http.Response('{}', 200));
      await occupied;
      await pumpEventQueue();
      expect(requests, 0);
      final replacement = await _signedIn(lifecycle);
      expect(
        (await replacement.run(() => _loadArtwork(loader, 'theme-logo'))).name,
        'theme-logo',
      );
      expect(requests, 1);
    },
  );
}
