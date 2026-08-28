import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/site_plugin.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _toggleKey = ValueKey('user-menu-hide-presence');
const _user = DiscourseUser(id: 7, username: 'reader', hidePresence: false);

void main() {
  testWidgets(
    'is optimistic, non-placeholder, and accessible through failure',
    (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final api = FakeDiscourseApi(
        user: _user,
        presenceGate: gate,
        writeFailure: const WriteException(WriteFailure.unreachable),
        feeds: const {'/latest.json': <Topic>[]},
      );
      final shell = await _controller(api: api, user: _user);
      addTearDown(shell.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await _pumpProfile(tester, shell);

        final toggle = find.byKey(_toggleKey);
        expect(toggle, findsOneWidget);
        expect(tester.getSize(toggle).height, greaterThanOrEqualTo(44));
        final online = tester.widget<Text>(find.text('Online'));
        expect(
          online.style?.color,
          isNot(
            Theme.of(tester.element(find.text('Online'))).shell.placeholder,
          ),
        );
        expect(
          tester.getSemantics(toggle),
          isSemantics(
            label: 'Online',
            hint: 'Toggle presence features',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasToggledState: true,
            isToggled: true,
            hasTapAction: true,
          ),
        );

        await tester.tap(toggle);
        await tester.pump();

        expect(find.text('Offline'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          tester.getSemantics(toggle),
          isSemantics(
            label: 'Offline',
            value: 'Saving',
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hasToggledState: true,
            isToggled: false,
            isLiveRegion: true,
          ),
        );

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Online'), findsOneWidget);
        final error = find.bySemanticsLabel(
          "Couldn't update presence. Check the connection and try again.",
        );
        expect(error, findsOneWidget);
        expect(
          tester.getSemantics(error),
          isSemantics(
            label:
                "Couldn't update presence. Check the connection and try again.",
            isLiveRegion: true,
          ),
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('names loading state and enables the live server value', (
    tester,
  ) async {
    final api = _GatedCurrentUserApi();
    addTearDown(() {
      if (!api.response.isCompleted) api.response.complete(_user);
    });
    final shell = await _controller(
      api: api,
      user: const DiscourseUser(id: 7, username: 'reader'),
    );
    addTearDown(shell.dispose);
    await api.started.future;
    final semantics = tester.ensureSemantics();
    try {
      await _pumpProfile(tester, shell);

      final toggle = find.byKey(_toggleKey);
      expect(find.text('Loading presence…'), findsOneWidget);
      expect(
        tester.getSemantics(toggle),
        isSemantics(
          label: 'Presence',
          value: 'Loading',
          hint: 'Toggle presence features',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          isLiveRegion: true,
        ),
      );

      api.response.complete(_user);
      await tester.pumpAndSettle();

      expect(find.text('Online'), findsOneWidget);
      expect(
        tester.getSemantics(toggle),
        isSemantics(
          label: 'Online',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });
}

final class _GatedCurrentUserApi extends FakeDiscourseApi {
  _GatedCurrentUserApi() : super(feeds: const {'/latest.json': <Topic>[]});

  final Completer<void> started = Completer<void>();
  final Completer<DiscourseUser> response = Completer<DiscourseUser>();

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}

Future<ShellController> _controller({
  required FakeDiscourseApi api,
  required DiscourseUser user,
}) async {
  final auth = FakeAuthenticator()..keys[_siteUrl] = 'key';
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator: auth,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  return shell;
}

Future<void> _pumpProfile(WidgetTester tester, ShellController shell) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: ShellScope(
          controller: shell,
          child: const UserMenuPanel(onDismiss: _ignore),
        ),
      ),
    ),
  );
  await tester.tap(find.byTooltip('Profile'));
  await tester.pump();
}

void _ignore() {}
