import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
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
            loaded: true,
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
