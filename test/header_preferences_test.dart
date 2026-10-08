import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/header_preferences.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

class _Persistence implements ScalarPreferencePersistence<String> {
  final values = <String, String>{};
  Completer<String?>? readGate;
  @override
  Future<String?> read(String key) async =>
      readGate == null ? values[key] : readGate!.future;
  @override
  Future<bool> write(String key, String value) async {
    values[key] = value;
    return true;
  }
}

void main() {
  testWidgets(
    'Native choices update the active scope and persist for the account',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          const DiscourseInstance(
            url: 'https://headers.example',
            title: 'Headers',
            user: DiscourseUser(id: 7, username: 'reader'),
          ),
        ]),
        api: FakeDiscourseApi(
          user: const DiscourseUser(id: 7, username: 'reader'),
        ),
        authenticator: FakeAuthenticator()
          ..keys['https://headers.example'] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      DHeaderTuning? active;
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  active = DHeaderMotionSettings.of(context);
                  return const SingleChildScrollView(
                    child: HeaderTuningPreferences(),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(active, const DHeaderTuning());
      expect(find.byType(DSelect<DHeaderSettle>), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('header-tuning-settle')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stay where left').last);
      await tester.pumpAndSettle();
      expect(active!.settle, DHeaderSettle.stay);
      final restored = HeaderPreferencesController(
        'https://headers.example',
        '7:reader',
      );
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.tuning.settle, DHeaderSettle.stay);
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(child: HeaderTuningPreferences()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('header-tuning-smoothing')),
      );
      expect(
        find.byKey(const ValueKey('header-tuning-smoothing')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'defaults and all tuning fields round trip within the account',
    () async {
      final persistence = _Persistence();
      final controller = HeaderPreferencesController(
        'https://a.example',
        '7:reader',
        persistence: persistence,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.tuning, const DHeaderTuning());
      const tuning = DHeaderTuning(
        settle: DHeaderSettle.halfway,
        point: .7,
        pause: 250,
        slack: 64,
        hold: 800,
        smoothing: 90,
      );
      await controller.set(tuning);
      final restored = HeaderPreferencesController(
        'https://a.example',
        '7:reader',
        persistence: persistence,
      );
      final otherUser = HeaderPreferencesController(
        'https://a.example',
        '8:other',
        persistence: persistence,
      );
      final otherSite = HeaderPreferencesController(
        'https://b.example',
        '7:reader',
        persistence: persistence,
      );
      addTearDown(restored.dispose);
      addTearDown(otherUser.dispose);
      addTearDown(otherSite.dispose);
      await restored.load();
      await otherUser.load();
      await otherSite.load();
      expect(restored.tuning, tuning);
      expect(otherUser.tuning, const DHeaderTuning());
      expect(otherSite.tuning, const DHeaderTuning());
    },
  );
  test('an interaction wins over a late persisted read', () async {
    final persistence = _Persistence()..readGate = Completer();
    final controller = HeaderPreferencesController(
      'https://a.example',
      '7:reader',
      persistence: persistence,
    );
    addTearDown(controller.dispose);
    final loading = controller.load();
    final saving = controller.set(
      const DHeaderTuning(settle: DHeaderSettle.stay),
    );
    persistence.readGate!.complete('{"settle":"halfway","pause":250}');
    await loading;
    await saving;
    expect(controller.tuning.settle, DHeaderSettle.stay);
    expect(controller.tuning.pause, 120);
  });
  test(
    'invalid settings fall back and a retired account cannot publish a read',
    () async {
      expect(
        DHeaderTuning.fromJson(const {
          'pause': -1,
          'point': 4,
          'slack': 'bad',
          'settle': 'unknown',
        }),
        const DHeaderTuning(),
      );
      final persistence = _Persistence()..readGate = Completer();
      final controller = HeaderPreferencesController(
        'https://a.example',
        '7:reader',
        persistence: persistence,
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      final loading = controller.load();
      controller.dispose();
      persistence.readGate!.complete('{"hold":800}');
      await loading;
      expect(notifications, 0);
    },
  );
}
