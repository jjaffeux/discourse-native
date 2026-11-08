import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _titleKeyBudget = 50;
const _saveBudget = 20;

void main() {
  for (final mobile in [false, true]) {
    final surface = mobile ? 'phone' : 'desktop';

    testWidgets('$surface title keys and caret moves leave the panel alone', (
      tester,
    ) async {
      final (:composer, :api) = await _openNewTopic(tester, mobile: mobile);
      composer.titleFocus.requestFocus();
      await tester.pumpAndSettle();
      final field = _fieldOf(composer.title);
      _type(composer.title, 'T');
      await tester.pump();

      var notifications = 0;
      void listener() => notifications++;
      composer.addListener(listener);
      addTearDown(() => composer.removeListener(listener));

      var keyElements = 0;
      const typed = 'Typed!';
      for (var length = 2; length <= typed.length; length++) {
        keyElements = math.max(
          keyElements,
          await _elementsRebuilt(() async {
            _type(composer.title, typed.substring(0, length));
            await tester.pump();
          }),
        );
      }
      final keyNotifications = notifications;
      final drawnTitle = tester
          .state<EditableTextState>(field)
          .renderEditable
          .text
          ?.toPlainText();

      await _saveDraftAndSettle(tester);
      final savesAfterTyping = api.draftsSaved.length;
      notifications = 0;

      var caretElements = 0;
      for (var offset = 0; offset < typed.length - 1; offset++) {
        caretElements = math.max(
          caretElements,
          await _elementsRebuilt(() async {
            composer.title.selection = TextSelection.collapsed(offset: offset);
            await tester.pump();
          }),
        );
      }
      final caretNotifications = notifications;
      final drawnCaret = tester
          .state<EditableTextState>(field)
          .renderEditable
          .selection;
      await _saveDraftAndSettle(tester);
      final caretSaves = api.draftsSaved.length - savesAfterTyping;

      _proof('title_key_elements_$surface', keyElements);
      _proof('title_key_notifications_$surface', keyNotifications);
      _proof('title_caret_elements_$surface', caretElements);
      _proof('title_caret_notifications_$surface', caretNotifications);
      _proof('title_caret_draft_saves_$surface', caretSaves);

      expect(drawnTitle, typed);
      expect(
        drawnCaret,
        const TextSelection.collapsed(offset: typed.length - 2),
      );
      expect(savesAfterTyping, greaterThan(0));
      expect(keyElements, greaterThan(0));
      expect(caretElements, greaterThan(0));
      expect(keyElements, lessThanOrEqualTo(_titleKeyBudget));
      expect(caretElements, lessThanOrEqualTo(_titleKeyBudget));
      expect(keyNotifications, 0);
      expect(caretNotifications, 0);
      expect(caretSaves, 0);
    });
  }

  for (final mobile in [false, true]) {
    final surface = mobile ? 'phone' : 'desktop';
    final burstBudget = mobile ? 420 : 500;

    testWidgets('$surface body burst and its save leave the panel alone', (
      tester,
    ) async {
      final (:composer, :api) = await _openNewTopic(tester, mobile: mobile);
      composer.title.text = 'Title';
      _type(composer.text, 'Body');
      await tester.pump();
      await _saveDraftAndSettle(tester);
      composer.focus.requestFocus();
      await tester.pumpAndSettle();
      final field = _fieldOf(composer.text);
      final savesBefore = api.draftsSaved.length;

      var notifications = 0;
      void listener() => notifications++;
      composer.addListener(listener);
      addTearDown(() => composer.removeListener(listener));

      const burst = 'Body words';
      final burstElements = await _elementsRebuilt(() async {
        for (var length = 'Body'.length + 1; length <= 9; length++) {
          _type(composer.text, burst.substring(0, length));
          await tester.pump();
        }
      });
      final drawn = tester
          .state<EditableTextState>(field)
          .renderEditable
          .text
          ?.toPlainText();
      final burstNotifications = notifications;
      final saveElements = await _elementsRebuilt(
        () => _saveDraftAndSettle(tester),
      );
      final saved = api.draftsSaved.length - savesBefore;

      const slug = 'composer-draft-status';
      _proof('burst_elements_$surface', burstElements, slug: slug);
      _proof('burst_notifications_$surface', burstNotifications, slug: slug);
      _proof('save_elements_$surface', saveElements, slug: slug);
      _proof(
        'burst_and_save_notifications_$surface',
        notifications,
        slug: slug,
      );

      expect(drawn, burst.substring(0, 9));
      expect(saved, 1);
      expect(burstElements, greaterThan(0));
      expect(burstElements, lessThanOrEqualTo(burstBudget));
      expect(saveElements, lessThanOrEqualTo(_saveBudget));
      expect(notifications, 0);
    });
  }

  testWidgets('the phone close menu weighs the draft as it opens', (
    tester,
  ) async {
    final (:composer, api: _) = await _openNewTopic(tester, mobile: true);
    expect(
      composer.restore(
        const ComposerDraft(
          action: ComposerDraft.createTopicAction,
          title: 'Saved title',
          reply: 'Saved body',
        ),
      ),
      isTrue,
    );
    await tester.pump();

    _type(composer.text, 'Saved body, edited');
    await tester.pump();
    await _saveDraftAndSettle(tester);

    await tester.tap(find.byKey(const ValueKey('composer-close')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('composer-save-draft')),
        matching: find.text('Save changes'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a desktop draft tab and the all-drafts menu follow the title', (
    tester,
  ) async {
    final (:composer, api: _) = await _openNewTopic(tester, mobile: false);
    Finder tabLabel(String title) => find.descendant(
      of: find.byType(DDocumentTab),
      matching: find.text(title),
    );

    _type(composer.title, 'First title');
    await tester.pump();
    expect(tabLabel('First title'), findsOneWidget);

    _type(composer.title, 'Second title');
    await tester.pump();
    expect(tabLabel('First title'), findsNothing);
    expect(tabLabel('Second title'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('composer-all-drafts')));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(DDropdownMenuItem, 'Second title'),
      findsOneWidget,
    );
    await _saveDraftAndSettle(tester);
  });

  testWidgets('the first title key still arms the phone close menu', (
    tester,
  ) async {
    final (:composer, api: _) = await _openNewTopic(tester, mobile: true);
    String closeTooltip() => tester
        .widget<DButton>(find.byKey(const ValueKey('composer-close')))
        .tooltip!;
    expect(closeTooltip(), 'Close composer');

    _type(composer.title, 'T');
    await tester.pump();
    expect(closeTooltip(), 'Composer actions');

    _type(composer.title, '');
    await tester.pump();
    expect(closeTooltip(), 'Close composer');
    await _saveDraftAndSettle(tester);
  });

  testWidgets('a title key still enables the submit button when it decides', (
    tester,
  ) async {
    final (:composer, api: _) = await _openNewTopic(tester, mobile: true);
    composer.text.text = 'A body long enough to post';
    await tester.pump();
    VoidCallback? submit() => tester
        .widget<DButton>(find.byKey(const ValueKey('composer-submit')))
        .onPressed;
    expect(submit(), isNull);

    _type(composer.title, 'T');
    await tester.pump();

    expect(composer.canSubmit, isTrue);
    expect(submit(), isNotNull);
    await _saveDraftAndSettle(tester);
  });
}

void _proof(String metric, int value, {String slug = 'composer-title'}) {
  // ignore: avoid_print
  print('PERF_PROOF $slug $metric=$value');
}

Future<void> _saveDraftAndSettle(WidgetTester tester) async {
  await tester.pump(ComposerController.draftDebounce);
  await tester.pumpAndSettle();
}

void _type(TextEditingController field, String value) {
  field.value = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );
}

Finder _fieldOf(TextEditingController controller) => find.byWidgetPredicate(
  (widget) =>
      widget is EditableText && identical(widget.controller, controller),
);

Future<int> _elementsRebuilt(Future<void> Function() action) async {
  var rebuilt = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    rebuilt++;
    previous?.call(element, builtOnce);
  };
  try {
    await action();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return rebuilt;
}

Future<({ComposerController composer, FakeDiscourseApi api})> _openNewTopic(
  WidgetTester tester, {
  required bool mobile,
}) async {
  const user = DiscourseUser(id: 7, username: 'sam', canCreateTopic: true);
  final api = FakeDiscourseApi(
    user: user,
    feeds: const {'/latest.json': []},
    creatableFeedPaths: const {'/latest.json'},
  );
  final shell = ShellController(
    mobileNavigationEnabled: mobile,
    forumTabsEnabled: false,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()
      ..keys['https://meta.discourse.org'] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = mobile
      ? const Size(390, 844)
      : const Size(1280, 850);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(
          platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
        ),
        home: const AdaptiveShell(),
      ),
    ),
  );
  await shell.openNewTopicFromSidebar();
  await tester.pumpAndSettle();
  return (composer: shell.visibleComposer!, api: api);
}
