import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/models/notification_schedule.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/shell/do_not_disturb_dialog.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

void main() {
  testWidgets(
    'custom days and invalid time ranges prevent saving until corrected',
    (tester) async {
      final api = _DndApi();
      await _open(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('notification-schedule-open')),
      );
      await tester.pumpAndSettle();
      await _choose(tester, 'notification-schedule-days', 'Custom days');
      for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        await tester.tap(find.text(day));
        await tester.pumpAndSettle();
      }
      expect(find.text('Choose at least one day.'), findsOneWidget);
      final save = find.byKey(const ValueKey('notification-schedule-save'));
      expect(tester.widget<DButton>(save).onPressed, isNull);
      expect(api.userPreferenceUpdates, isEmpty);
      await tester.tap(find.text('Mon'));
      await tester.pumpAndSettle();
      await _choose(tester, 'notification-schedule-to', '08:00');
      expect(find.text('End time must be after start time.'), findsOneWidget);
      expect(tester.widget<DButton>(save).onPressed, isNull);
      await _choose(tester, 'notification-schedule-to', '18:00');
      await tester.tap(save);
      await tester.pumpAndSettle();
      final fields =
          api.userPreferenceUpdates.single.values['user_notification_schedule']
              as Map<String, Object?>;
      expect(fields['day_0_start_time'], 540);
      expect(fields['day_0_end_time'], 1080);
      for (var day = 1; day < 7; day++) {
        expect(fields['day_${day}_start_time'], -1);
        expect(fields['day_${day}_end_time'], -1);
      }
    },
  );
  testWidgets(
    'schedule saves selected days and times in-app and updates the quick menu',
    (tester) async {
      final api = _DndApi();
      api.userPreferences = UserPreferences(
        username: 'reader',
        timezone: 'Europe/Paris',
        canEdit: true,
        notificationSchedule: NotificationSchedule.initial(),
      );
      final launcher = _watchLauncher(tester);
      await _open(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('notification-schedule-open')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Europe/Paris'), findsOneWidget);
      expect(find.byType(DSwitch), findsNothing);
      expect(find.text('Turn off schedule'), findsNothing);
      expect(
        find.textContaining('Notifications are paused outside'),
        findsNothing,
      );
      await _choose(tester, 'notification-schedule-days', 'Weekdays');
      await _choose(tester, 'notification-schedule-from', '09:30');
      await tester.tap(
        find.byKey(const ValueKey('notification-schedule-save')),
      );
      await tester.pumpAndSettle();
      expect(launcher.urls, isEmpty);
      expect(api.userPreferenceUpdates, hasLength(1));
      expect(api.userPreferenceUpdates.single.values, {
        'user_notification_schedule': {
          'enabled': true,
          'day_0_start_time': 570,
          'day_0_end_time': 1080,
          'day_1_start_time': 570,
          'day_1_end_time': 1080,
          'day_2_start_time': 570,
          'day_2_end_time': 1080,
          'day_3_start_time': 570,
          'day_3_end_time': 1080,
          'day_4_start_time': 570,
          'day_4_end_time': 1080,
          'day_5_start_time': -1,
          'day_5_end_time': -1,
          'day_6_start_time': -1,
          'day_6_end_time': -1,
        },
      });
      expect(find.text('Weekdays · 09:30–18:00'), findsOneWidget);
      expect(find.text('Allow notifications on'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Back discards schedule edits and reopening reads confirmed settings',
    (tester) async {
      final api = _DndApi();
      await _open(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('notification-schedule-open')),
      );
      await tester.pumpAndSettle();
      await _choose(tester, 'notification-schedule-from', '10:00');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(api.userPreferenceUpdates, isEmpty);
      expect(find.text('Not set'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('notification-schedule-open')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DSwitch), findsNothing);
      expect(find.text('Turn off schedule'), findsNothing);
      expect(find.text('Every day'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
    },
  );

  testWidgets(
    'a disabled schedule opens a reset form without ambiguous time placeholders',
    (tester) async {
      final api = _DndApi();
      final original = NotificationSchedule(
        enabled: false,
        days: [
          for (var i = 0; i < 7; i++)
            (start: i < 5 ? 480 + i * 30 : -1, end: i < 5 ? 1020 : -1),
        ],
      );
      api.userPreferences = UserPreferences(
        username: 'reader',
        canEdit: true,
        notificationSchedule: original,
      );
      await _open(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('notification-schedule-open')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Varies by day'), findsNothing);
      expect(find.text('Every day'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('notification-schedule-save')),
      );
      await tester.pumpAndSettle();
      expect(api.userPreferenceUpdates.single.values, {
        'user_notification_schedule': {
          ...NotificationSchedule.initial().wireValues,
          'enabled': true,
        },
      });
    },
  );

  testWidgets('schedule save failures keep the draft for retry', (
    tester,
  ) async {
    final api = _DndApi();
    await _open(tester, api);
    await tester.tap(find.byKey(const ValueKey('notification-schedule-open')));
    await tester.pumpAndSettle();
    api.preferenceFailure = const WriteException(WriteFailure.forbidden);
    await tester.tap(find.byKey(const ValueKey('notification-schedule-save')));
    await tester.pumpAndSettle();
    expect(find.text('Allow notifications on'), findsOneWidget);
    expect(find.byType(DFieldError), findsOneWidget);
    api.preferenceFailure = null;
    await tester.tap(find.byKey(const ValueKey('notification-schedule-save')));
    await tester.pumpAndSettle();
    expect(api.userPreferenceUpdates, hasLength(2));
    expect(find.text('Allow notifications on'), findsNothing);
  });

  testWidgets(
    'cancel schedule shows exact saved hours, retries failures and resets the same editor',
    (tester) async {
      final original = NotificationSchedule(
        enabled: true,
        days: [
          for (var i = 0; i < 7; i++)
            (start: i < 5 ? 480 + i * 30 : -1, end: i < 5 ? 1020 : -1),
        ],
      );
      final api = _DndApi()
        ..userPreferences = UserPreferences(
          username: 'reader',
          canEdit: true,
          notificationSchedule: original,
        );
      final shell = await _open(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('notification-schedule-open')),
      );
      await tester.pumpAndSettle();
      final editor = tester.element(find.byType(DDialogContent));
      expect(find.text('Varies by day'), findsNothing);
      expect(find.text('Save schedule'), findsNothing);
      expect(find.text('Turn off schedule'), findsNothing);
      for (final time in ['08:00', '08:30', '09:00', '09:30', '10:00']) {
        expect(find.text('$time–17:00'), findsOneWidget);
      }
      final action = find.byKey(const ValueKey('notification-schedule-save'));
      expect(
        tester.widget<DButton>(action).variant,
        DButtonVariant.destructive,
      );
      api.preferenceFailure = const WriteException(WriteFailure.forbidden);
      await tester.tap(find.text('Cancel schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel schedule'), findsOneWidget);
      expect(
        shell.preferences.stateFor(_site)?.confirmed?.notificationSchedule,
        original,
      );
      api.preferenceFailure = null;
      await tester.tap(find.text('Cancel schedule'));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(DDialogContent)), same(editor));
      expect(api.userPreferenceUpdates, hasLength(2));
      for (final update in api.userPreferenceUpdates) {
        expect(update.values, {
          'user_notification_schedule': {
            ...original.wireValues,
            'enabled': false,
          },
        });
      }
      expect(find.text('Cancel schedule'), findsNothing);
      expect(find.text('Save schedule'), findsOneWidget);
      expect(tester.widget<DButton>(action).variant, DButtonVariant.primary);
      expect(find.text('Every day'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);
      expect(find.byType(DFieldError), findsNothing);
      await _choose(tester, 'notification-schedule-days', 'Weekdays');
      await _choose(tester, 'notification-schedule-from', '10:00');
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Weekdays · 10:00–18:00'), findsOneWidget);
      final saved =
          api.userPreferenceUpdates.last.values['user_notification_schedule']
              as Map<String, Object?>;
      expect(saved['enabled'], true);
      expect(saved['day_0_start_time'], 600);
      expect(saved['day_5_start_time'], -1);
      expect(find.text('Allow notifications on'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel after a failed first save discards its shared preferences draft',
    (tester) async {
      final api = _DndApi();
      final shell = await _open(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('notification-schedule-open')),
      );
      await tester.pumpAndSettle();
      api.preferenceFailure = const WriteException(WriteFailure.forbidden);
      await tester.tap(
        find.byKey(const ValueKey('notification-schedule-save')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(
        shell.preferences
            .stateFor(_site)
            ?.dirty(PreferenceSection.notificationSchedule),
        isFalse,
      );
      expect(find.text('Not set'), findsOneWidget);
    },
  );

  for (final active in [false, true]) {
    testWidgets(
      'late schedule ${active ? 'cancellations' : 'saves'} cannot update a retired account editor',
      (tester) async {
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final api = _DndApi(preferencesWriteGate: gate)
          ..userPreferences = UserPreferences(
            username: 'reader',
            canEdit: true,
            notificationSchedule: NotificationSchedule.initial().copyWith(
              enabled: active,
            ),
          );
        final shell = await _open(tester, api);
        await tester.tap(
          find.byKey(const ValueKey('notification-schedule-open')),
        );
        await tester.pumpAndSettle();
        final editor = tester.element(find.byType(DDialogContent));
        await tester.tap(
          find.byKey(const ValueKey('notification-schedule-save')),
        );
        await tester.pump();
        expect(api.userPreferenceUpdates, hasLength(1));
        await shell.disconnectCurrentInstance();
        await shell.connectCurrentInstance();
        gate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.element(find.byType(DDialogContent)), same(editor));
        expect(shell.preferences.stateFor(_site), isNull);
        expect(
          tester
              .widget<DButton>(
                find.byKey(const ValueKey('notification-schedule-save')),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (width, scale) in [
    (320.0, 17 / 14),
    (390.0, 17 / 14),
    (320.0, 2.0),
  ]) {
    testWidgets(
      'quick menu and schedule use Native bottom sheets at width $width and text scale $scale',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final api = _DndApi();
        api.userPreferences = UserPreferences(
          username: 'reader',
          canEdit: true,
          notificationSchedule: NotificationSchedule.initial().copyWith(
            enabled: true,
          ),
        );
        final shell = await _loadShell(api);
        await _pump(
          tester,
          shell,
          platform: TargetPlatform.iOS,
          textScale: scale,
        );
        await tester.tap(find.text('Pause'));
        await tester.pumpAndSettle();
        expect(
          find.ancestor(
            of: find.text('30 minutes'),
            matching: find.byType(DSheetContent),
          ),
          findsOneWidget,
        );
        if (scale > 1.5) {
          await tester.drag(
            find.byKey(const ValueKey('sheet-drag-handle')),
            const Offset(0, -450),
          );
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('notification-schedule-open')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('notification-schedule-open')),
        );
        await tester.pumpAndSettle();
        expect(
          find.ancestor(
            of: find.text('Time zone'),
            matching: find.byType(DSheetContent),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .getBottomRight(
                find.byKey(const ValueKey('notification-schedule-save')),
              )
              .dx,
          lessThanOrEqualTo(width),
        );
        expect(
          tester.getBottomRight(find.text('Cancel schedule')).dx,
          lessThanOrEqualTo(width),
        );
        final action = find.byKey(const ValueKey('notification-schedule-save'));
        if (scale > 1.5) {
          await tester.drag(
            find.byKey(const ValueKey('sheet-drag-handle')).last,
            const Offset(0, -450),
          );
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.text('Save schedule'), findsOneWidget);
        expect(find.text('Cancel schedule'), findsNothing);
        expect(
          find.ancestor(
            of: find.text('Time zone'),
            matching: find.byType(DSheetContent),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.text('30 minutes'), findsOneWidget);
        expect(api.userPreferenceUpdates, hasLength(1));
        expect(find.text('Not set'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
  for (final replacement in ['account', 'shell']) {
    for (final action in ['pause', 'schedule']) {
      testWidgets(
        '$action rejects an opening from before $replacement replacement',
        (tester) async {
          final api = _DndApi();
          final launcher = _watchLauncher(tester);
          final shell = await _open(tester, api);
          final dialog = tester.element(find.byType(DDropdownMenuContent));
          final replacementApi = _DndApi();
          if (replacement == 'account') {
            await shell.disconnectCurrentInstance();
            await shell.connectCurrentInstance();
            expect(shell.currentInstance?.isConnected, isTrue);
          } else {
            await _pump(tester, await _loadShell(replacementApi));
          }
          await tester.pumpAndSettle();
          expect(
            tester.element(find.byType(DDropdownMenuContent)),
            same(dialog),
          );

          await tester.tap(
            action == 'pause' ? _oneHour : find.text('Notification schedule'),
          );
          await tester.pumpAndSettle();

          expect(api.writes, isEmpty);
          expect(replacementApi.writes, isEmpty);
          expect(launcher.urls, isEmpty);
          expect(find.byType(DDropdownMenuContent), findsOneWidget);
        },
      );
    }

    for (final failure in [false, true]) {
      testWidgets(
        'late pause ${failure ? 'failure' : 'success'} leaves a retired $replacement dialog untouched',
        (tester) async {
          final api = _DndApi();
          final gate = _writeGate(api);
          final shell = await _open(tester, api);
          final dialog = tester.element(find.byType(DDropdownMenuContent));
          await tester.tap(_oneHour);
          await tester.pump();
          expect(api.writes, [
            (_site, 'key', const DoNotDisturbDuration.minutes(60)),
          ]);
          if (replacement == 'account') {
            await shell.disconnectCurrentInstance();
            await shell.connectCurrentInstance();
          } else {
            await _pump(tester, await _loadShell(_DndApi()));
          }
          if (failure) {
            gate.completeError(const WriteException(WriteFailure.forbidden));
          } else {
            gate.complete();
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(
            tester.element(find.byType(DDropdownMenuContent)),
            same(dialog),
          );
          expect(tester.widget<DDropdownMenuItem>(_oneHour).onPressed, isNull);
          expect(
            find.text(const WriteException(WriteFailure.forbidden).message),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final (label, duration) in const [
    ('30 minutes', DoNotDisturbDuration.minutes(30)),
    ('1 hour', DoNotDisturbDuration.minutes(60)),
    ('2 hours', DoNotDisturbDuration.minutes(120)),
    ('Until tomorrow', DoNotDisturbDuration.untilTomorrow()),
  ]) {
    testWidgets('$label pauses the opening account and closes the dialog', (
      tester,
    ) async {
      final api = _DndApi();
      final shell = await _open(tester, api);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(api.writes, [(_site, 'key', duration)]);
      expect(shell.doNotDisturb.stateFor(_site).until, api.doNotDisturbUntil);
      expect(find.byType(DDropdownMenuContent), findsNothing);
    });
  }

  testWidgets('same-frame pause and schedule callbacks admit one operation', (
    tester,
  ) async {
    final api = _DndApi();
    final gate = _writeGate(api);
    final launcher = _watchLauncher(tester);
    await _open(tester, api);
    final pause = tester.widget<DDropdownMenuItem>(_oneHour).onPressed!;
    final schedule = _scheduleButton(tester).onPressed!;
    pause();
    pause();
    schedule();
    await tester.pump();
    expect(api.writes, [
      (_site, 'key', const DoNotDisturbDuration.minutes(60)),
    ]);
    expect(launcher.urls, isEmpty);
    expect(tester.widget<DDropdownMenuItem>(_oneHour).onPressed, isNull);
    expect(
      find.text('Another notification change is still finishing.'),
      findsNothing,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsNothing);
  });

  testWidgets('schedule opens once and rejects same-frame pause callbacks', (
    tester,
  ) async {
    final api = _DndApi();
    final launcher = _watchLauncher(tester);
    await _open(tester, api);
    final pause = tester.widget<DDropdownMenuItem>(_oneHour).onPressed!;
    final schedule = _scheduleButton(tester).onPressed!;
    schedule();
    schedule();
    pause();
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(launcher.urls, isEmpty);
    expect(find.text('Allow notifications on'), findsOneWidget);
    expect(api.userPreferenceLoads, hasLength(1));
  });

  testWidgets('current pause failure allows retrying another duration', (
    tester,
  ) async {
    final api = _DndApi();
    final gate = _writeGate(api);
    await _open(tester, api);
    await tester.tap(_oneHour);
    await tester.pump();
    gate.completeError(const WriteException(WriteFailure.forbidden));
    await tester.pumpAndSettle();
    expect(
      find.text(const WriteException(WriteFailure.forbidden).message),
      findsOneWidget,
    );
    api.writeGate = null;
    await tester.tap(find.text('2 hours'));
    await tester.pumpAndSettle();
    expect(api.writes, [
      (_site, 'key', const DoNotDisturbDuration.minutes(60)),
      (_site, 'key', const DoNotDisturbDuration.minutes(120)),
    ]);
    expect(find.byType(DDropdownMenuContent), findsNothing);
  });
}

Finder get _oneHour => find.byKey(const ValueKey('do-not-disturb-oneHour'));

DDropdownMenuItem _scheduleButton(WidgetTester tester) =>
    tester.widget<DDropdownMenuItem>(
      find.ancestor(
        of: find.text('Notification schedule'),
        matching: find.byType(DDropdownMenuItem),
      ),
    );

Future<ShellController> _open(WidgetTester tester, FakeDiscourseApi api) async {
  final shell = await _loadShell(api);
  await _pump(tester, shell);
  await tester.tap(find.text('Pause'));
  await tester.pumpAndSettle();
  return shell;
}

({List<String> urls, Completer<bool> result}) _watchLauncher(
  WidgetTester tester,
) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final urls = <String>[];
  final result = Completer<bool>();
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method != 'launch') return true;
    urls.add((call.arguments as Map)['url'] as String);
    return result.future;
  });
  addTearDown(() {
    if (!result.isCompleted) result.complete(true);
    messenger.setMockMethodCallHandler(channel, null);
  });
  return (urls: urls, result: result);
}

Completer<void> _writeGate(_DndApi api) {
  final gate = Completer<void>();
  api.writeGate = gate.future;
  addTearDown(() {
    if (!gate.isCompleted) gate.complete();
  });
  return gate;
}

class _DndApi extends FakeDiscourseApi {
  _DndApi({Completer<void>? preferencesWriteGate})
    : super(
        user: _user,
        feeds: const {'/latest.json': <Topic>[]},
        doNotDisturbUntil: eternalDoNotDisturbUntil,
        userPreferencesWriteGate: preferencesWriteGate,
      );

  Future<void>? writeGate;
  WriteException? preferenceFailure;
  @override
  WriteException? get writeFailure => preferenceFailure;
  final writes = <(String, String, DoNotDisturbDuration)>[];

  @override
  Future<DateTime> enterDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    required DoNotDisturbDuration duration,
    String? clientId,
  }) async {
    writes.add((siteUrl, apiKey, duration));
    await writeGate;
    return doNotDisturbUntil!;
  }
}

Future<void> _choose(WidgetTester tester, String key, String option) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(option).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<ShellController> _loadShell(FakeDiscourseApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  return shell;
}

Future<void> _pump(
  WidgetTester tester,
  ShellController shell, {
  TargetPlatform platform = TargetPlatform.macOS,
  double textScale = 1,
}) => tester.pumpWidget(
  ShellScope(
    controller: shell,
    child: MaterialApp(
      theme: AppTheme.dark.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: DToaster(child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => DButton(
            onPressed: () => showDoNotDisturbDialog(context, siteUrl: _site),
            label: const Text('Pause'),
          ),
        ),
      ),
    ),
  ),
);
