import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/shell/emoji_picker.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/user_status_editor.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/timezone.dart' as tz;

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

/// UTC+14 all year, so no CI or developer device shares its wall time.
const _zone = 'Pacific/Kiritimati';

const _user = DiscourseUser(
  id: 7,
  username: 'reader',
  status: UserStatus(description: 'Working', emoji: 'house'),
);

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'mobile inset sheet keeps its actions above the keyboard (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        final api = await _open(
          tester,
          platform: TargetPlatform.iOS,
          dark: dark,
        );
        expect(find.byType(DDialogContent), findsNothing);
        expect(find.byType(DInput), findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
        final bounds = tester.getRect(find.byType(DSheetContent));
        expect(bounds.left, greaterThan(0));
        expect(bounds.right, lessThan(390));
        expect(bounds.top, greaterThan(0));
        expect(bounds.bottom, lessThan(844));
        final footer = tester.getRect(find.byType(DSheetFooter));
        expect(footer.bottom, closeTo(bounds.bottom, 1));
        await tester.enterText(find.byType(TextField), 'On holiday');
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        final keyboardFooter = tester.getRect(find.byType(DSheetFooter));
        expect(keyboardFooter.bottom, lessThanOrEqualTo(524));
        expect(find.text('Save').hitTestable(), findsOneWidget);
        expect(find.text('Clear status').hitTestable(), findsOneWidget);
        final closePosition = tester.getCenter(find.byTooltip('Close'));
        await tester.drag(find.byType(DSheetBody), const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(tester.getCenter(find.byTooltip('Close')), closePosition);
        expect(tester.getRect(find.byType(DSheetFooter)), keyboardFooter);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsNothing);
        expect(api.userStatusesSet, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('new status remains usable on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.reset);
    final api = await _open(
      tester,
      platform: TargetPlatform.android,
      hasStatus: false,
      textScale: 1.5,
    );
    expect(find.text('Clear status'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a status description.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ready');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(find.text('Save').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.userStatusesSet.single.description, 'Ready');
    expect(find.byType(DSheetContent), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile expiry and emoji pickers return to the status sheet', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final api = _StatusApi();
    await _open(tester, api: api, platform: TargetPlatform.iOS);
    await _select(tester, 'Custom date and time');
    expect(find.byType(DCalendar), findsOneWidget);
    expect(find.byType(DTimeInput), findsOneWidget);
    expect(find.text('Apply').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('Never').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Choose status emoji'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('emoji-picker-cell-default-0-smile')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.userStatusesSet.single.emoji, 'smile');
    expect(tester.takeException(), isNull);
  });

  for (final (width, platform, scale) in [
    (390.0, TargetPlatform.iOS, 1.0),
    (320.0, TargetPlatform.android, 1.5),
  ]) {
    testWidgets('custom expiry calendar fills the mobile body at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.reset);
      await _open(tester, platform: platform, textScale: scale);
      await _select(tester, 'Custom date and time');

      final calendarFinder = find.byType(DCalendar);
      final calendar = tester.widget<DCalendar>(calendarFinder);
      final bounds = tester.getRect(calendarFinder);
      const padding = EdgeInsets.all(8);
      final firstWeek = find.descendant(
        of: calendarFinder,
        matching: find.byType(DCalendarDayButton),
      );
      final firstDay = tester.getRect(firstWeek.at(0));
      final lastDay = tester.getRect(firstWeek.at(6));
      expect(firstDay.left, closeTo(bounds.left + padding.left, .01));
      expect(lastDay.right, closeTo(bounds.right - padding.right, .01));
      expect(
        firstDay.width,
        closeTo((bounds.width - padding.horizontal) / 7, .01),
      );
      final timeBounds = tester.getRect(find.byType(DTimeInput));
      expect(bounds.left, timeBounds.left);
      expect(bounds.right, timeBounds.right);

      final nextDate = (calendar.selection! as DCalendarSingleSelection).date!
          .addDays(1);
      final nextDay = find.byWidgetPredicate(
        (widget) =>
            widget is DCalendarDayButton && widget.details.date == nextDate,
      );
      await tester.tap(nextDay);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DCalendar>(calendarFinder).selection,
        DCalendarSingleSelection(nextDate),
      );
      expect(find.text('Apply').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mobile time wheels save the account-local custom expiry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final api = await _open(
      tester,
      platform: TargetPlatform.iOS,
      timezone: _zone,
    );
    await _select(tester, 'Custom date and time');
    final date =
        (tester.widget<DCalendar>(find.byType(DCalendar)).selection!
                as DCalendarSingleSelection)
            .date!;
    await tester.tap(find.byType(DTimeInput));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    tester
        .widget<CupertinoTimerPicker>(find.byType(CupertinoTimerPicker))
        .onTimerDurationChanged(const Duration(hours: 12, minutes: 34));
    await tester.tap(find.text('Apply').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('12:34'), findsOneWidget);
    expect(find.byType(CupertinoTimerPicker), findsNothing);
    await tester.tap(find.text('Apply').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      api.userStatusesSet.single.endsAt,
      DateTime.utc(date.year, date.month, date.day, 12 - 14, 34),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid custom time cannot apply a stale value', (tester) async {
    await _open(tester);
    await _select(tester, 'Custom date and time');
    final timeField = find.descendant(
      of: find.byType(DTimeInput),
      matching: find.byType(TextField),
    );
    await tester.enterText(timeField, '25:99');
    await tester.pumpAndSettle();
    expect(_button(tester, 'Apply').onPressed, isNull);
    await tester.enterText(timeField, '12:30');
    await tester.pumpAndSettle();
    expect(_button(tester, 'Apply').onPressed, isNotNull);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Until '), findsOneWidget);
  });

  for (final (width, platform) in [
    (390.0, TargetPlatform.iOS),
    (1000.0, TargetPlatform.macOS),
  ]) {
    testWidgets('status editor saves 51 emoji through HTTP at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final sent = <http.Request>[];
      final writer = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response('', 200);
        }),
      );
      addTearDown(writer.close);
      final api = _HttpStatusApi(writer);
      await _open(tester, api: api, platform: platform);
      final description = '🧵' * 51;
      await tester.enterText(find.byType(TextField), description);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        description,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(sent, hasLength(1));
      expect(sent.single.method, 'PUT');
      expect(sent.single.url.toString(), '$_site/user-status.json');
      expect(sent.single.headers['User-Api-Key'], 'key');
      expect(jsonDecode(sent.single.body), {
        'description': description,
        'emoji': 'house',
      });
      expect(find.byKey(const ValueKey('user-status-editor')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in ['Save', 'Clear status']) {
    testWidgets(
      '$action rejects a replaced shell while the dialog stays open',
      (tester) async {
        final api = await _open(tester);
        final dialog = tester.element(
          find.byKey(const ValueKey('user-status-editor')),
        );
        final replacementApi = _StatusApi();
        await _pump(tester, await _loadShell(replacementApi));
        expect(
          tester.element(find.byKey(const ValueKey('user-status-editor'))),
          same(dialog),
        );

        await tester.tap(find.text(action));
        await tester.pumpAndSettle();

        expect(api.userStatusesSet, isEmpty);
        expect(api.userStatusesCleared, isEmpty);
        expect(replacementApi.writes, isEmpty);
        expect(
          find.byKey(const ValueKey('user-status-editor')),
          findsOneWidget,
        );
      },
    );

    testWidgets('$action rejects an opening from before account reconnect', (
      tester,
    ) async {
      final api = await _open(tester);
      final dialog = tester.element(
        find.byKey(const ValueKey('user-status-editor')),
      );
      final shell = ShellScope.read(dialog);
      await shell.disconnectCurrentInstance();
      await shell.connectCurrentInstance();
      await tester.pumpAndSettle();
      expect(shell.currentInstance?.isConnected, isTrue);
      expect(
        tester.element(find.byKey(const ValueKey('user-status-editor'))),
        same(dialog),
      );

      await tester.tap(find.text(action));
      await tester.pumpAndSettle();

      expect(api.userStatusesSet, isEmpty);
      expect(api.userStatusesCleared, isEmpty);
      expect(api.doNotDisturbDurations, isEmpty);
      expect(find.byKey(const ValueKey('user-status-editor')), findsOneWidget);
    });

    for (final replacement in ['account', 'shell']) {
      for (final failure in [false, true]) {
        testWidgets(
          '$action late ${failure ? 'failure' : 'success'} leaves a retired $replacement dialog untouched',
          (tester) async {
            final api = _StatusApi();
            final gate = _writeGate(api);
            await _open(tester, api: api);
            final dialog = tester.element(
              find.byKey(const ValueKey('user-status-editor')),
            );
            final shell = ShellScope.read(dialog);
            await tester.tap(find.text(action));
            await tester.pump();
            expect(api.writes, [(action, _site, 'key')]);

            if (replacement == 'account') {
              await shell.disconnectCurrentInstance();
              await shell.connectCurrentInstance();
            } else {
              await _pump(tester, await _loadShell(_StatusApi()));
            }
            if (failure) {
              gate.completeError(const WriteException(WriteFailure.forbidden));
            } else {
              gate.complete();
            }
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));

            expect(
              tester.element(find.byKey(const ValueKey('user-status-editor'))),
              same(dialog),
            );
            expect(_button(tester, 'Save').loading, isTrue);
            expect(
              find.text(const WriteException(WriteFailure.forbidden).message),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('$action admits only one write from same-frame callbacks', (
      tester,
    ) async {
      final api = _StatusApi();
      final gate = _writeGate(api);
      await _open(tester, api: api);
      final save = _button(tester, 'Save').onPressed!;
      final clear = _button(tester, 'Clear status').onPressed!;
      final submit = action == 'Save' ? save : clear;
      submit();
      submit();
      (action == 'Save' ? clear : save)();
      await tester.pump();

      expect(api.writes, [(action, _site, 'key')]);
      expect(_button(tester, 'Save').loading, isTrue);
      expect(
        find.text('Another status change is still finishing.'),
        findsNothing,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-status-editor')), findsNothing);
    });
  }

  testWidgets('accepted expiry picker cannot continue after reconnect', (
    tester,
  ) async {
    final api = await _open(tester);
    final shell = ShellScope.read(
      tester.element(find.byKey(const ValueKey('user-status-editor'))),
    );
    await _select(tester, 'Custom date and time');
    await shell.disconnectCurrentInstance();
    await shell.connectCurrentInstance();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.byType(DCalendar), findsNothing);
    expect(find.text('Never').hitTestable(), findsOneWidget);
    expect(find.textContaining('Until '), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.userStatusesSet, isEmpty);
  });

  for (final reconnect in [false, true]) {
    testWidgets(
      'emoji selection ${reconnect ? 'is ignored after reconnect' : 'is displayed in the picker button and saved'}',
      (tester) async {
        final api = _StatusApi();
        await _open(tester, api: api);
        final shell = ShellScope.read(
          tester.element(find.byKey(const ValueKey('user-status-editor'))),
        );
        await tester.tap(find.byTooltip('Choose status emoji'));
        await tester.pumpAndSettle();
        final picker = tester.widget<EmojiPicker>(find.byType(EmojiPicker));
        if (reconnect) {
          await shell.disconnectCurrentInstance();
          await shell.connectCurrentInstance();
          await tester.pumpAndSettle();
          expect(await picker.controller.loadCatalog(refresh: true), isNull);
          expect(
            await picker.controller.loadSearchAliases(refresh: true),
            isNull,
          );
        }
        await tester.tap(
          find.byKey(const ValueKey('emoji-picker-cell-default-0-smile')),
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .widgetList<SiteEmojiImage>(find.byType(SiteEmojiImage))
              .map((image) => image.name),
          [reconnect ? 'house' : 'smile'],
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          api.userStatusesSet,
          reconnect
              ? isEmpty
              : [(description: 'Working', emoji: 'smile', endsAt: null)],
        );
      },
    );
  }

  testWidgets('saving a paused status and clearing it updates notifications', (
    tester,
  ) async {
    final api = _StatusApi();
    await _open(tester, api: api);
    final shell = ShellScope.read(
      tester.element(find.byKey(const ValueKey('user-status-editor'))),
    );
    await tester.tap(find.text('Pause notifications'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.userStatusesSet, [
      (description: 'Working', emoji: 'house', endsAt: null),
    ]);
    expect(api.doNotDisturbDurations, hasLength(1));
    expect(shell.doNotDisturb.stateFor(_site).until, eternalDoNotDisturbUntil);
    expect(find.byKey(const ValueKey('user-status-editor')), findsNothing);

    await tester.tap(find.text('Edit status'));
    await tester.pumpAndSettle();
    expect(tester.widget<DSwitchTile>(find.byType(DSwitchTile)).value, isTrue);
    await tester.tap(find.text('Clear status'));
    await tester.pumpAndSettle();
    expect(api.userStatusesCleared, [_site]);
    expect(api.doNotDisturbResumes, [_site]);
    expect(shell.currentInstance?.user?.status, isNull);
    expect(shell.doNotDisturb.stateFor(_site).until, isNull);
    expect(find.byKey(const ValueKey('user-status-editor')), findsNothing);
  });

  testWidgets('a current write failure allows retrying the edited status', (
    tester,
  ) async {
    final api = _StatusApi();
    final gate = _writeGate(api);
    await _open(tester, api: api);
    await tester.enterText(find.byType(TextField), '  On holiday  ');
    await tester.tap(find.text('Save'));
    await tester.pump();
    gate.completeError(const WriteException(WriteFailure.forbidden));
    await tester.pumpAndSettle();
    expect(
      find.text(const WriteException(WriteFailure.forbidden).message),
      findsOneWidget,
    );
    expect(_button(tester, 'Save').loading, isFalse);
    api.writeGate = null;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.userStatusesSet.single.description, 'On holiday');
    expect(find.byKey(const ValueKey('user-status-editor')), findsNothing);
  });

  for (final original in ['Never', '1 hour', '2 hours', 'Tomorrow', 'custom']) {
    testWidgets('cancel expiry picker retains $original in field and save', (
      tester,
    ) async {
      final stored = original == 'custom'
          ? DateTime.now().add(const Duration(days: 3))
          : null;
      final api = await _open(tester, endsAt: stored, timezone: _zone);
      if (original != 'Never' && original != 'custom') {
        await _select(tester, original);
      }
      await _select(tester, 'Custom date and time');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(
        find
            .text(original == 'custom' ? 'Custom date and time' : original)
            .hitTestable(),
        findsOneWidget,
      );
      final before = DateTime.now();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final submitted = api.userStatusesSet.single.endsAt?.toUtc();
      if (original == 'Never') {
        expect(submitted, isNull);
      } else if (original == 'custom') {
        expect(submitted, stored!.toUtc());
      } else if (original == 'Tomorrow') {
        final today = tz.TZDateTime.from(before, _location());
        // Eight o'clock on the next Kiritimati day is 18:00 UTC on this one.
        expect(submitted, DateTime.utc(today.year, today.month, today.day, 18));
      } else {
        final hours = original == '1 hour' ? 1 : 2;
        expect(
          submitted!.difference(before).inSeconds,
          inInclusiveRange(hours * 3600, hours * 3600 + 2),
        );
      }
    });
  }

  testWidgets(
    'accepted custom expiry is retained after reopening and cancelling',
    (tester) async {
      final api = await _open(tester, timezone: _zone);
      await _select(tester, 'Custom date and time');
      final date =
          (tester.widget<DCalendar>(find.byType(DCalendar)).selection
                  as DCalendarSingleSelection)
              .date!;
      final time = tester
          .widget<DTimeInput>(find.byType(DTimeInput))
          .initialValue!;
      // The picked wall time is the account's: UTC+14.
      final expected = DateTime.utc(
        date.year,
        date.month,
        date.day,
        time.hour - 14,
        time.minute,
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Custom date and time').hitTestable(), findsOneWidget);
      expect(find.textContaining('Until '), findsOneWidget);
      await _select(tester, 'Custom date and time');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.userStatusesSet.single.endsAt?.toUtc(), expected);
    },
  );

  testWidgets('a stored expiry is shown and edited in the account timezone', (
    tester,
  ) async {
    final year = DateTime.now().year + 1;
    // 02:00 on 16 June at UTC+14.
    final stored = DateTime.utc(year, 6, 15, 12);
    final api = await _open(tester, endsAt: stored, timezone: _zone);
    expect(find.textContaining('Jun 16 2:00'), findsOneWidget);

    await _select(tester, 'Custom date and time');
    expect(
      (tester.widget<DCalendar>(find.byType(DCalendar)).selection
              as DCalendarSingleSelection)
          .date,
      DCalendarDate(year, 6, 16),
    );
    final time = tester
        .widget<DTimeInput>(find.byType(DTimeInput))
        .initialValue!;
    expect(time.hour, 2);
    expect(time.minute, 0);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.userStatusesSet.single.endsAt?.toUtc(), stored);
  });

  testWidgets(
    'stored expiry beyond picker bounds opens and cancellation preserves it',
    (tester) async {
      final stored = DateTime(DateTime.now().year + 10, 6, 15, 12);
      final api = await _open(tester, endsAt: stored);
      await _select(tester, 'Custom date and time');
      expect(tester.takeException(), isNull);
      final picker = tester.widget<DCalendar>(find.byType(DCalendar));
      expect(
        (picker.selection as DCalendarSingleSelection).date,
        picker.endMonth,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.userStatusesSet.single.endsAt?.toUtc(), stored.toUtc());
    },
  );
}

Future<void> _select(WidgetTester tester, String label) async {
  await tester.tap(find.byWidgetPredicate((widget) => widget is DSelect));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

tz.Location _location() =>
    (TimezoneEnvironment.instance..ensureDatabase()).location(_zone)!;

Future<FakeDiscourseApi> _open(
  WidgetTester tester, {
  DateTime? endsAt,
  String? timezone,
  FakeDiscourseApi? api,
  TargetPlatform platform = TargetPlatform.macOS,
  bool dark = false,
  bool hasStatus = true,
  double textScale = 1,
}) async {
  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    timezone: timezone,
    status: hasStatus
        ? UserStatus(description: 'Working', emoji: 'house', endsAt: endsAt)
        : null,
  );
  api ??= FakeDiscourseApi(
    user: user,
    feeds: const {'/latest.json': <Topic>[]},
    siteConfigs: const {_site: SiteConfig(userStatusEnabled: true)},
  );
  final shell = await _loadShell(api, user: user);
  await _pump(
    tester,
    shell,
    platform: platform,
    dark: dark,
    textScale: textScale,
  );
  await tester.tap(find.text('Edit status'));
  await tester.pumpAndSettle();
  return api;
}

Future<ShellController> _loadShell(
  FakeDiscourseApi api, {
  DiscourseUser user = _user,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: user, config: const SiteConfig(userStatusEnabled: true)),
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
  bool dark = false,
  double textScale = 1,
}) => tester.pumpWidget(
  ShellScope(
    controller: shell,
    child: MaterialApp(
      theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
        platform: platform,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showUserStatusEditor(context, siteUrl: _site),
            child: const Text('Edit status'),
          ),
        ),
      ),
    ),
  ),
);

DButton _button(WidgetTester tester, String label) => tester.widget<DButton>(
  find.byWidgetPredicate(
    (widget) =>
        widget is DButton &&
        widget.label is Text &&
        (widget.label as Text).data == label,
  ),
);

Completer<void> _writeGate(_StatusApi api) {
  final gate = Completer<void>();
  api.writeGate = gate.future;
  addTearDown(() {
    if (!gate.isCompleted) gate.complete();
  });
  return gate;
}

class _StatusApi extends FakeDiscourseApi {
  _StatusApi()
    : super(
        user: _user,
        feeds: const {'/latest.json': <Topic>[]},
        siteConfigs: const {_site: SiteConfig(userStatusEnabled: true)},
        doNotDisturbUntil: eternalDoNotDisturbUntil,
        emojisBySite: const {
          _site: [SiteEmoji(name: 'smile', url: '$_site/smile.png')],
        },
      );

  Future<void>? writeGate;
  final writes = <(String, String, String)>[];

  @override
  Future<void> setUserStatus({
    required String siteUrl,
    required String apiKey,
    required String description,
    required String emoji,
    DateTime? endsAt,
    String? clientId,
  }) async {
    writes.add(('Save', siteUrl, apiKey));
    await writeGate;
    await super.setUserStatus(
      siteUrl: siteUrl,
      apiKey: apiKey,
      description: description,
      emoji: emoji,
      endsAt: endsAt,
      clientId: clientId,
    );
  }

  @override
  Future<void> clearUserStatus({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    writes.add(('Clear status', siteUrl, apiKey));
    await writeGate;
    await super.clearUserStatus(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}

final class _HttpStatusApi extends FakeDiscourseApi {
  _HttpStatusApi(this.writer)
    : super(
        user: _user,
        feeds: const {'/latest.json': <Topic>[]},
        siteConfigs: const {_site: SiteConfig(userStatusEnabled: true)},
      );

  final DiscourseApi writer;

  @override
  Future<void> setUserStatus({
    required String siteUrl,
    required String apiKey,
    required String description,
    required String emoji,
    DateTime? endsAt,
    String? clientId,
  }) => writer.setUserStatus(
    siteUrl: siteUrl,
    apiKey: apiKey,
    description: description,
    emoji: emoji,
    endsAt: endsAt,
    clientId: clientId,
  );
}
