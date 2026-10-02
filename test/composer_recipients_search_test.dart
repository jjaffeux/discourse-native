import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/found_group.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_recipients.dart';
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

Future<ComposerController> _pump(
  WidgetTester tester, {
  required bool mobile,
  required _RecipientApi api,
  String recipients = '',
}) async {
  tester.view.physicalSize = Size(mobile ? 390 : 1180, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final composer = ComposerController(
    ComposerTarget(
      siteUrl: _site,
      topicId: 0,
      slug: '',
      topicTitle: 'New message',
      mode: ComposerMode.privateMessage,
      targetRecipients: recipients,
    ),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'test-api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  addTearDown(composer.dispose);
  addTearDown(shell.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(
        platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
      home: ShellScope(
        controller: shell,
        child: Scaffold(
          body: ListenableBuilder(
            listenable: composer,
            builder: (_, _) => ComposerRecipients(composer: composer),
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

  @override
  Future<FoundUsersAndGroups> searchUsersAndGroups({
    required String siteUrl,
    required String term,
    int limit = 6,
    String? apiKey,
    String? clientId,
  }) async {
    terms.add(term);
    return switch (term) {
      'sa' => const FoundUsersAndGroups(users: [_sam]),
      'alice' => pending.future,
      _ => const FoundUsersAndGroups(),
    };
  }
}
