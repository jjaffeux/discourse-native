import 'dart:async';

import 'package:discourse_native/discourse_ui.dart' show DSpinner;
import 'package:discourse_native/src/data/invites_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/invite.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/invite_editor.dart';
import 'package:discourse_native/src/shell/invite_list.dart';
import 'package:discourse_native/src/shell/invites_controller.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/invite_fixtures.dart';

void main() {
  late InviteTransport transport;
  late InvitesController controller;
  String? clipboard;

  setUp(() {
    transport = InviteTransport();
    controller = InvitesController(
      api: InvitesApi(transport),
      credentials: InviteCredentials(),
      instance: inviteSite,
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);
    clipboard = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  });

  Future<void> pumpList(
    WidgetTester tester, {
    double width = 320,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Center(
              child: SizedBox(
                width: width,
                height: 410,
                child: SingleChildScrollView(
                  child: InviteList(controller: controller, onManage: () {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  test('the invite tab follows the current user permission', () {
    expect(
      userMenuSections(null).where((section) => section.isInvites),
      isEmpty,
    );
    expect(
      userMenuSections(
        null,
        user: const DiscourseUser(id: 1, username: 'alice'),
      ).where((section) => section.isInvites),
      isEmpty,
    );
    expect(
      userMenuSections(
        null,
        user: inviteSite.user,
      ).singleWhere((section) => section.isInvites).isPlaceholder,
      isFalse,
    );
  });

  testWidgets('shows loading, retry and the real empty state', (tester) async {
    final gate = Completer<Map<String, dynamic>>();
    transport.onGet = (_) => gate.future;
    final loading = controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: InviteList(controller: controller, onManage: () {}),
          ),
        ),
      ),
    );
    expect(find.byType(DSpinner), findsOneWidget);
    expect(find.text('No pending invites.'), findsNothing);
    gate.completeError(StateError('offline'));
    await loading;
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't load invites. Please try again."),
      findsOneWidget,
    );
    transport.onGet = (_) => invitePage([]);
    await tapText(tester, 'Retry');
    expect(find.text('No pending invites.'), findsOneWidget);
    expect(find.text('Create invite'), findsOneWidget);
  });

  testWidgets('filters redeemed users and debounces email or username search', (
    tester,
  ) async {
    transport.onGet = (request) =>
        Uri.parse(request.path).queryParameters['filter'] == 'redeemed'
        ? invitePage([
            {
              'id': 1,
              'user': {'id': 4, 'username': 'sam'},
              'invite_source': 'email',
            },
          ], redeemed: 1)
        : invitePage([inviteRow(1)], redeemed: 1);
    await controller.load();
    await pumpList(tester);
    await tester.tap(find.byType(DropdownButtonFormField<InviteFilter>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redeemed (1)').last);
    await tester.pumpAndSettle();
    expect(find.text('sam'), findsOneWidget);
    expect(find.text('Invited via email'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
    await tester.enterText(field('Search invites'), 'sa');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(field('Search invites'), 'sam');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      transport.requests.map(
        (request) => Uri.parse(request.path).queryParameters,
      ),
      [
        {'filter': 'pending', 'offset': '0'},
        {'filter': 'redeemed', 'offset': '0'},
        {'filter': 'redeemed', 'offset': '0', 'search': 'sam'},
      ],
    );
  });

  testWidgets('copies an invite and confirms removal before writing', (
    tester,
  ) async {
    transport.onGet = (_) => invitePage([inviteRow(1)]);
    await controller.load();
    await pumpList(tester);
    await tapText(tester, 'Copy link');
    expect(clipboard, '${inviteSite.url}/invites/key-1');
    expect(find.text('Copied!'), findsOneWidget);
    await tapText(tester, 'Remove');
    expect(
      transport.requests.where((request) => request.method != 'GET'),
      isEmpty,
    );
    transport.onGet = (_) => invitePage([]);
    await tapText(tester, 'Confirm removal');
    expect(find.text('No pending invites.'), findsOneWidget);
    expect(find.text('Invite removed.'), findsOneWidget);
    expect(
      transport.requests.map(
        (request) => (request.method, Uri.parse(request.path).path),
      ),
      [
        ('GET', '/u/alice/invited.json'),
        ('DELETE', '/invites.json'),
        ('GET', '/u/alice/invited.json'),
      ],
    );
  });

  testWidgets(
    'creates and copies a link within a narrow panel with large text',
    (tester) async {
      await controller.load();
      await pumpList(tester, width: 280, textScale: 1.5);
      await tapText(tester, 'Create invite');
      expect(find.byType(InviteEditor), findsOneWidget);
      await tester.enterText(
        field('Description (optional)'),
        'Community meetup',
      );
      await tapText(tester, 'Create invite link');
      expect(find.text('Invite link created.'), findsOneWidget);
      await tapText(tester, 'Copy link');
      expect(clipboard, '${inviteSite.url}/invites/key-99');
      final write = transport.requests.singleWhere(
        (request) => request.method == 'POST',
      );
      expect(write.body!['description'], 'Community meetup');
      expect(write.body!['max_redemptions_allowed'], 10);
      expect(write.body!['skip_email'], isTrue);
      expect(write.body!.containsKey('email'), isFalse);
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Back to invites');
      expect(find.byType(InviteEditor), findsNothing);
    },
  );

  testWidgets('validates email and requires choosing to send the invitation', (
    tester,
  ) async {
    await controller.load();
    await pumpList(tester);
    await tapText(tester, 'Create invite');
    await tester.enterText(field('Email (optional)'), 'invalid');
    await tapText(tester, 'Create invite link');
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(
      transport.requests.where((request) => request.method == 'POST'),
      isEmpty,
    );
    await tester.enterText(field('Email (optional)'), 'sam@example.com');
    await tapText(tester, 'Send invitation email');
    await tester.enterText(
      field('Custom message (optional)'),
      'Welcome aboard',
    );
    await tapText(tester, 'Create and send email');
    expect(find.text('Invitation email sent.'), findsOneWidget);
    final body = transport.requests
        .singleWhere((request) => request.method == 'POST')
        .body!;
    expect(body['email'], 'sam@example.com');
    expect(body['custom_message'], 'Welcome aboard');
    expect(body['max_redemptions_allowed'], 1);
    expect(body['send_email'], isTrue);
    expect(body.containsKey('skip_email'), isFalse);
  });

  testWidgets(
    'withdraws sending and removal controls when permissions disallow them',
    (tester) async {
      final restricted = InvitesController(
        api: InvitesApi(transport),
        credentials: InviteCredentials(),
        instance: inviteSite.copyWith(
          config: const SiteConfig(invites: InviteSettings(allowEmail: false)),
        ),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(restricted.dispose);
      transport.onGet = (_) => invitePage([
        inviteRow(1, email: 'sam@example.com', canDelete: false),
      ]);
      await restricted.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: InviteList(controller: restricted, onManage: () {}),
            ),
          ),
        ),
      );
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Resend'), findsNothing);
      await tapText(tester, 'Create invite');
      await tester.enterText(field('Email (optional)'), 'sam@example.com');
      await tester.pump();
      expect(find.text('Send invitation email'), findsNothing);
      expect(find.text('Create invite link'), findsOneWidget);
    },
  );
}
