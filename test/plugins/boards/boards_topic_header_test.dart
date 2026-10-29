import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/ui/foundation/control_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/button_surface.dart';
import '../../support/fakes.dart';
import '../../support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';

void main() {
  for (final size in [const Size(390, 844), const Size(1000, 844)]) {
    testWidgets('Boards shares the bookmark/bell pill at ${size.width}', (
      tester,
    ) async {
      const user = DiscourseUser(id: 9, username: 'reader');
      final config = SiteConfig(
        plugins: PluginData.none.withValue(
          boardsSettingsKey,
          const BoardsSettings(enabled: true),
        ),
      );
      await pumpShell(
        tester,
        size,
        instances: [
          instance('meta.discourse.org').copyWith(user: user, config: config),
        ],
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
        api: FakeDiscourseApi(
          user: user,
          siteConfigs: {_site: config},
          feeds: const {
            '/latest.json': [
              Topic(id: 7, title: 'Grouped plugin actions', slug: 'grouped'),
            ],
          },
          topics: {
            7: topicPayload(
              id: 7,
              title: 'Grouped plugin actions',
              posts: const [
                Post(
                  id: 71,
                  postNumber: 1,
                  username: 'reader',
                  cooked: '<p>A topic on two boards.</p>',
                ),
              ],
              plugins: PluginData.none.withValue(
                boardsMembershipKey,
                BoardMemberships.decode([
                  for (var id = 1; id <= 2; id++)
                    {
                      'board_id': id,
                      'board_name': 'Board $id',
                      'cards': [
                        {'card_id': 100 + id, 'column_title': 'Backlog'},
                      ],
                    },
                ]),
              ),
            ),
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('topic-card-7')));
      await tester.pumpAndSettle();

      final boards = find.byKey(const ValueKey('boards-topic-header'));
      final bookmark = find.byKey(
        const ValueKey('topic-header-bookmark-button'),
      );
      final bell = find.byKey(
        const ValueKey('topic-header-notification-button'),
      );
      final group = find.ancestor(
        of: bookmark,
        matching: find.byType(DButtonGroup),
      );
      expect(find.descendant(of: group, matching: boards), findsOneWidget);
      expect(find.descendant(of: group, matching: bell), findsOneWidget);
      final button = tester.widget<DButton>(boards);
      expect(button.variant, DButtonVariant.tool);
      expect(button.hasPopup, isTrue);
      Rect surface(Finder control) => tester.getRect(
        find.descendant(of: control, matching: find.byType(DControlArtwork)),
      );
      expect(surface(boards).height, surface(bookmark).height);
      expect(surface(boards).left, surface(bell).right);
      expect(surface(boards).top, surface(bell).top);
      final artwork = buttonSurface(tester, of: boards);
      expect(artwork.color, Colors.transparent);
      expect(artwork.borderRadius.topLeft, Radius.zero);
      expect(artwork.borderRadius.topRight.x, greaterThan(0));

      await tester.tap(boards);
      await tester.pumpAndSettle();
      expect(find.text('Board 1 · Backlog'), findsOneWidget);
      expect(find.text('Board 2 · Backlog'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}
