import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _draft = UserDraft(
  key: 'new_topic',
  sequence: 1,
  data: ComposerDraft(reply: 'Draft body', title: 'Draft topic'),
);

void main() {
  for (final compact in [false, true]) {
    testWidgets(
      '${compact ? 'compact icon' : 'labeled'} New topic controls retain their hit targets and keyboard actions',
      (tester) async {
        final fixture = await _pump(
          tester,
          compact: compact,
          showLabel: !compact,
        );
        final semantics = tester.ensureSemantics();
        try {
          final create = find.byKey(TopicCreateButton.buttonKey);
          final drafts = find.byKey(TopicCreateButton.draftsButtonKey);

          _expectSmallDButton(tester, create, iconOnly: compact);
          _expectSmallDButton(tester, drafts, iconOnly: true);
          expect(
            tester.widget<DButton>(drafts).tooltip,
            'Open the latest drafts menu',
          );
          expect(
            tester.getSemantics(create),
            isSemantics(
              label: 'New topic',
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true,
            ),
          );
          expect(
            tester.getSemantics(drafts),
            isSemantics(
              label: 'Open the latest drafts menu',
              hasExpandedState: true,
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true,
            ),
          );
          expect(tester.getSemantics(create).tooltip, isEmpty);
          expect(tester.getSemantics(drafts).tooltip, isEmpty);

          final createFocus = _focusButton(tester, create);
          await tester.pumpAndSettle();
          expect(createFocus.hasPrimaryFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(fixture.createCalls(), 1);

          if (compact) {
            for (final button in [create, drafts]) {
              final surface = find.descendant(
                of: button,
                matching: find.byType(Material),
              );
              expect(tester.getSize(surface), tester.getSize(button));
              final bounds = tester.getRect(button);
              final edge = Offset(bounds.left + 1, bounds.center.dy);
              expect(tester.getRect(surface).contains(edge), isTrue);
              if (button == create) {
                await tester.tapAt(edge);
                await tester.pumpAndSettle();
                expect(fixture.createCalls(), 2);
              }
            }
          }

          final draftsFocus = _focusButton(tester, drafts);
          await tester.pumpAndSettle();
          expect(draftsFocus.hasPrimaryFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('recent-draft-new_topic')),
            findsOneWidget,
          );
          expect(fixture.api.userDraftRequests, [
            (siteUrl: _siteUrl, offset: 0, limit: 30),
          ]);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('compact toolbar controls grow with text and open drafts', (
    tester,
  ) async {
    await _pump(tester, compact: true, textScale: 2);
    final create = find.byKey(TopicCreateButton.buttonKey);
    final drafts = find.byKey(TopicCreateButton.draftsButtonKey);
    final createRect = tester.getRect(create);
    final draftRect = tester.getRect(drafts);
    expect(createRect.height, greaterThan(40));
    expect(draftRect.height, createRect.height);
    expect(draftRect.top, createRect.top);
    final label = tester.getRect(find.text('New topic'));
    expect(createRect.contains(label.topLeft), isTrue);
    expect(createRect.contains(label.bottomRight), isTrue);
    await tester.tap(drafts);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('recent-draft-new_topic')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    for (final compact in [false, true]) {
      testWidgets(
        'joins ${compact ? 'compact' : 'labeled'} button surfaces in $direction',
        (tester) async {
          await _pump(
            tester,
            direction: direction,
            compact: compact,
            showLabel: !compact,
          );
          final create = find.byKey(TopicCreateButton.buttonKey);
          final drafts = find.byKey(TopicCreateButton.draftsButtonKey);
          final createSurface = tester.getRect(
            find.descendant(of: create, matching: find.byType(Material)),
          );
          final draftsSurface = tester.getRect(
            find.descendant(of: drafts, matching: find.byType(Material)),
          );
          expect(
            direction == TextDirection.ltr
                ? draftsSurface.left - createSurface.right
                : createSurface.left - draftsSurface.right,
            1,
          );
          final createRadius = buttonSurface(tester, of: create).borderRadius;
          final draftsRadius = buttonSurface(tester, of: drafts).borderRadius;
          if (direction == TextDirection.ltr) {
            expect(createRadius.topLeft.x, greaterThan(0));
            expect(createRadius.topRight, Radius.zero);
            expect(draftsRadius.topLeft, Radius.zero);
            expect(draftsRadius.topRight.x, greaterThan(0));
            expect(
              tester.getRect(drafts).left - tester.getRect(create).right,
              1,
            );
          } else {
            expect(createRadius.topRight.x, greaterThan(0));
            expect(createRadius.topLeft, Radius.zero);
            expect(draftsRadius.topRight, Radius.zero);
            expect(draftsRadius.topLeft.x, greaterThan(0));
            expect(
              tester.getRect(create).left - tester.getRect(drafts).right,
              1,
            );
          }
        },
      );
    }
  }

  testWidgets('keeps a standalone create action when there are no drafts', (
    tester,
  ) async {
    final fixture = await _pump(tester, draftCount: 0);
    expect(find.byKey(TopicCreateButton.draftsButtonKey), findsNothing);
    final create = find.byKey(TopicCreateButton.buttonKey);
    final radius = buttonSurface(tester, of: create).borderRadius;
    expect(radius.topLeft.x, greaterThan(0));
    expect(radius.topRight, radius.topLeft);
    await tester.tap(create);
    expect(fixture.createCalls(), 1);
    expect(fixture.api.userDraftRequests, isEmpty);
  });

  testWidgets('focuses loaded drafts and restores the trigger on Escape', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pump(
      tester,
      userDraftGate: gate,
      draftCount: 6,
      userDrafts: [
        _draft,
        for (var i = 1; i < 6; i++)
          UserDraft(
            key: 'new_private_message_$i',
            sequence: i,
            data: ComposerDraft(reply: 'Message body', title: 'Message $i'),
          ),
      ],
    );
    final trigger = find.byKey(TopicCreateButton.draftsButtonKey);
    final triggerFocus = _focusButton(tester, trigger);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Loading drafts…'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    final title = find.descendant(
      of: find.byKey(const ValueKey('recent-draft-new_topic')),
      matching: find.byType(TopicTitle),
    );
    expect(Focus.of(tester.element(title)).hasPrimaryFocus, isTrue);
    expect(tester.widget<DButton>(trigger).expanded, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Message 1'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('View all drafts'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    expect(triggerFocus.hasPrimaryFocus, isTrue);
    expect(tester.widget<DButton>(trigger).expanded, isFalse);
  });

  testWidgets('dismissed loading does not reopen or take focus on completion', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pump(tester, userDraftGate: gate);
    await tester.tap(find.byKey(TopicCreateButton.draftsButtonKey));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Loading drafts…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final createFocus = _focusButton(
      tester,
      find.byKey(TopicCreateButton.buttonKey),
    );
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(createFocus.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final failed in [false, true]) {
    testWidgets(
      'handles an ${failed ? 'unsuccessful' : 'empty'} draft response',
      (tester) async {
        final gate = Completer<void>();
        final fixture = await _pump(
          tester,
          userDraftGate: gate,
          userDrafts: const [],
          compact: true,
          textScale: 2,
        );
        final trigger = find.byKey(TopicCreateButton.draftsButtonKey);
        await tester.tap(trigger);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Loading drafts…'), findsOneWidget);
        if (failed) {
          gate.completeError(StateError('Draft request failed'));
        } else {
          gate.complete();
        }
        await tester.pumpAndSettle();
        if (failed) {
          expect(find.text("Couldn't load drafts."), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        } else {
          expect(trigger, findsNothing);
        }
        await tester.tap(find.byKey(TopicCreateButton.buttonKey));
        expect(fixture.createCalls(), 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

void _expectSmallDButton(
  WidgetTester tester,
  Finder target, {
  required bool iconOnly,
}) {
  final button = tester.widget<DButton>(target);
  final size = tester.getSize(target);
  expect(button.size, DButtonSize.small);
  expect(button.variant, DButtonVariant.primary);
  expect(size.height, DButton.iconOnlyDimensionFor(DButtonSize.small));
  if (iconOnly) {
    expect(size.width, DButton.iconOnlyDimensionFor(DButtonSize.small));
  }
}

typedef _Fixture = ({FakeDiscourseApi api, int Function() createCalls});

Future<_Fixture> _pump(
  WidgetTester tester, {
  bool compact = false,
  bool showLabel = true,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  int draftCount = 1,
  List<UserDraft> userDrafts = const [_draft],
  Completer<void>? userDraftGate,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    name: 'Reader',
    draftCount: draftCount,
  );
  final site = instance('meta.example').copyWith(user: user);
  final api = FakeDiscourseApi(
    user: user,
    totals: const NotificationTotals(),
    userDraftList: userDrafts,
    userDraftGate: userDraftGate,
    feeds: const {'/latest.json': []},
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();

  var createCalls = 0;
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(textDirection: direction, child: child!),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: TopicCreateButton(
              showLabel: showLabel,
              compact: compact,
              onPressed: () => createCalls++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (api: api, createCalls: () => createCalls);
}

FocusNode _focusButton(WidgetTester tester, Finder button) {
  final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
  expect(inkWell, findsOneWidget);
  final focusChild = find
      .descendant(of: inkWell, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  return focus;
}
