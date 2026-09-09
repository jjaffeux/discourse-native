import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/do_not_disturb_dialog.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

void main() {
  for (final replacement in ['account', 'shell']) {
    for (final action in ['pause', 'schedule']) {
      testWidgets(
        '$action rejects an opening from before $replacement replacement',
        (tester) async {
          final api = _DndApi();
          final launcher = _watchLauncher(tester);
          final shell = await _open(tester, api);
          final dialog = tester.element(find.byType(AlertDialog));
          final replacementApi = _DndApi();
          if (replacement == 'account') {
            await shell.disconnectCurrentInstance();
            await shell.connectCurrentInstance();
            expect(shell.currentInstance?.isConnected, isTrue);
          } else {
            await _pump(tester, await _loadShell(replacementApi));
          }
          await tester.pumpAndSettle();
          expect(tester.element(find.byType(AlertDialog)), same(dialog));

          await tester.tap(
            action == 'pause'
                ? _oneHour
                : find.text('Set a notification schedule'),
          );
          await tester.pumpAndSettle();

          expect(api.writes, isEmpty);
          expect(replacementApi.writes, isEmpty);
          expect(launcher.urls, isEmpty);
          expect(find.byType(AlertDialog), findsOneWidget);
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
          final dialog = tester.element(find.byType(AlertDialog));
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

          expect(tester.element(find.byType(AlertDialog)), same(dialog));
          expect(tester.widget<OutlinedButton>(_oneHour).onPressed, isNull);
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
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

  testWidgets('same-frame pause and schedule callbacks admit one operation', (
    tester,
  ) async {
    final api = _DndApi();
    final gate = _writeGate(api);
    final launcher = _watchLauncher(tester);
    await _open(tester, api);
    final pause = tester.widget<OutlinedButton>(_oneHour).onPressed!;
    final schedule = _scheduleButton(tester).onPressed!;
    pause();
    pause();
    schedule();
    await tester.pump();
    expect(api.writes, [
      (_site, 'key', const DoNotDisturbDuration.minutes(60)),
    ]);
    expect(launcher.urls, isEmpty);
    expect(tester.widget<OutlinedButton>(_oneHour).onPressed, isNull);
    expect(
      find.text('Another notification change is still finishing.'),
      findsNothing,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('schedule opens once and rejects same-frame pause callbacks', (
    tester,
  ) async {
    final api = _DndApi();
    final launcher = _watchLauncher(tester);
    await _open(tester, api);
    final pause = tester.widget<OutlinedButton>(_oneHour).onPressed!;
    final schedule = _scheduleButton(tester).onPressed!;
    schedule();
    schedule();
    pause();
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(launcher.urls, ['$_site/u/reader/preferences/notifications']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final replacement in ['none', 'account', 'shell', 'messenger']) {
    testWidgets(
      'late schedule failure with $replacement replacement is reported only to its live owner',
      (tester) async {
        final launcher = _watchLauncher(tester);
        final shell = await _open(tester, _DndApi());
        await tester.tap(find.text('Set a notification schedule'));
        await tester.pumpAndSettle();
        expect(launcher.urls, ['$_site/u/reader/preferences/notifications']);
        expect(find.byType(AlertDialog), findsNothing);

        switch (replacement) {
          case 'account':
            await shell.disconnectCurrentInstance();
            await shell.connectCurrentInstance();
          case 'shell':
            await _pump(tester, await _loadShell(_DndApi()));
          case 'messenger':
            await tester.pumpWidget(const SizedBox.shrink());
          case 'none':
            break;
        }
        launcher.result.complete(false);
        await tester.pumpAndSettle();
        expect(
          find.text('Could not open notification preferences.'),
          replacement == 'none' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    expect(find.byType(AlertDialog), findsNothing);
  });
}

Finder get _oneHour => find.byKey(const ValueKey('do-not-disturb-oneHour'));

DButton _scheduleButton(WidgetTester tester) => tester.widget<DButton>(
  find.ancestor(
    of: find.text('Set a notification schedule'),
    matching: find.byType(DButton),
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
  _DndApi()
    : super(
        user: _user,
        feeds: const {'/latest.json': <Topic>[]},
        doNotDisturbUntil: eternalDoNotDisturbUntil,
      );

  Future<void>? writeGate;
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

Future<void> _pump(WidgetTester tester, ShellController shell) =>
    tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showDoNotDisturbDialog(context, siteUrl: _site),
                child: const Text('Pause'),
              ),
            ),
          ),
        ),
      ),
    );
