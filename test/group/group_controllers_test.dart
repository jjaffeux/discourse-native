import 'dart:async';

import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/shell/group/group_manage_controller.dart';
import 'package:discourse_native/src/shell/group/group_members_controller.dart';
import 'package:discourse_native/src/shell/group/group_page_types.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('association capability remains valid on an automatic admin group', () {
    final group = Group.fromWire(const {
      'id': 9,
      'name': 'admins',
      'automatic': true,
      'associated_group_ids': [12],
    }, 'https://forum.example');
    final controller = GroupManageController(
      group: group,
      currentUserAdmin: true,
      currentUserStaff: true,
      subsection: GroupRoute.membership,
    );
    addTearDown(controller.dispose);
    expect(controller.canEditField('associated_group_ids'), isTrue);
    controller.textController('associated_group_ids').text = '22';
    expect(controller.buildUpdate().values['associated_group_ids'], [22]);
  });

  group('GroupMemberFilterController', () {
    test('refreshing the committed filter preserves pending input', () async {
      final original = <String>[];
      final updated = <String>[];
      final controller = GroupMemberFilterController(
        filter: '',
        onFilterChanged: original.add,
        debounceDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.searchController.text = 'sam';
      controller.search('sam');

      controller.update(filter: '', onFilterChanged: updated.add);

      expect(controller.searchController.text, 'sam');
      await _flushTimers();
      expect(original, isEmpty);
      expect(updated, ['sam']);
    });

    test('an external filter replacement cancels the pending draft', () async {
      final searches = <String>[];
      final controller = GroupMemberFilterController(
        filter: '',
        onFilterChanged: searches.add,
        debounceDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.searchController.text = 'old draft';
      controller.search('old draft');

      controller.update(filter: 'restored', onFilterChanged: searches.add);
      await _flushTimers();

      expect(controller.searchController.text, 'restored');
      expect(searches, isEmpty);
    });

    test('the echoed trimmed filter keeps the typed whitespace', () async {
      final searches = <String>[];
      final controller = GroupMemberFilterController(
        filter: '',
        onFilterChanged: searches.add,
        debounceDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.searchController.value = const TextEditingValue(
        text: 'sam ',
        selection: TextSelection.collapsed(offset: 4),
      );
      controller.search('sam ');
      await _flushTimers();
      expect(searches, ['sam']);

      controller.update(filter: 'sam', onFilterChanged: searches.add);

      expect(controller.searchController.text, 'sam ');
      expect(
        controller.searchController.selection,
        const TextSelection.collapsed(offset: 4),
      );
    });

    test('a delayed filter echo keeps keystrokes typed after it', () async {
      final searches = <String>[];
      final controller = GroupMemberFilterController(
        filter: '',
        onFilterChanged: searches.add,
        debounceDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.searchController.text = 'sam';
      controller.search('sam');
      await _flushTimers();
      controller.searchController.value = const TextEditingValue(
        text: 'sam s',
        selection: TextSelection.collapsed(offset: 5),
      );
      controller.search('sam s');

      controller.update(filter: 'sam', onFilterChanged: searches.add);
      expect(controller.searchController.text, 'sam s');
      expect(
        controller.searchController.selection,
        const TextSelection.collapsed(offset: 5),
      );
      await _flushTimers();

      expect(searches, ['sam', 'sam s']);
    });
  });

  group('GroupMemberAdditionController', () {
    test(
      'query changes retire results before a replacement search runs',
      () async {
        final replacement = Completer<List<FoundUser>>();
        final controller = GroupMemberAdditionController(
          searchDebounce: Duration.zero,
          searchUsers: (query) async => query == 'sam'
              ? const [FoundUser(username: 'sam')]
              : replacement.future,
          addMembers: (_, _) async => const GroupMembershipMutationResult(),
        );
        addTearDown(controller.dispose);
        controller.search('sam');
        await _flushTimers();
        controller.toggleUsername('sam', selected: true);
        controller.toggleEmail('selected@example.com', selected: true);

        controller.search('alice');
        expect(controller.results, isEmpty);
        expect(controller.searching, isTrue);
        expect(controller.selectedUsernames, {'sam'});
        expect(controller.selectedEmails, {'selected@example.com'});
        await _flushTimers();
        expect(controller.results, isEmpty);
        replacement.complete(const [FoundUser(username: 'alice')]);
        await _flushTimers();
        expect(controller.results, const [FoundUser(username: 'alice')]);
        expect(controller.searching, isFalse);
      },
    );

    test('a failed search clears progress and allows a retry', () async {
      var attempts = 0;
      final controller = GroupMemberAdditionController(
        searchDebounce: Duration.zero,
        searchUsers: (_) async {
          if (++attempts == 1) throw StateError('offline');
          return const [FoundUser(username: 'sam')];
        },
        addMembers: (_, _) async => const GroupMembershipMutationResult(),
      );
      addTearDown(controller.dispose);

      controller.search('sam');
      await _flushTimers();
      expect(controller.searching, isFalse);
      expect(controller.results, isEmpty);
      expect(controller.error, 'Members could not be searched. Try again.');

      controller.search('sam');
      await _flushTimers();
      expect(controller.error, isNull);
      expect(controller.results, const [FoundUser(username: 'sam')]);
      expect(controller.searching, isFalse);
    });

    test('a stale search error does not finish a newer search', () async {
      final first = Completer<List<FoundUser>>();
      final second = Completer<List<FoundUser>>();
      final controller = GroupMemberAdditionController(
        searchDebounce: Duration.zero,
        searchUsers: (query) => query == 'sam' ? first.future : second.future,
        addMembers: (_, _) async => const GroupMembershipMutationResult(),
      );
      addTearDown(controller.dispose);
      controller.search('sam');
      await _flushTimers();
      controller.search('lee');
      await _flushTimers();

      first.completeError(StateError('old request failed'));
      await _flushTimers();
      expect(controller.searching, isTrue);
      expect(controller.error, isNull);
      second.complete(const [FoundUser(username: 'lee')]);
      await _flushTimers();
      expect(controller.results, const [FoundUser(username: 'lee')]);
      expect(controller.searching, isFalse);
    });

    test('a rejected save retains selection and allows a retry', () async {
      var attempts = 0;
      final controller = GroupMemberAdditionController(
        searchUsers: (_) async => const [],
        addMembers: (usernames, emails) async {
          expect(usernames, ['sam']);
          expect(emails, ['member@example.com']);
          if (++attempts == 1) throw StateError('offline');
          return const GroupMembershipMutationResult();
        },
      );
      addTearDown(controller.dispose);
      controller.toggleUsername('sam', selected: true);
      controller.toggleEmail('member@example.com', selected: true);

      expect(await controller.save(), isFalse);
      expect(controller.saving, isFalse);
      expect(controller.canSave, isTrue);
      expect(controller.error, 'The selected members could not be added.');
      expect(await controller.save(), isTrue);
      expect(attempts, 2);
    });

    test(
      'a save uses the selection accepted before progress is announced',
      () async {
        List<String>? submitted;
        final controller = GroupMemberAdditionController(
          searchUsers: (_) async => const [],
          addMembers: (usernames, _) async {
            submitted = usernames;
            return const GroupMembershipMutationResult();
          },
        );
        addTearDown(controller.dispose);
        controller.toggleUsername('sam', selected: true);
        var edited = false;
        controller.addListener(() {
          if (!controller.saving || edited) return;
          edited = true;
          controller.toggleUsername('lee', selected: true);
        });

        expect(await controller.save(), isTrue);
        expect(submitted, ['sam']);
      },
    );

    test('retained member commands stop after disposal', () async {
      var calls = 0;
      final controller = GroupMemberAdditionController(
        searchDebounce: Duration.zero,
        searchUsers: (_) async {
          calls++;
          return const [];
        },
        addMembers: (_, _) async {
          calls++;
          return const GroupMembershipMutationResult();
        },
      );
      controller.toggleUsername('sam', selected: true);
      controller.search('sam');
      controller.dispose();

      controller.search('lee');
      controller.toggleUsername('lee', selected: true);
      controller.toggleEmail('member@example.com', selected: true);
      expect(await controller.save(), isFalse);
      await _flushTimers();
      expect(controller.canSave, isFalse);
      expect(calls, 0);
    });

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
    test('a failed invitation clears progress and allows a retry', () async {
      var attempts = 0;
      final controller = GroupInviteController(
        siteUrl: 'https://meta.discourse.org',
        createInvite: ({email, customMessage}) async {
          expect(email, 'member@example.com');
          expect(customMessage, 'Welcome');
          if (++attempts == 1) throw StateError('offline');
          return const GroupInvite(id: 8);
        },
      );
      addTearDown(controller.dispose);
      controller.email.text = ' member@example.com ';
      controller.message.text = ' Welcome ';

      expect(await controller.create(), GroupInviteSubmission.failed);
      expect(controller.saving, isFalse);
      expect(controller.error, 'The invitation could not be created.');
      expect(await controller.create(), GroupInviteSubmission.sent);
      expect(controller.error, isNull);
      expect(attempts, 2);
    });

    test(
      'an invite uses the input accepted before progress is announced',
      () async {
        String? submitted;
        final controller = GroupInviteController(
          siteUrl: 'https://meta.discourse.org',
          createInvite: ({email, customMessage}) async {
            submitted = email;
            return const GroupInvite(id: 8);
          },
        );
        addTearDown(controller.dispose);
        controller.email.text = 'first@example.com';
        var edited = false;
        controller.addListener(() {
          if (!controller.saving || edited) return;
          edited = true;
          controller.email.text = 'second@example.com';
        });

        expect(await controller.create(), GroupInviteSubmission.sent);
        expect(submitted, 'first@example.com');
      },
    );

    test('a retained invite command stops after disposal', () async {
      var calls = 0;
      final controller = GroupInviteController(
        siteUrl: 'https://meta.discourse.org',
        createInvite: ({email, customMessage}) async {
          calls++;
          return const GroupInvite(id: 8);
        },
      );
      controller.dispose();

      expect(await controller.create(), GroupInviteSubmission.failed);
      expect(calls, 0);
    });

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
    for (final invalid in ['0', '-1', '12,,35', '12,', '9223372036854775808']) {
      test('invalid category IDs $invalid stay local', () async {
        var writes = 0;
        final controller = GroupManageController(
          group: const Group(
            id: 9,
            name: 'support',
            watchingCategoryIds: [12, 34],
          ),
          subsection: GroupRoute.categories,
          onSubmit: (_) async {
            writes++;
            return true;
          },
        );
        addTearDown(controller.dispose);
        controller.textController('watching_category_ids').text = invalid;
        expect(await controller.submit(), isFalse);
        expect(writes, 0);
        expect(
          controller.textController('watching_category_ids').text,
          invalid,
        );
        expect(controller.snapshot.fieldErrors, {
          'watching_category_ids':
              'Enter positive numeric IDs, separated by commas.',
        });
        controller.textController('watching_category_ids').text = ' 12, 35 ';
        expect(controller.snapshot.fieldErrors, isEmpty);
        expect(await controller.submit(), isTrue);
        expect(controller.buildUpdate().values['watching_category_ids'], [
          12,
          35,
        ]);
        controller.textController('watching_category_ids').text = '  ';
        expect(await controller.submit(), isTrue);
        expect(
          controller.buildUpdate().values['watching_category_ids'],
          isEmpty,
        );
      });
    }
    for (final (admin, capability) in [(false, true), (true, false)]) {
      test(
        'withheld associated IDs do not block allowed membership saves admin=$admin capability=$capability',
        () async {
          GroupManageUpdate? saved;
          final controller = GroupManageController(
            group: Group(
              id: 9,
              name: 'support',
              canAssociateGroups: capability,
            ),
            currentUserAdmin: admin,
            subsection: GroupRoute.membership,
            onSubmit: (update) async {
              saved = update;
              return true;
            },
          );
          addTearDown(controller.dispose);
          controller.textController('associated_group_ids').text = 'oops';
          controller.setPublicExit(true);
          expect(await controller.submit(), isTrue);
          expect(controller.snapshot.fieldErrors, isEmpty);
          expect(saved!.values, isNot(contains('associated_group_ids')));
          expect(saved!.values['public_exit'], isTrue);
        },
      );
    }
    for (final invalid in ['587x', '58.7', '', '9223372036854775808']) {
      test('SMTP port $invalid cannot submit null while enabled', () async {
        var writes = 0;
        final controller = GroupManageController(
          group: const Group(
            id: 9,
            name: 'support',
            smtpEnabled: true,
            smtpPort: 587,
          ),
          currentUserAdmin: true,
          currentUserStaff: true,
          subsection: GroupRoute.email,
          onSubmit: (_) async {
            writes++;
            return true;
          },
        );
        addTearDown(controller.dispose);
        controller.textController('smtp_port').text = invalid;
        expect(await controller.submit(), isFalse);
        expect(writes, 0);
        expect(controller.textController('smtp_port').text, invalid);
        expect(
          controller.snapshot.fieldErrors['smtp_port'],
          'Enter a valid whole number.',
        );
        controller.textController('smtp_port').text = ' 465 ';
        expect(controller.snapshot.fieldErrors, isEmpty);
        expect(await controller.submit(), isTrue);
        expect(writes, 1);
        expect(controller.buildUpdate().values['smtp_port'], 465);
      });
    }

    test('deliberate SMTP disable discards a malformed port', () async {
      final controller = GroupManageController(
        group: const Group(
          id: 9,
          name: 'support',
          smtpEnabled: true,
          smtpPort: 587,
        ),
        currentUserAdmin: true,
        subsection: GroupRoute.email,
        onSubmit: (_) async => true,
      );
      addTearDown(controller.dispose);
      controller.textController('smtp_port').text = '587x';
      expect(controller.validate(), isFalse);
      controller.setSmtpEnabled(false);
      expect(controller.snapshot.fieldErrors, isEmpty);
      expect(await controller.submit(), isTrue);
      expect(controller.buildUpdate().values['smtp_enabled'], 'false');
    });

    for (final staff in [false, true]) {
      test('membership setting permissions staff=$staff', () {
        final controller = GroupManageController(
          group: const Group(id: 9, name: 'support'),
          currentUserStaff: staff,
          subsection: GroupRoute.membership,
          onSubmit: (_) async => true,
        );
        addTearDown(controller.dispose);
        controller.setVisibility(1);
        controller.setMembersVisibility(2);
        controller.textController('grant_trust_level').text = '3';
        final values = controller.buildUpdate().values;
        for (final field in [
          'visibility_level',
          'members_visibility_level',
          'grant_trust_level',
        ]) {
          expect(values.containsKey(field), staff);
        }
        expect(controller.snapshot.dirty, staff);
        controller.setPublicExit(true);
        expect(controller.snapshot.canSubmit, isTrue);
        expect(controller.buildUpdate().values['public_exit'], isTrue);
      });
    }
    for (final (staff, automatic) in [
      (false, false),
      (true, false),
      (true, true),
    ]) {
      test(
        'interaction setting permissions staff=$staff automatic=$automatic',
        () {
          final controller = GroupManageController(
            group: Group(id: 9, name: 'support', automatic: automatic),
            currentUserStaff: staff,
            subsection: GroupRoute.interaction,
            onSubmit: (_) async => true,
          );
          addTearDown(controller.dispose);
          controller.setPublishReadState(true);
          controller.textController('incoming_email').text = 'new@example.com';
          final editable = staff && !automatic;
          expect(
            controller.buildUpdate().values.containsKey('publish_read_state'),
            editable,
          );
          expect(
            controller.buildUpdate().values.containsKey('incoming_email'),
            editable,
          );
          expect(controller.snapshot.dirty, editable);
          controller.setMentionable(1);
          controller.setMessageable(2);
          controller.setDefaultNotification(3);
          expect(controller.snapshot.canSubmit, isTrue);
          expect(
            controller.buildUpdate().values,
            containsPair('mentionable_level', 1),
          );
          expect(
            controller.buildUpdate().values,
            containsPair('messageable_level', 2),
          );
          expect(
            controller.buildUpdate().values,
            containsPair('default_notification_level', 3),
          );
        },
      );
    }

    for (final (staff, automatic, editable) in [
      (
        false,
        false,
        {'full_name', 'bio_raw', 'flair_icon', 'flair_bg_color', 'flair_color'},
      ),
      (
        true,
        false,
        {
          'name',
          'full_name',
          'title',
          'bio_raw',
          'flair_icon',
          'flair_bg_color',
          'flair_color',
        },
      ),
      (true, true, {'bio_raw', 'flair_icon', 'flair_bg_color', 'flair_color'}),
    ]) {
      test('profile permissions staff=$staff automatic=$automatic', () {
        final controller = GroupManageController(
          group: Group(id: 9, name: 'support', automatic: automatic),
          currentUserStaff: staff,
          onSubmit: (_) async => true,
        );
        addTearDown(controller.dispose);
        expect(controller.buildUpdate().values.keys, unorderedEquals(editable));
        for (final key in ['name', 'full_name', 'title']) {
          if (!editable.contains(key)) {
            expect(controller.canEditField(key), isFalse);
            controller.textController(key).clear();
          }
        }
        expect(controller.validate(), isTrue);
        expect(controller.snapshot.dirty, isFalse);
        expect(controller.snapshot.canSubmit, isFalse);
        controller.textController('bio_raw').text = 'Updated biography';
        expect(controller.snapshot.dirty, isTrue);
      });
    }

    test(
      'SMTP passwords preserve whitespace while address fields trim',
      () async {
        Map<String, Object?>? submitted;
        final controller = GroupManageController(
          group: const Group(id: 9, name: 'support'),
          subsection: GroupRoute.email,
          currentUserAdmin: true,
          onSubmit: (update) async {
            submitted = update.values;
            return true;
          },
        );
        addTearDown(controller.dispose);
        controller.textController('smtp_server').text = ' smtp.example.com ';
        controller.textController('email_username').text = ' mailbox ';
        controller.textController('email_from_alias').text = ' Support ';
        const syntheticPassword = ' synthetic smtp password ';
        controller.textController('email_password').text = syntheticPassword;

        expect(await controller.submit(), isTrue);
        expect(submitted?['email_password'], syntheticPassword);
        expect(submitted?['smtp_server'], 'smtp.example.com');
        expect(submitted?['email_username'], 'mailbox');
        expect(submitted?['email_from_alias'], 'Support');
      },
    );

    test('unchanged blank SMTP passwords stay omitted', () {
      final controller = GroupManageController(
        group: const Group(id: 9, name: 'support'),
        subsection: GroupRoute.email,
        currentUserAdmin: true,
      );
      addTearDown(controller.dispose);
      expect(
        controller.buildUpdate().values,
        isNot(contains('email_password')),
      );
      controller.textController('email_password').text = '   ';
      expect(controller.buildUpdate().values['email_password'], '   ');
      expect(controller.snapshot.dirty, isTrue);
      controller.textController('email_password').clear();
      expect(
        controller.buildUpdate().values,
        isNot(contains('email_password')),
      );
      expect(controller.snapshot.dirty, isFalse);
    });

    test('a retained management command stops after disposal', () async {
      var calls = 0;
      final controller = GroupManageController(
        group: const Group(id: 9, name: 'support'),
        onSubmit: (_) async {
          calls++;
          return true;
        },
      );
      controller.textController('full_name').text = 'Support';
      controller.dispose();

      expect(await controller.submit(), isFalse);
      expect(calls, 0);
    });

    test('owns dirty state and serializes subsection-specific updates', () {
      final controller = GroupManageController(
        group: const Group(
          id: 9,
          name: 'support',
          allowMembershipRequests: true,
          associatedGroupIds: [3],
          canAssociateGroups: true,
          mutedCategoryIds: [5],
          watchingTags: [GroupTag(name: 'existing')],
        ),
        subsection: GroupRoute.membership,
        currentUserAdmin: true,
      );
      addTearDown(controller.dispose);

      expect(controller.snapshot.dirty, isFalse);
      controller.setAdmission('free');
      controller.setPublicExit(true);
      controller.textController('associated_group_ids').text = '4, nope, 8';
      final membership = controller.buildUpdate();

      expect(controller.snapshot.dirty, isTrue);
      expect(membership.values['public_admission'], isTrue);
      expect(membership.values['allow_membership_requests'], isFalse);
      expect(membership.values['public_exit'], isTrue);
      expect(membership.values['associated_group_ids'], [4, 8]);

      controller.textController('watching_tags').text = ' flutter, native,  ';
      final tags = controller.buildUpdate(GroupRoute.tags);
      expect(tags.values['watching_tags'], ['flutter', 'native']);
      // Every tag level goes, so an emptied one is cleared; the category
      // default the group holds goes back unchanged beside them.
      expect(
        tags.values.keys,
        unorderedEquals([...groupTagKeys, 'muted_category_ids']),
      );
      expect(tags.values['muted_category_ids'], [5]);
    });

    test('every subsection sends back the notification defaults it holds', () {
      final controller = GroupManageController(
        group: const Group(
          id: 9,
          name: 'support',
          watchingCategoryIds: [3],
          mutedCategoryIds: [5, 6],
          trackingTags: [GroupTag(name: 'billing')],
        ),
      );
      addTearDown(controller.dispose);

      Map<String, Object?> defaultsIn(String subsection) {
        final values = controller.buildUpdate(subsection).values;
        return {
          for (final key in [...groupCategoryKeys, ...groupTagKeys])
            if (values.containsKey(key)) key: values[key],
        };
      }

      // Core reads a list a save leaves out as empty and counts each default
      // held there as one to delete, refusing the save while members hold
      // it. An empty list would delete defaults the payload may not have
      // shown, so only the held ones are sent.
      const held = {
        'watching_category_ids': [3],
        'muted_category_ids': [5, 6],
        'tracking_tags': ['billing'],
      };
      for (final subsection in [
        GroupRoute.profile,
        GroupRoute.membership,
        GroupRoute.interaction,
        GroupRoute.email,
      ]) {
        expect(defaultsIn(subsection), held, reason: subsection);
      }
      expect(defaultsIn(GroupRoute.categories), {
        for (final key in groupCategoryKeys) key: held[key] ?? const <int>[],
        'tracking_tags': ['billing'],
      });
      expect(defaultsIn(GroupRoute.tags), {
        for (final key in groupTagKeys) key: held[key] ?? const <String>[],
        'watching_category_ids': [3],
        'muted_category_ids': [5, 6],
      });
      expect(controller.snapshot.dirty, isFalse);
    });

    test('serializes the SMTP switch as the string the server compares', () {
      final controller = GroupManageController(
        group: const Group(
          id: 9,
          name: 'support',
          smtpEnabled: true,
          smtpServer: 'smtp.example.com',
          smtpPort: 587,
          emailUsername: 'support@example.com',
        ),
        subsection: GroupRoute.email,
        currentUserAdmin: true,
      );
      addTearDown(controller.dispose);

      expect(controller.buildUpdate().values['smtp_enabled'], 'true');

      // GroupsController clears the stored SMTP settings only for
      // `smtp_enabled == "false"`, and Group#record_email_setting_changes!
      // then re-enables SMTP whenever those settings are still present. A
      // JSON false therefore leaves SMTP switched on.
      controller.setSmtpEnabled(false);
      final disabled = controller.buildUpdate();
      expect(controller.snapshot.dirty, isTrue);
      expect(disabled.values['smtp_enabled'], 'false');
    });

    for (final (staff, admin, automatic) in [
      (false, false, false),
      (true, false, false),
      (true, true, true),
    ]) {
      test('SMTP ignores forbidden edits staff=$staff admin=$admin '
          'automatic=$automatic', () async {
        Map<String, Object?>? submitted;
        final controller = GroupManageController(
          group: Group(id: 9, name: 'support', automatic: automatic),
          subsection: GroupRoute.email,
          currentUserStaff: staff,
          currentUserAdmin: admin,
          onSubmit: (update) async {
            submitted = update.values;
            return true;
          },
        );
        addTearDown(controller.dispose);
        for (final key in [
          'smtp_server',
          'smtp_port',
          'smtp_ssl_mode',
          'email_username',
          'email_password',
          'email_from_alias',
        ]) {
          expect(controller.canEditField(key), isFalse);
          controller.textController(key).text = 'changed';
        }
        expect(controller.canEditField('smtp_enabled'), isFalse);
        expect(
          controller.canEditField('allow_unknown_sender_topic_replies'),
          isFalse,
        );
        controller.setSmtpEnabled(true);
        controller.setAllowUnknownSenderReplies(true);
        expect(controller.snapshot.dirty, isFalse);
        expect(controller.snapshot.canSubmit, isFalse);
        expect(controller.buildUpdate().values, isEmpty);
        expect(await controller.submit(), isTrue);
        expect(submitted, isEmpty);
      });
    }

    test('validation rejects an empty group name before submission', () async {
      var submissions = 0;
      final controller = GroupManageController(
        group: const Group(id: 9, name: 'support'),
        currentUserStaff: true,
        onSubmit: (_) async {
          submissions += 1;
          return true;
        },
      );
      addTearDown(controller.dispose);

      controller.textController('name').text = '  ';
      expect(await controller.submit(), isFalse);
      expect(submissions, 0);
      expect(controller.snapshot.fieldErrors, {'name': 'Enter a group name.'});

      controller.textController('name').text = 'community-support';
      expect(controller.snapshot.fieldErrors, isEmpty);
    });

    test(
      'reports progress and accepts the submitted values on success',
      () async {
        final completion = Completer<bool>();
        GroupManageUpdate? submitted;
        final controller = GroupManageController(
          group: const Group(id: 9, name: 'support'),
          onSubmit: (update) {
            submitted = update;
            return completion.future;
          },
        );
        addTearDown(controller.dispose);
        controller.textController('full_name').text = 'Support Team';

        final save = controller.submit();
        expect(controller.snapshot.submitting, isTrue);
        expect(controller.snapshot.canSubmit, isFalse);
        expect(submitted?.values['full_name'], 'Support Team');

        completion.complete(true);
        expect(await save, isTrue);
        expect(controller.snapshot.submitting, isFalse);
        expect(controller.snapshot.dirty, isFalse);
        expect(controller.snapshot.error, isNull);
      },
    );

    test('maps thrown submission failures and keeps the form dirty', () async {
      final controller = GroupManageController(
        group: const Group(id: 9, name: 'support'),
        onSubmit: (_) async => throw StateError('offline'),
        errorMapper: (error) => 'Mapped ${error.runtimeType}',
      );
      addTearDown(controller.dispose);
      controller.textController('full_name').text = 'Support Team';

      expect(await controller.submit(), isFalse);
      expect(controller.snapshot.submitting, isFalse);
      expect(controller.snapshot.dirty, isTrue);
      expect(controller.snapshot.error, 'Mapped StateError');
    });

    test(
      'uses the save failure message when the command rejects the update',
      () async {
        final controller = GroupManageController(
          group: const Group(id: 9, name: 'support'),
          onSubmit: (_) async => false,
        );
        addTearDown(controller.dispose);
        controller.textController('full_name').text = 'Support Team';

        expect(await controller.submit(), isFalse);
        expect(controller.snapshot.error, "Couldn't save that group change.");
      },
    );

    test(
      'stale failure does not overwrite edits made during submission',
      () async {
        final completion = Completer<bool>();
        final controller = GroupManageController(
          group: const Group(id: 9, name: 'support'),
          onSubmit: (_) => completion.future,
        );
        addTearDown(controller.dispose);
        controller.textController('full_name').text = 'First value';

        final save = controller.submit();
        controller.textController('full_name').text = 'Newer value';
        completion.complete(false);

        expect(await save, isFalse);
        expect(controller.snapshot.error, isNull);
        expect(controller.snapshot.dirty, isTrue);
        expect(controller.buildUpdate().values['full_name'], 'Newer value');
      },
    );
  });
}

Future<void> _flushTimers() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
