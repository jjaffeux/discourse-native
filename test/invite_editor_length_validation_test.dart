import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/invites_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/invite_editor.dart';
import 'package:discourse_native/src/shell/invite_list.dart';
import 'package:discourse_native/src/shell/invites_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/invite_fixtures.dart';

void main() {
  for (final (description, message, hideMessage, hideEmail, invalid) in [
    ('e\u0301' * 60, '', false, false, 'Description (optional)'),
    ('', 'a' * 1001, false, false, 'Custom message (optional)'),
    ('', 'e\u0301' * 501, false, false, 'Custom message (optional)'),
    ('', 'a' * 1001, true, false, null),
    ('', 'a' * 1001, true, true, null),
    ('e\u0301' * 50, 'e\u0301' * 500, false, false, null),
    ('𐐀' * 100, '𐐀' * 1000, false, false, null),
    ('  Team  ', '  Welcome  ', false, false, null),
    ('Team', '  ${'𐐀' * 1000}  ', false, false, null),
  ]) {
    testWidgets(
      'invite description ${description.runes.length} message ${message.runes.length}, hidden $hideMessage/$hideEmail, validates $invalid',
      (tester) async {
        final requests = <http.Request>[];
        final api = DiscourseApi(
          client: MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response(jsonEncode(invitePage([])), 200);
            }
            requests.add(request);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final description = body['description'] as String? ?? '';
            final message = body['custom_message'] as String? ?? '';
            final field = description.runes.length > 100
                ? 'Description'
                : message.runes.length > 1000
                ? 'Custom message'
                : null;
            if (field != null) {
              return http.Response(
                jsonEncode({
                  'errors': ['$field is too long'],
                }),
                422,
              );
            }
            return http.Response(jsonEncode(inviteRow(99)), 200);
          }),
        );
        addTearDown(api.close);
        final controller = InvitesController(
          api: InvitesApi(api),
          credentials: InviteCredentials(),
          instance: inviteSite,
          lifecycle: SiteLifecycle(),
        );
        addTearDown(controller.dispose);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await controller.load();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
            home: Scaffold(
              body: SingleChildScrollView(
                child: InviteList(controller: controller, onManage: () {}),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _tap(tester, find.text('Create invite'));
        expect(find.byType(InviteEditor), findsOneWidget);
        await tester.enterText(_input('Description (optional)'), description);
        expect(
          tester
              .widget<DInput>(_input('Description (optional)'))
              .controller!
              .text,
          description,
        );
        if (message.isNotEmpty) {
          await tester.enterText(_input('Email (optional)'), 'sam@example.com');
          await tester.pumpAndSettle();
          await _tap(tester, find.byType(DCheckbox));
          await tester.enterText(find.byType(DTextarea), message);
          if (hideMessage) {
            await _tap(tester, find.byType(DCheckbox));
            expect(find.byType(DTextarea), findsNothing);
            await _tap(tester, find.byType(DCheckbox));
            expect(
              tester.widget<DTextarea>(find.byType(DTextarea)).controller!.text,
              message,
            );
            await _tap(tester, find.byType(DCheckbox));
          }
          if (hideEmail) {
            await tester.enterText(_input('Email (optional)'), '');
            await tester.pumpAndSettle();
          }
        }
        await _tap(
          tester,
          find.text(
            message.isNotEmpty && !hideMessage
                ? 'Create and send email'
                : 'Create invite link',
          ),
        );
        if (invalid != null) {
          expect(requests, isEmpty);
          final field = invalid == 'Custom message (optional)'
              ? find.byType(DTextarea)
              : _input(invalid);
          final state = tester.state<FormFieldState<String>>(field);
          expect(state.hasError, isTrue);
          expect(
            state.errorText,
            contains(invalid.startsWith('Description') ? '100' : '1000'),
          );
          expect(find.byType(InviteEditor), findsOneWidget);
          // A corrected value submits through the production API.
          await tester.enterText(field, 'Corrected');
          await _tap(
            tester,
            find.text(
              message.isNotEmpty
                  ? 'Create and send email'
                  : 'Create invite link',
            ),
          );
        }
        final request = requests.single;
        expect(request.method, 'POST');
        expect(request.url.path, '/community/invites.json');
        expect(request.headers['User-Api-Key'], 'invite-key');
        expect(request.headers['User-Api-Client-Id'], 'invite-client');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(
          body['description'],
          invalid == 'Description (optional)'
              ? 'Corrected'
              : description.trim(),
        );
        if (message.isNotEmpty && !hideMessage) {
          expect(
            body['custom_message'],
            invalid == 'Custom message (optional)'
                ? 'Corrected'
                : message.trim(),
          );
          expect(body['send_email'], isTrue);
          expect(find.text('Invitation email sent.'), findsWidgets);
        } else {
          expect(
            body['custom_message'],
            hideEmail ? isNull : anyOf(isNull, ''),
          );
          expect(body['skip_email'], isTrue);
          expect(find.text('Invite link created.'), findsWidgets);
        }
        expect(controller.actionError, isNull);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }
}

Finder _input(String label) => find.byWidgetPredicate(
  (widget) => widget is DInput && widget.labelText == label,
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
