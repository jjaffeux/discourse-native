import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_row.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_services.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const _site = 'https://meta.example';

void main() {
  final emojiBytes = <String, List<int>>{};
  setUpAll(() async {
    final dir = Platform.environment['POST_REACTION_EMOJI_DIR'];
    if (dir != null) {
      for (final name in ['eyes', '100', 'cry']) {
        emojiBytes[name] = await File('$dir/$name.svg').readAsBytes();
      }
    }
    if (Platform.environment['POST_REACTION_RENDER_DIR'] == null) return;
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final dark in [false, true]) {
    testWidgets(
      'post preset has flat mockup states and exact targets ($dark)',
      (tester) async {
        final theme = (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: TargetPlatform.macOS,
          textTheme: (dark ? AppTheme.dark : AppTheme.light).textTheme.apply(
            fontFamily: 'Lato',
          ),
        );
        var taps = 0;
        final key = GlobalKey();
        Future<void> mount({
          bool selected = false,
          bool enabled = true,
          double scale = 1,
          bool glass = false,
        }) => tester.pumpWidget(
          MaterialApp(
            theme: DMaterialTheme.apply(
              theme,
              glass
                  ? DAppearanceMaterial.liquidGlass
                  : DAppearanceMaterial.standard,
            ),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: _frame(
                      theme,
                      ReactionPills(
                        padding: const EdgeInsets.all(24),
                        spacing: 4,
                        children: [
                          DToggle(
                            density: DToggleDensity.postReaction,
                            variant: DToggleVariant.outline,
                            pressed: selected,
                            enabled: enabled,
                            onPressedChanged: (_) => taps++,
                            icon: const DIcon(DIcons.heart),
                            child: const Text('5'),
                          ),
                          DButton(
                            density: DButtonDensity.postReaction,
                            onPressed: () => taps++,
                            label: const Text('+3'),
                          ),
                          DButton.iconOnly(
                            density: DButtonDensity.postReaction,
                            onPressed: enabled ? () => taps++ : null,
                            tooltip: 'Add reaction',
                            icon: const DIcon(DIcons.faceSmile),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await mount();
        final toggle = find.byType(DToggle);
        final artwork = find.descendant(
          of: toggle,
          matching: find.byType(AnimatedContainer),
        );
        BoxDecoration decoration() =>
            tester.widget<AnimatedContainer>(artwork).decoration!
                as BoxDecoration;
        final tokens = DTokens.of(tester.element(toggle));
        expect(decoration().color, tokens.foreground.withValues(alpha: .05));
        expect(decoration().borderRadius, BorderRadius.circular(999));
        expect(decoration().border!.top.color, Colors.transparent);
        expect(
          find.descendant(of: toggle, matching: find.byType(DMaterialSurface)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(DButton),
            matching: find.byType(DMaterialSurface),
          ),
          findsNothing,
        );
        expect(tester.getSize(toggle).height, 30);
        expect(
          tester.getSize(find.byTooltip('Add reaction')),
          const Size.square(30),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text('5'), matching: find.byType(RichText)),
        );
        expect(paragraph.text.style!.fontSize, 12.5);
        expect(paragraph.text.style!.fontWeight, FontWeight.w500);
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(toggle));
        await tester.pump();
        expect(decoration().color, tokens.foreground.withValues(alpha: .08));
        await mouse.removePointer();
        await mount(selected: true);
        expect(decoration().color, tokens.primary.withValues(alpha: .24));
        await tester.pumpAndSettle();
        await _capture(tester, key, 'preset-${dark ? 'dark' : 'light'}');
        final rect = tester.getRect(toggle);
        await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
        await tester.pump();
        expect(taps, 1);
        await tester.tapAt(Offset(rect.right + 2, rect.center.dy));
        await tester.pump();
        expect(
          taps,
          1,
          reason: 'the gap between chips must not activate a control',
        );
        await mount(selected: true, enabled: false);
        expect(decoration().color, tokens.primary.withValues(alpha: .24));
        await tester.tap(toggle);
        await tester.pump();
        expect(taps, 1);
        await mount(glass: true);
        expect(decoration().color, tokens.foreground.withValues(alpha: .05));
        expect(
          find.descendant(
            of: find.byType(DButton),
            matching: find.byType(DMaterialSurface),
          ),
          findsNothing,
        );
        await mount(scale: 2);
        expect(tester.getSize(toggle).height, greaterThan(30));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'post row ranks three pills, retains mine and opens overflow ($dark)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 600);
        addTearDown(tester.view.reset);
        installTestMediaPipeline(
          client: MockClient((request) async {
            final name = request.url.pathSegments.last.split('.').first;
            final bytes = emojiBytes[name];
            return bytes == null
                ? http.Response('', 404)
                : http.Response.bytes(
                    bytes,
                    200,
                    headers: {'content-type': 'image/svg+xml'},
                  );
          }),
        );
        final shell = ShellController(
          plugins: installedPlugins,
          instanceStore: FakeInstanceStore([
            instance(
              'meta.example',
            ).copyWith(user: const DiscourseUser(username: 'reader')),
          ]),
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator()..keys[_site] = 'key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updater: FakeUpdater(),
          updateStore: FakeUpdateStore(),
        );
        await shell.load();
        addTearDown(shell.dispose);
        Post post({String? mine}) => Post.fromJson(
          {
            'id': 1,
            'post_number': 1,
            'username': 'author',
            'cooked': '<p>Post</p>',
            'actions_summary': const [
              {'id': Post.likeActionId, 'can_act': true},
            ],
            'reactions': const [
              {'id': 'cry', 'count': 5},
              {'id': 'eyes', 'count': 8},
              {'id': '100', 'count': 7},
              {'id': 'heart', 'count': 1},
              {'id': 'clap', 'count': 2},
              {'id': 'rocket', 'count': 3},
            ],
            if (mine != null)
              'current_user_reaction': {'id': mine, 'can_undo': true},
          },
          _site,
          extensions: pluginRegistry,
        );
        final key = GlobalKey();
        Future<void> mount({String? mine}) => tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
                platform: TargetPlatform.macOS,
                textTheme: (dark ? AppTheme.dark : AppTheme.light).textTheme
                    .apply(fontFamily: 'Lato'),
              ),
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: _frame(
                      dark ? AppTheme.dark : AppTheme.light,
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: ReactionsRow(
                          siteUrl: _site,
                          post: post(mine: mine),
                          controller: shell.pluginSession.require(
                            reactionsControllerService,
                          ),
                          emoji: shell.pluginSession.require(
                            reactionsEmojiHostService,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await mount();
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<ReactionPill>(find.byType(ReactionPill))
              .map((pill) => pill.reaction),
          ['eyes', '100', 'cry'],
        );
        expect(find.text('+3'), findsOneWidget);
        expect(
          tester
              .widgetList<SiteEmojiImage>(find.byType(SiteEmojiImage))
              .every((emoji) => emoji.size == 14),
          isTrue,
        );
        await _capture(tester, key, 'row-${dark ? 'dark' : 'light'}');
        await mount(mine: 'heart');
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<ReactionPill>(find.byType(ReactionPill))
              .map((pill) => pill.reaction),
          ['eyes', '100', 'heart'],
        );
        expect(
          tester
              .widget<ReactionPill>(
                find.byKey(const ValueKey('post-reaction-1-heart')),
              )
              .selected,
          isTrue,
        );
        await tester.tap(
          find.byKey(const ValueKey('post-reaction-overflow-1')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsOneWidget);
        for (final id in ['eyes', '100', 'cry', 'heart', 'clap', 'rocket']) {
          expect(
            find.byKey(ValueKey('post-reaction-filter-$id')),
            findsOneWidget,
          );
        }
        await tester.tap(
          find.byKey(const ValueKey('post-reaction-filter-cry')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DToggle>(
                find.byKey(const ValueKey('post-reaction-filter-cry')),
              )
              .pressed,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['POST_REACTION_RENDER_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _frame(ThemeData theme, Widget child) => ColoredBox(
  color: theme.scaffoldBackgroundColor,
  child: SizedBox(width: 380, height: 100, child: child),
);
