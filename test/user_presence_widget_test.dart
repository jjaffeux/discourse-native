import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
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
        expect(tester.widget(toggle), isA<DToggle>());
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
        expect(tester.widget<DToggle>(toggle).pressed, isTrue);

        await tester.tap(toggle);
        await tester.pump();

        expect(find.text('Offline'), findsOneWidget);
        expect(find.byType(DSpinner), findsNothing);
        expect(
          tester
              .widget<DIcon>(
                find.descendant(of: toggle, matching: find.byType(DIcon)),
              )
              .icon,
          DIcons.toggleOff,
        );
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
        expect(tester.widget<DToggle>(toggle).enabled, isFalse);
        expect(tester.widget<DToggle>(toggle).pressed, isFalse);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Online'), findsOneWidget);
        expect(tester.widget<DToggle>(toggle).pressed, isTrue);
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

  for (final statusMenu in [false, true]) {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
      for (final initialHidden in [false, true]) {
        testWidgets(
          '${statusMenu ? 'status' : 'profile'} menu changes from ${initialHidden ? 'offline' : 'online'} immediately and disables while saving on $platform',
          (tester) async {
            final gate = Completer<void>();
            addTearDown(() {
              if (!gate.isCompleted) gate.complete();
            });
            final user = _user.withHidePresence(initialHidden);
            final api = FakeDiscourseApi(
              user: user,
              presenceGate: gate,
              feeds: const {'/latest.json': <Topic>[]},
            );
            final shell = await _controller(api: api, user: user);
            addTearDown(shell.dispose);
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light.copyWith(platform: platform),
                builder: (context, child) =>
                    ShellScope(controller: shell, child: child!),
                home: Scaffold(
                  body: statusMenu
                      ? const UserPresenceMenu(siteUrl: _siteUrl)
                      : const UserMenuButton(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(
                statusMenu
                    ? const ValueKey('user-presence-menu')
                    : UserMenuButton.avatarKey,
              ),
            );
            await tester.pumpAndSettle();

            final toggle = find.byKey(_toggleKey);
            DDropdownMenuCheckboxItem control() => tester.widget(toggle);
            expect(control().checked, !initialHidden);
            await tester.tap(toggle);
            await tester.pump();

            expect(gate.isCompleted, isFalse);
            expect(control().checked, initialHidden);
            expect(control().onChanged, isNull);
            expect(
              (control().leading! as DIcon).icon,
              initialHidden ? DIcons.toggleOn : DIcons.toggleOff,
            );

            await tester.pumpAndSettle();

            await tester.tap(toggle);
            await tester.pump();
            expect(control().checked, initialHidden);
            expect(
              (control().leading! as DIcon).icon,
              initialHidden ? DIcons.toggleOn : DIcons.toggleOff,
            );
            expect(api.presencePreferencesUpdated, hasLength(1));

            gate.complete();
            await tester.pumpAndSettle();
            expect(control().checked, initialHidden);
            expect(control().onChanged, isNotNull);
            expect(shell.currentInstance?.user?.hidePresence, !initialHidden);
            expect(
              api.presencePreferencesUpdated.map((write) => write.hidePresence),
              [!initialHidden],
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

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
      expect(find.text('Loading presence…'), findsNothing);
      expect(find.byType(DSkeleton), findsNWidgets(2));
      expect(tester.widget(toggle), isA<DSkeletonRegion>());
      expect(
        tester.getSemantics(toggle),
        isSemantics(label: 'Loading presence…', isLiveRegion: true),
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

  testWidgets('presence dropdown uses a skeleton until its value arrives', (
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
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        builder: (context, child) =>
            ShellScope(controller: shell, child: child!),
        home: const Scaffold(body: UserPresenceMenu(siteUrl: _siteUrl)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('user-presence-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Loading presence…'), findsNothing);
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expect(tester.widget(find.byKey(_toggleKey)), isA<DSkeletonRegion>());
    await tester.tap(find.byKey(_toggleKey), warnIfMissed: false);
    expect(api.presencePreferencesUpdated, isEmpty);

    api.response.complete(_user);
    await tester.pumpAndSettle();
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(find.text('Online'), findsOneWidget);
    expect(
      tester
          .widget<DDropdownMenuCheckboxItem>(find.byKey(_toggleKey))
          .onChanged,
      isNotNull,
    );
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
          child: const UserMenuPanel(
            onDismiss: _ignore,
            view: UserMenuView.profile,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _ignore() {}
