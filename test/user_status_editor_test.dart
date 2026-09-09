import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(
  id: 7,
  username: 'reader',
  status: UserStatus(description: 'Working', emoji: 'house'),
);

void main() {
  for (final action in ['Save', 'Clear status']) {
    testWidgets(
      '$action rejects a replaced shell while the dialog stays open',
      (tester) async {
        final api = await _open(tester);
        final dialog = tester.element(find.byType(AlertDialog));
        final replacementApi = _StatusApi();
        await _pump(tester, await _loadShell(replacementApi));
        expect(tester.element(find.byType(AlertDialog)), same(dialog));

        await tester.tap(find.text(action));
        await tester.pumpAndSettle();

        expect(api.userStatusesSet, isEmpty);
        expect(api.userStatusesCleared, isEmpty);
        expect(replacementApi.writes, isEmpty);
        expect(find.byType(AlertDialog), findsOneWidget);
      },
    );

    testWidgets('$action rejects an opening from before account reconnect', (
      tester,
    ) async {
      final api = await _open(tester);
      final dialog = tester.element(find.byType(AlertDialog));
      final shell = ShellScope.read(dialog);
      await shell.disconnectCurrentInstance();
      await shell.connectCurrentInstance();
      await tester.pumpAndSettle();
      expect(shell.currentInstance?.isConnected, isTrue);
      expect(tester.element(find.byType(AlertDialog)), same(dialog));

      await tester.tap(find.text(action));
      await tester.pumpAndSettle();

      expect(api.userStatusesSet, isEmpty);
      expect(api.userStatusesCleared, isEmpty);
      expect(api.doNotDisturbDurations, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    for (final replacement in ['account', 'shell']) {
      for (final failure in [false, true]) {
        testWidgets(
          '$action late ${failure ? 'failure' : 'success'} leaves a retired $replacement dialog untouched',
          (tester) async {
            final api = _StatusApi();
            final gate = _writeGate(api);
            await _open(tester, api: api);
            final dialog = tester.element(find.byType(AlertDialog));
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

            expect(tester.element(find.byType(AlertDialog)), same(dialog));
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
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

  for (final stage in ['date', 'time']) {
    testWidgets('accepted $stage picker cannot continue after reconnect', (
      tester,
    ) async {
      final api = await _open(tester);
      final shell = ShellScope.read(tester.element(find.byType(AlertDialog)));
      await _select(tester, 'Custom date and time');
      if (stage == 'time') {
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      await shell.disconnectCurrentInstance();
      await shell.connectCurrentInstance();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.text('Never').hitTestable(), findsOneWidget);
      expect(find.textContaining('Until '), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.userStatusesSet, isEmpty);
    });
  }

  for (final reconnect in [false, true]) {
    testWidgets(
      'emoji selection ${reconnect ? 'is ignored after reconnect' : 'is previewed and saved'}',
      (tester) async {
        final api = _StatusApi();
        await _open(tester, api: api);
        final shell = ShellScope.read(tester.element(find.byType(AlertDialog)));
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
          [reconnect ? 'house' : 'smile', reconnect ? 'house' : 'smile'],
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
    final shell = ShellScope.read(tester.element(find.byType(AlertDialog)));
    await tester.tap(find.text('Pause notifications'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.userStatusesSet, [
      (description: 'Working', emoji: 'house', endsAt: null),
    ]);
    expect(api.doNotDisturbDurations, hasLength(1));
    expect(shell.doNotDisturb.stateFor(_site).until, eternalDoNotDisturbUntil);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('Edit status'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    await tester.tap(find.text('Clear status'));
    await tester.pumpAndSettle();
    expect(api.userStatusesCleared, [_site]);
    expect(api.doNotDisturbResumes, [_site]);
    expect(shell.currentInstance?.user?.status, isNull);
    expect(shell.doNotDisturb.stateFor(_site).until, isNull);
    expect(find.byType(AlertDialog), findsNothing);
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
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final original in ['Never', '1 hour', '2 hours', 'Tomorrow', 'custom']) {
    for (final stage in ['date', 'time']) {
      testWidgets('cancel $stage picker retains $original in field and save', (
        tester,
      ) async {
        final stored = original == 'custom'
            ? DateTime.now().add(const Duration(days: 3))
            : null;
        final api = await _open(tester, endsAt: stored);
        if (original != 'Never' && original != 'custom') {
          await _select(tester, original);
        }
        await _select(tester, 'Custom date and time');
        if (stage == 'time') {
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          expect(find.byType(TimePickerDialog), findsOneWidget);
        }
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
          expect(
            submitted,
            DateTime(before.year, before.month, before.day + 1, 8, 30).toUtc(),
          );
        } else {
          final hours = original == '1 hour' ? 1 : 2;
          expect(
            submitted!.difference(before).inSeconds,
            inInclusiveRange(hours * 3600, hours * 3600 + 2),
          );
        }
      });
    }
  }

  testWidgets(
    'accepted custom expiry is retained after reopening and cancelling',
    (tester) async {
      final api = await _open(tester);
      await _select(tester, 'Custom date and time');
      final date = tester
          .widget<DatePickerDialog>(find.byType(DatePickerDialog))
          .initialDate!;
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final time = tester
          .widget<TimePickerDialog>(find.byType(TimePickerDialog))
          .initialTime;
      final expected = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Custom date and time').hitTestable(), findsOneWidget);
      expect(find.textContaining('Until '), findsOneWidget);
      await _select(tester, 'Custom date and time');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.userStatusesSet.single.endsAt?.toUtc(), expected.toUtc());
    },
  );

  testWidgets(
    'stored expiry beyond picker bounds opens and cancellation preserves it',
    (tester) async {
      final stored = DateTime(DateTime.now().year + 10, 6, 15, 12);
      final api = await _open(tester, endsAt: stored);
      await _select(tester, 'Custom date and time');
      expect(tester.takeException(), isNull);
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.initialDate, picker.lastDate);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.userStatusesSet.single.endsAt?.toUtc(), stored.toUtc());
    },
  );
}

Future<void> _select(WidgetTester tester, String label) async {
  await tester.tap(
    find.byWidgetPredicate((widget) => widget is DropdownButton),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<FakeDiscourseApi> _open(
  WidgetTester tester, {
  DateTime? endsAt,
  FakeDiscourseApi? api,
}) async {
  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    status: UserStatus(description: 'Working', emoji: 'house', endsAt: endsAt),
  );
  api ??= FakeDiscourseApi(
    user: user,
    feeds: const {'/latest.json': <Topic>[]},
    siteConfigs: const {_site: SiteConfig(userStatusEnabled: true)},
  );
  final shell = await _loadShell(api, user: user);
  await _pump(tester, shell);
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

Future<void> _pump(WidgetTester tester, ShellController shell) =>
    tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
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
