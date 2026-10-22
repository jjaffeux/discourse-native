import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/found_group.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/recipients.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _sam = FoundUser(username: 'sam');
const _alice = FoundUser(username: 'alice');
final _input = find.byKey(const ValueKey('composer-recipients-input'));

Finder _option(String name) => find.byWidgetPredicate(
  (widget) => widget is DComboboxItem<String> && widget.option.value == name,
);

void main() {
  for (final mobile in [false, true]) {
    for (final duringLookup in [false, true]) {
      testWidgets('retained recipient widget retires replaced composer on '
          '${mobile ? 'mobile' : 'desktop'} '
          '${duringLookup ? 'during lookup' : 'during debounce'}', (
        tester,
      ) async {
        final pending = Completer<FoundUsersAndGroups>();
        final api = _RecipientApi(pending);
        final original = _composer();
        final replacement = _composer(siteUrl: 'https://other.example');
        final source = ValueNotifier(original);
        addTearDown(source.dispose);
        addTearDown(replacement.dispose);
        await _pump(tester, mobile: mobile, api: api, composerSource: source);
        await _findSam(tester, mobile: mobile);
        final state = tester.state(find.byType(ComposerRecipients));
        await tester.enterText(_input, 'alice');
        if (duringLookup) {
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pump();
        }
        source.value = replacement;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ComposerRecipients)), same(state));
        pending.complete(const FoundUsersAndGroups(users: [_alice]));
        await tester.pumpAndSettle();
        expect(
          api.terms.where((term) => term == 'alice').length,
          duringLookup ? 1 : 0,
        );
        if (mobile) {
          await tester.tap(find.byKey(const ValueKey('composer-recipients')));
          await tester.pumpAndSettle();
        }
        expect(_editable(tester).controller.text, isEmpty);
        expect(_option('alice'), findsNothing);
        expect(_option('sam'), findsNothing);
        await _findSam(tester, mobile: false);
        expect(api.sites.last, 'https://other.example');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('recipient lookup retires on shell replacement on '
        '${mobile ? 'mobile' : 'desktop'}', (tester) async {
      final pending = Completer<FoundUsersAndGroups>();
      final api = _RecipientApi(pending);
      final original = _shell(api);
      final replacementApi = _RecipientApi(Completer<FoundUsersAndGroups>());
      final replacement = _shell(replacementApi);
      await original.load();
      await replacement.load();
      final source = ValueNotifier(original);
      addTearDown(source.dispose);
      addTearDown(replacement.dispose);
      await _pump(tester, mobile: mobile, api: api, shellSource: source);
      await _findSam(tester, mobile: mobile);
      await tester.enterText(_input, 'alice');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      source.value = replacement;
      await tester.pumpAndSettle();
      pending.complete(const FoundUsersAndGroups(users: [_alice]));
      await tester.pumpAndSettle();
      if (mobile) {
        await tester.tap(find.byKey(const ValueKey('composer-recipients')));
        await tester.pumpAndSettle();
      }
      expect(_editable(tester).controller.text, isEmpty);
      expect(_option('alice'), findsNothing);
      await _findSam(tester, mobile: false);
      expect(replacementApi.terms, contains('sa'));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'recipient account retirement rejects a cached row before rebuild on '
      '${mobile ? 'mobile' : 'desktop'}',
      (tester) async {
        final composer = await _pump(
          tester,
          mobile: mobile,
          api: _RecipientApi(Completer<FoundUsersAndGroups>()),
        );
        await _findSam(tester, mobile: mobile);
        final picker = tester.widget<DCombobox<String>>(
          find.byKey(const ValueKey('composer-private-message-recipients')),
        );
        ShellScope.read(
          tester.element(find.byType(ComposerRecipients)),
        ).lifecycle.invalidate(_site);
        picker.onValuesChanged!(['sam'], DComboboxChangeReason.itemPress);
        expect(composer.target.targetRecipients, isEmpty);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('recipient target update retains current lookup on '
        '${mobile ? 'mobile' : 'desktop'}', (tester) async {
      final composer = await _pump(
        tester,
        mobile: mobile,
        api: _RecipientApi(Completer<FoundUsersAndGroups>()),
      );
      await _findSam(tester, mobile: mobile);
      final picker = tester.widget<DCombobox<String>>(
        find.byKey(const ValueKey('composer-private-message-recipients')),
      );
      final target = composer.target;
      picker.onValuesChanged!(['sam'], DComboboxChangeReason.itemPress);
      await tester.pump();
      expect(composer.target, isNot(same(target)));
      expect(composer.target.targetRecipients, 'sam');
      expect(_editable(tester).controller.text, 'sa');
      if (!mobile) expect(_option('sam'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('recipient target update preserves a pending request on '
        '${mobile ? 'mobile' : 'desktop'}', (tester) async {
      final pending = Completer<FoundUsersAndGroups>();
      final composer = await _pump(
        tester,
        mobile: mobile,
        api: _RecipientApi(pending),
        recipients: 'alex',
      );
      await _findSam(tester, mobile: mobile);
      await tester.enterText(_input, 'alice');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      composer.setRecipients(['alex', 'sam']);
      await tester.pump();
      expect(_editable(tester).controller.text, 'alice');
      pending.complete(const FoundUsersAndGroups(users: [_alice]));
      await tester.pumpAndSettle();
      expect(_option('alice'), findsOneWidget);
      await tester.tap(_option('alice'));
      await tester.pumpAndSettle();
      expect(composer.target.targetRecipients, 'alex,sam,alice');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'retired recipient row cannot select for replacement composer on '
      '${mobile ? 'mobile' : 'desktop'}',
      (tester) async {
        final original = _composer();
        final replacement = _composer();
        final source = ValueNotifier(original);
        addTearDown(source.dispose);
        addTearDown(replacement.dispose);
        await _pump(
          tester,
          mobile: mobile,
          api: _RecipientApi(Completer<FoundUsersAndGroups>()),
          composerSource: source,
        );
        await _findSam(tester, mobile: mobile);
        final picker = tester.widget<DCombobox<String>>(
          find.byKey(const ValueKey('composer-private-message-recipients')),
        );
        source.value = replacement;
        await tester.pumpAndSettle();
        picker.onValuesChanged!(['sam'], DComboboxChangeReason.itemPress);
        expect(original.target.targetRecipients, isEmpty);
        expect(replacement.target.targetRecipients, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    for (final duringLookup in [false, true]) {
      testWidgets('recipient account retirement cancels old lookup on '
          '${mobile ? 'mobile' : 'desktop'} '
          '${duringLookup ? 'during lookup' : 'during debounce'}', (
        tester,
      ) async {
        final pending = Completer<FoundUsersAndGroups>();
        final api = _RecipientApi(pending);
        final composer = await _pump(tester, mobile: mobile, api: api);
        await _findSam(tester, mobile: mobile);
        await tester.enterText(_input, 'alice');
        if (duringLookup) {
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pump();
        }
        final shell = ShellScope.read(
          tester.element(find.byType(ComposerRecipients)),
        );
        shell.lifecycle.invalidate(_site);
        await tester.pumpAndSettle();
        pending.complete(const FoundUsersAndGroups(users: [_alice]));
        await tester.pumpAndSettle();
        expect(
          api.terms.where((term) => term == 'alice').length,
          duringLookup ? 1 : 0,
        );
        if (mobile) {
          await tester.tap(find.byKey(const ValueKey('composer-recipients')));
          await tester.pumpAndSettle();
        }
        expect(_editable(tester).controller.text, isEmpty);
        expect(_option('alice'), findsNothing);
        expect(composer.target.targetRecipients, isEmpty);
        await _findSam(tester, mobile: false);
        expect(tester.takeException(), isNull);
      });
    }

    for (final duringLookup in [false, true]) {
      testWidgets('recipient Enter rejects old results on '
          '${mobile ? 'mobile' : 'desktop'} '
          '${duringLookup ? 'during lookup' : 'during debounce'}', (
        tester,
      ) async {
        final pending = Completer<FoundUsersAndGroups>();
        final api = _RecipientApi(pending);
        final composer = await _pump(tester, mobile: mobile, api: api);
        await _findSam(tester, mobile: mobile);

        await tester.enterText(_input, 'alice');
        if (duringLookup) {
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pump();
          expect(api.terms, contains('alice'));
        }
        // The debounce case intentionally attempts selection before a rebuild.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(composer.target.targetRecipients, '');
        await tester.pump();
        expect(_editable(tester).controller.text, 'alice');

        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();
        expect(api.terms, contains('alice'));
        pending.complete(const FoundUsersAndGroups(users: [_alice]));
        await tester.pumpAndSettle();
        expect(_option('sam'), findsNothing);
        await tester.tap(_option('alice'));
        await tester.pump();
        expect(composer.target.targetRecipients, 'alice');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('recipient click rejects an old row before rebuild on '
        '${mobile ? 'mobile' : 'desktop'}', (tester) async {
      final pending = Completer<FoundUsersAndGroups>();
      final api = _RecipientApi(pending);
      final composer = await _pump(tester, mobile: mobile, api: api);
      await _findSam(tester, mobile: mobile);
      await tester.enterText(_input, 'alice');
      await tester.tap(_option('sam'));
      expect(composer.target.targetRecipients, '');
      await tester.pump();
      expect(_editable(tester).controller.text, 'alice');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      pending.complete(const FoundUsersAndGroups(users: [_alice]));
      await tester.pumpAndSettle();
      await tester.tap(_option('alice'));
      await tester.pump();
      expect(composer.target.targetRecipients, 'alice');
      expect(tester.takeException(), isNull);
    });

    testWidgets('selected users and groups survive another recipient search on '
        '${mobile ? 'mobile' : 'desktop'}', (tester) async {
      final pending = Completer<FoundUsersAndGroups>();
      final api = _RecipientApi(pending);
      final composer = await _pump(
        tester,
        mobile: mobile,
        api: api,
        recipients: 'alex,team',
      );
      await _findSam(tester, mobile: mobile);
      await tester.enterText(_input, 'alice');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(composer.target.targetRecipients, 'alex,team');
      pending.complete(const FoundUsersAndGroups(users: [_alice]));
      await tester.pumpAndSettle();
      await tester.tap(_option('alice'));
      await tester.pumpAndSettle();
      expect(composer.target.targetRecipients, 'alex,team,alice');
      expect(composer.draft.recipients, 'alex,team,alice');

      if (mobile) {
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsNothing);
        await tester.tap(find.byKey(const ValueKey('composer-recipients')));
        await tester.pumpAndSettle();
        for (final name in ['alex', 'team', 'alice']) {
          expect(_option(name), findsOneWidget);
        }
        await tester.tap(_option('team'));
        await tester.pumpAndSettle();
        expect(composer.target.targetRecipients, 'alex,alice');
      } else {
        final picker = tester.widget<DCombobox<String>>(
          find.byKey(const ValueKey('composer-private-message-recipients')),
        );
        expect(picker.controlledValues, ['alex', 'team', 'alice']);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

EditableText _editable(WidgetTester tester) => tester.widget<EditableText>(
  find.descendant(of: _input, matching: find.byType(EditableText)),
);

Future<void> _findSam(WidgetTester tester, {required bool mobile}) async {
  if (mobile) {
    await tester.tap(find.byKey(const ValueKey('composer-recipients')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(_input, 'sa');
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
  expect(_option('sam'), findsOneWidget);
}

ComposerController _composer({
  String siteUrl = _site,
  String recipients = '',
}) => ComposerController(
  PrivateMessageComposerTarget(
    siteUrl: siteUrl,
    topicTitle: 'New message',
    targetRecipients: recipients,
  ),
);

ShellController _shell(_RecipientApi api) => ShellController(
  instanceStore: FakeInstanceStore(),
  api: api,
  authenticator: FakeAuthenticator()..keys[_site] = 'test-api-key',
  drafts: FakeDraftStore(),
  trackers: FakeSiteTracker.reset(),
);

Future<ComposerController> _pump(
  WidgetTester tester, {
  required bool mobile,
  required _RecipientApi api,
  String recipients = '',
  ValueNotifier<ComposerController>? composerSource,
  ValueNotifier<ShellController>? shellSource,
}) async {
  tester.view.physicalSize = Size(mobile ? 390 : 1180, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final composer = composerSource?.value ?? _composer(recipients: recipients);
  final shell = shellSource?.value ?? _shell(api);
  await shell.load();
  addTearDown(composer.dispose);
  addTearDown(shell.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(
        platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
      home: ListenableBuilder(
        listenable: shellSource ?? shell,
        builder: (_, _) => ShellScope(
          controller: shellSource?.value ?? shell,
          child: Scaffold(
            body: ListenableBuilder(
              listenable: composerSource ?? composer,
              builder: (_, _) {
                final current = composerSource?.value ?? composer;
                return ListenableBuilder(
                  listenable: current,
                  builder: (_, _) => ComposerRecipients(composer: current),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return composer;
}

class _RecipientApi extends FakeDiscourseApi {
  _RecipientApi(this.pending);

  final Completer<FoundUsersAndGroups> pending;
  final List<String> terms = [];
  final List<String> sites = [];

  @override
  Future<FoundUsersAndGroups> searchUsersAndGroups({
    required String siteUrl,
    required String term,
    int limit = 6,
    String? apiKey,
    String? clientId,
  }) async {
    terms.add(term);
    sites.add(siteUrl);
    return switch (term) {
      'sa' => const FoundUsersAndGroups(users: [_sam]),
      'alice' => pending.future,
      _ => const FoundUsersAndGroups(),
    };
  }
}
