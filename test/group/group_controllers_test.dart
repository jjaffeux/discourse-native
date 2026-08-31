import 'dart:async';

import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/shell/group/group_manage_controller.dart';
import 'package:discourse_native/src/shell/group/group_members_controller.dart';
import 'package:discourse_native/src/shell/group/group_page_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupMemberAdditionController', () {
    test('ignores stale searches and exposes only the latest result', () async {
      final first = Completer<List<FoundUser>>();
      final second = Completer<List<FoundUser>>();
      final controller = GroupMemberAdditionController(
        searchDebounce: Duration.zero,
        searchUsers: (query) => query == 'sa' ? first.future : second.future,
        addMembers: (_, _) async => const GroupMembershipMutationResult(),
      );
      addTearDown(controller.dispose);

      controller.search('sa');
      await _flushTimers();
      controller.search('lee');
      await _flushTimers();

      first.complete(const [FoundUser(username: 'sam')]);
      await _flushTimers();
      expect(controller.results, isEmpty);
      expect(controller.searching, isTrue);

      second.complete(const [FoundUser(username: 'lee')]);
      await _flushTimers();
      expect(controller.results, const [FoundUser(username: 'lee')]);
      expect(controller.searching, isFalse);
    });

    test('owns member selection and reports skipped additions', () async {
      var skip = true;
      List<String>? submittedUsernames;
      List<String>? submittedEmails;
      final controller = GroupMemberAdditionController(
        searchUsers: (_) async => const [],
        addMembers: (usernames, emails) async {
          submittedUsernames = usernames;
          submittedEmails = emails;
          return GroupMembershipMutationResult(
            skippedUsernames: skip ? const ['sam'] : const [],
          );
        },
      );
      addTearDown(controller.dispose);

      controller.toggleUsername('sam', selected: true);
      controller.toggleEmail('member@example.com', selected: true);
      expect(controller.selectionCount, 2);

      expect(await controller.save(), isFalse);
      expect(controller.error, 'Not added: sam');
      expect(submittedUsernames, ['sam']);
      expect(submittedEmails, ['member@example.com']);

      skip = false;
      expect(await controller.save(), isTrue);
    });
  });

  group('GroupInviteController', () {
    test('normalizes invite input and resolves a returned link', () async {
      String? submittedEmail;
      String? submittedMessage;
      final controller = GroupInviteController(
        siteUrl: 'https://meta.discourse.org',
        createInvite: ({email, customMessage}) async {
          submittedEmail = email;
          submittedMessage = customMessage;
          return const GroupInvite(id: 8, link: '/invites/native');
        },
      );
      addTearDown(controller.dispose);

      controller.message.text = '  hello  ';
      expect(await controller.create(), GroupInviteSubmission.linkCreated);
      expect(submittedEmail, isNull);
      expect(submittedMessage, 'hello');
      expect(controller.link, 'https://meta.discourse.org/invites/native');
    });
  });

  group('GroupManageController', () {
    test('owns form state and serializes subsection-specific updates', () {
      final controller = GroupManageController(
        group: const Group(
          id: 9,
          name: 'support',
          allowMembershipRequests: true,
          associatedGroupIds: [3],
          watchingTags: [GroupTag(name: 'existing')],
        ),
      );
      addTearDown(controller.dispose);

      controller.setAdmission('free');
      controller.setPublicExit(true);
      controller.textController('associated_group_ids').text = '4, nope, 8';
      final membership = controller.buildUpdate(GroupRoute.membership);

      expect(membership.values['public_admission'], isTrue);
      expect(membership.values['allow_membership_requests'], isFalse);
      expect(membership.values['public_exit'], isTrue);
      expect(membership.values['associated_group_ids'], [4, 8]);

      controller.textController('watching_tags').text = ' flutter, native,  ';
      final tags = controller.buildUpdate(GroupRoute.tags);
      expect(tags.values['watching_tags'], ['flutter', 'native']);
      expect(tags.values.keys, unorderedEquals(groupTagKeys));
    });

    test('save invokes the command callback with the current values', () async {
      final controller = GroupManageController(
        group: const Group(id: 9, name: 'support'),
      );
      addTearDown(controller.dispose);
      GroupManageUpdate? submitted;
      controller.textController('full_name').text = 'Support Team';

      await controller.save(
        GroupRoute.profile,
        (update) async => submitted = update,
      );

      expect(submitted?.subsection, GroupRoute.profile);
      expect(submitted?.values['full_name'], 'Support Team');
    });
  });
}

Future<void> _flushTimers() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
