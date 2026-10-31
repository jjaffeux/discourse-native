import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _createdRoom = {
  'id': 8,
  'name': 'Planning',
  'slug': 'planning',
  'room_type': 'open',
  'active_participants': <Object>[],
};

void main() {
  for (final drawer in [false, true]) {
    testWidgets(
      'Create a voice room from the mobile Chat ${drawer ? 'drawer' : 'inbox'}',
      (tester) async {
        late FakeDiscourseApi api;
        final shell = await pumpMobileShellFixture(
          tester,
          voice: true,
          onApi: (value) => api = value,
          pluginResponses: const {
            'POST /live/rooms.json': {'room': _createdRoom},
          },
        );
        shell.selectMobilePanel('chat');
        await tester.pumpAndSettle();
        if (drawer) {
          await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
          await tester.pumpAndSettle();
        }
        final newRoom = find.widgetWithText(DButton, 'New voice room');
        await Scrollable.ensureVisible(tester.element(newRoom), alignment: .5);
        await tester.pumpAndSettle();
        expect(newRoom.hitTestable(), findsOneWidget);
        expect(tester.widget<DButton>(newRoom).variant, DButtonVariant.outline);
        await tester.tap(newRoom);
        await tester.pumpAndSettle();
        expect(find.text('Create voice room'), findsOneWidget);
        expect(find.byType(DSheetContent), findsOneWidget);
        expect(find.byType(DDialogContent), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.descendant(
            of: find.byType(DInput).first,
            matching: find.byType(EditableText),
          ),
          '  Planning  ',
        );
        api.pluginResponses['GET /live/rooms.json'] = {
          'rooms': [_createdRoom],
          'can_create_room': true,
        };
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(DButton, 'Create room'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        final creation = api.pluginWrites.single;
        expect(creation.method, 'POST');
        expect(creation.path, '/live/rooms.json');
        expect((creation.body['room']! as Map)['name'], 'Planning');
        expect(
          shell.pluginSession
              .require(voiceControllerService)
              .room(_site, 8)
              ?.name,
          'Planning',
        );
        expect(find.byType(DSheetContent), findsNothing);
        expect(find.text('Planning'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}
