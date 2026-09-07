import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_status_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
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

Future<FakeDiscourseApi> _open(WidgetTester tester, {DateTime? endsAt}) async {
  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    status: UserStatus(description: 'Working', emoji: 'house', endsAt: endsAt),
  );
  final api = FakeDiscourseApi(
    user: user,
    feeds: const {'/latest.json': <Topic>[]},
    siteConfigs: const {_site: SiteConfig(userStatusEnabled: true)},
  );
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
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
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
  await tester.tap(find.text('Edit status'));
  await tester.pumpAndSettle();
  return api;
}
