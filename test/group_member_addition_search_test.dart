import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/group/group_members_controller.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _group = Group(
  id: 9,
  name: 'support',
  canSeeMembers: true,
  canAdminGroup: true,
);
const _sam = FoundUser(username: 'sam');
const _alice = FoundUser(username: 'alice');
final _field = find.byKey(const ValueKey('add-members-search'));
final _submit = find.byKey(const ValueKey('submit-add-members'));

void main() {
  group('addition search queue', () {
    for (final firstFails in [false, true]) {
      testWidgets('runs only first and newest debounced queries when first '
          '${firstFails ? 'fails' : 'succeeds'}', (tester) async {
        final first = Completer<List<FoundUser>>();
        final newest = Completer<List<FoundUser>>();
        final searches = <String>[];
        final controller = GroupMemberAdditionController(
          searchUsers: (query) {
            searches.add(query);
            return query == 'sam' ? first.future : newest.future;
          },
          addMembers: (_, _) async => const GroupMembershipMutationResult(),
        );
        addTearDown(controller.dispose);

        controller.search(' sam ');
        await tester.pump(const Duration(milliseconds: 249));
        expect(searches, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        expect(searches, ['sam']);
        for (final query in ['al', 'ali', 'alic', 'alice']) {
          controller.search(query);
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(searches, ['sam']);
        expect(controller.searching, isTrue);

        if (firstFails) {
          first.completeError(StateError('stale failure'));
        } else {
          first.complete([_sam]);
        }
        await tester.pump();
        expect(searches, ['sam', 'alice']);
        expect(controller.results, isEmpty);
        expect(controller.error, isNull);
        expect(controller.searching, isTrue);

        newest.complete([_alice]);
        await tester.pump();
        expect(controller.results, [_alice]);
        expect(controller.searching, isFalse);
        expect(controller.error, isNull);
      });
    }

    testWidgets(
      'new input invalidates delivery and queued work before debounce',
      (tester) async {
        final first = Completer<List<FoundUser>>();
        final searches = <String>[];
        final controller = GroupMemberAdditionController(
          searchDebounce: const Duration(milliseconds: 40),
          searchUsers: (query) {
            searches.add(query);
            return query == 'sam' ? first.future : Future.value([_alice]);
          },
          addMembers: (_, _) async => const GroupMembershipMutationResult(),
        );
        addTearDown(controller.dispose);
        controller.search('sam');
        await tester.pump(const Duration(milliseconds: 40));
        controller.search('queued');
        await tester.pump(const Duration(milliseconds: 40));
        controller.search(' alice ');

        first.complete([_sam]);
        await tester.pump();
        expect(searches, ['sam']);
        expect(controller.query, ' alice ');
        expect(controller.results, isEmpty);
        expect(controller.searching, isTrue);
        await tester.pump(const Duration(milliseconds: 39));
        expect(searches, ['sam']);
        await tester.pump(const Duration(milliseconds: 1));
        expect(searches, ['sam', 'alice']);
        expect(controller.results, [_alice]);
        expect(controller.searching, isFalse);
      },
    );

    for (final shortQuery in [' a ', '   ']) {
      testWidgets(
        'short query "$shortQuery" drops queued and current delivery',
        (tester) async {
          final first = Completer<List<FoundUser>>();
          final searches = <String>[];
          final controller = GroupMemberAdditionController(
            searchUsers: (query) {
              searches.add(query);
              return first.future;
            },
            addMembers: (_, _) async => const GroupMembershipMutationResult(),
          );
          addTearDown(controller.dispose);
          controller.search('sam');
          await tester.pump(const Duration(milliseconds: 250));
          controller.search('alice');
          await tester.pump(const Duration(milliseconds: 250));
          controller.search(shortQuery);
          expect(controller.searching, isFalse);
          first.complete([_sam]);
          await tester.pump(const Duration(milliseconds: 250));

          expect(searches, ['sam']);
          expect(controller.results, isEmpty);
          expect(controller.error, isNull);
          expect(controller.searching, isFalse);
        },
      );
    }

    testWidgets('current failure shows localized error and retry recovers', (
      tester,
    ) async {
      final failed = Completer<List<FoundUser>>();
      final controller = GroupMemberAdditionController(
        searchUsers: (query) =>
            query == 'sam' ? failed.future : Future.value([_alice]),
        addMembers: (_, _) async => const GroupMembershipMutationResult(),
      );
      addTearDown(controller.dispose);
      controller.search('sam');
      await tester.pump(const Duration(milliseconds: 250));
      failed.completeError(StateError('offline'));
      await tester.pump();
      expect(controller.error, appL10n.membersCouldNotBeSearchedTryAgain);
      expect(controller.results, isEmpty);
      expect(controller.searching, isFalse);

      controller.search('alice');
      expect(controller.error, isNull);
      expect(controller.searching, isTrue);
      await tester.pump(const Duration(milliseconds: 250));
      expect(controller.results, [_alice]);
      expect(controller.searching, isFalse);
      expect(controller.error, isNull);
    });

    for (final stage in ['debounce', 'queued result', 'queued error']) {
      testWidgets('disposal suppresses $stage and late delivery', (
        tester,
      ) async {
        final pending = Completer<List<FoundUser>>();
        final searches = <String>[];
        var notifications = 0;
        final controller = GroupMemberAdditionController(
          searchUsers: (query) {
            searches.add(query);
            return pending.future;
          },
          addMembers: (_, _) async => const GroupMembershipMutationResult(),
        );
        controller.addListener(() => notifications++);
        controller.search('sam');
        if (stage != 'debounce') {
          await tester.pump(const Duration(milliseconds: 250));
          controller.search('alice');
          await tester.pump(const Duration(milliseconds: 250));
        }
        controller.dispose();
        final before = notifications;
        controller.search('ignored');
        if (stage == 'queued error') {
          pending.completeError(StateError('late failure'));
        } else {
          pending.complete([_sam]);
        }
        await tester.pump(const Duration(milliseconds: 250));

        expect(searches, stage == 'debounce' ? isEmpty : ['sam']);
        expect(notifications, before);
        expect(controller.results, isEmpty);
        expect(controller.error, isNull);
        expect(controller.canSave, isFalse);
      });
    }
  });

  for (final width in [1180.0, 390.0]) {
    for (final duringLookup in [false, true]) {
      testWidgets('Enter cannot select a previous username at width $width '
          '${duringLookup ? 'during lookup' : 'during debounce'}', (
        tester,
      ) async {
        final pending = Completer<List<FoundUser>>();
        await _pump(
          tester,
          width: width,
          searchUsers: (query) async =>
              query == 'sam' ? [_sam] : pending.future,
        );
        await tester.enterText(_field, 'sam');
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expect(find.byKey(const ValueKey('add-user-sam')), findsOneWidget);

        await tester.enterText(_field, 'alice');
        if (duringLookup) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        // No extra frame is required to reject a stale keyboard choice.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(tester.widget<DButton>(_submit).onPressed, isNull);

        await tester.pump(const Duration(milliseconds: 250));
        pending.complete([_alice]);
        await tester.pumpAndSettle();
        await tester.tap(_field.last);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(tester.widget<DButton>(_submit).onPressed, isNotNull);
        expect(find.byKey(const ValueKey('add-user-sam')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'selection and the current email survive search at width $width',
      (tester) async {
        final pending = Completer<List<FoundUser>>();
        List<String>? usernames;
        List<String>? emails;
        await _pump(
          tester,
          width: width,
          searchUsers: (query) async =>
              query == 'sam' ? [_sam] : pending.future,
          onAdd: (selectedUsers, selectedEmails) async {
            usernames = selectedUsers;
            emails = selectedEmails;
            return const GroupMembershipMutationResult();
          },
        );
        await tester.enterText(_field, 'sam');
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('add-user-sam')));
        await tester.pump();

        await tester.enterText(_field, 'member@example.com');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(_submit);
        await tester.pumpAndSettle();
        expect(usernames, ['sam']);
        expect(emails, ['member@example.com']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required Future<List<FoundUser>> Function(String) searchUsers,
  GroupAddMembers? onAdd,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: GroupPage(
          siteUrl: 'https://meta.discourse.org',
          route: GroupRoute.detail(_group.name),
          registry: PluginRegistry.empty,
          data: const GroupPageData(
            detail: GroupDetail(group: _group),
            members: GroupMembersPage(members: [], total: 0),
          ),
          onOpenMember: (_, _) {},
          onSearchUsers: searchUsers,
          onAddMembers:
              onAdd ?? (_, _) async => const GroupMembershipMutationResult(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('add-group-members')));
  await tester.pumpAndSettle();
}
