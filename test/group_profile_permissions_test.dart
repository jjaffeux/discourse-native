import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/groups_api.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final (staff, admin, automatic, smtpEnabled) in [
    (false, false, false, true),
    (true, false, false, true),
    (true, true, true, true),
    (true, true, false, false),
  ]) {
    testWidgets('SMTP settings unavailable staff=$staff admin=$admin '
        'automatic=$automatic siteSMTP=$smtpEnabled', (tester) async {
      final server = _GroupServer(
        staff: staff,
        admin: admin,
        automatic: automatic,
        smtpEnabled: smtpEnabled,
        subsection: GroupRoute.email,
      );
      addTearDown(server.transport.close);
      await server.pump(tester);
      expect(find.text('Email'), findsNothing);
      expect(_field('smtp_server'), findsNothing);
      expect(find.byKey(const ValueKey('save-group-email')), findsNothing);
      await tester.enterText(_field('bio_raw'), 'Still permitted biography');
      await tester.pump();
      await server.save(tester, subsection: GroupRoute.profile);
      expect(server.writes.single, isNot(contains('smtp_server')));
      expect(server.writes.single, isNot(contains('email_password')));
      expect(server.group['smtp_server'], 'smtp.original.example');
      expect(server.group['bio_raw'], 'Still permitted biography');
      await server.pump(tester);
      expect(_field('smtp_server'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('admin custom SMTP settings save and reload', (tester) async {
    final server = _GroupServer(
      staff: true,
      admin: true,
      automatic: false,
      smtpEnabled: true,
      subsection: GroupRoute.email,
    );
    addTearDown(server.transport.close);
    await server.pump(tester);
    expect(find.text('Email'), findsNWidgets(2));
    const syntheticPassword = ' synthetic mailbox password ';
    await tester.enterText(_field('smtp_server'), ' smtp.changed.example ');
    await tester.enterText(_field('smtp_port'), '465');
    await tester.enterText(_field('smtp_ssl_mode'), '1');
    await tester.enterText(_field('email_username'), ' changed-user ');
    await tester.enterText(_field('email_password'), syntheticPassword);
    await tester.enterText(_field('email_from_alias'), '');
    final unknown = find.widgetWithText(
      DSwitchTile,
      'Allow replies from unknown senders',
    );
    await tester.ensureVisible(unknown);
    await tester.tap(unknown);
    await tester.pump();
    await server.save(tester);
    expect(
      server.writes.single,
      containsPair('smtp_server', 'smtp.changed.example'),
    );
    expect(server.writes.single, containsPair('smtp_port', 465));
    expect(server.writes.single, containsPair('smtp_ssl_mode', 1));
    expect(
      server.writes.single,
      containsPair('email_username', 'changed-user'),
    );
    expect(
      server.writes.single,
      containsPair('email_password', syntheticPassword),
    );
    expect(server.writes.single, containsPair('email_from_alias', ''));
    expect(
      server.writes.single,
      containsPair('allow_unknown_sender_topic_replies', true),
    );
    await server.pump(tester);
    expect(
      tester.widget<DInput>(_field('smtp_server')).controller!.text,
      'smtp.changed.example',
    );
    expect(tester.widget<DInput>(_field('smtp_port')).controller!.text, '465');
    expect(
      tester.widget<DInput>(_field('email_password')).controller!.text,
      '',
    );
    expect(
      tester.widget<DInput>(_field('email_from_alias')).controller!.text,
      '',
    );
    expect(tester.widget<DSwitchTile>(unknown).value, isTrue);
    final enabled = find.widgetWithText(DSwitchTile, 'Enable SMTP');
    await tester.ensureVisible(enabled);
    await tester.tap(enabled);
    await tester.pump();
    await server.save(tester);
    expect(server.writes.last['smtp_enabled'], 'false');
    expect(server.writes.last, isNot(contains('email_password')));
    await server.pump(tester);
    expect(tester.widget<DSwitchTile>(enabled).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final (staff, automatic, field) in [
    (false, false, 'name'),
    (false, false, 'title'),
    (true, true, 'full_name'),
    (true, true, 'title'),
    (true, true, 'name'),
  ]) {
    testWidgets('profile restricts $field staff=$staff automatic=$automatic', (
      tester,
    ) async {
      final server = _GroupServer(staff: staff, automatic: automatic);
      addTearDown(server.transport.close);
      await server.pump(tester);
      expect(tester.widget<DInput>(_field(field)).enabled, isFalse);
      final original = server.group[field];
      // Even retained/programmatic edits must not become a saveable change
      // or leak an ignored identity field into an otherwise permitted save.
      tester.widget<DInput>(_field(field)).controller!.text = 'Updated value';
      await tester.pump();
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('save-group-profile')))
            .onPressed,
        isNull,
      );
      await tester.enterText(_field('bio_raw'), 'Updated biography');
      await tester.enterText(_field('flair_icon'), 'star');
      await tester.pump();
      await server.save(tester);
      expect(server.writes, hasLength(1));
      expect(server.writes.single, isNot(contains(field)));
      expect(server.group[field], original);
      expect(server.group['bio_raw'], 'Updated biography');
      expect(server.group['flair_icon'], 'star');
      await server.pump(tester);
      expect(tester.widget<DInput>(_field(field)).controller!.text, original);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (staff, field) in [
    (false, 'full_name'),
    (true, 'name'),
    (true, 'full_name'),
    (true, 'title'),
  ]) {
    testWidgets('custom profile saves $field staff=$staff', (tester) async {
      final server = _GroupServer(staff: staff, automatic: false);
      addTearDown(server.transport.close);
      await server.pump(tester);
      expect(tester.widget<DInput>(_field(field)).enabled, isTrue);
      const value = 'updated-value';
      await tester.enterText(_field(field), value);
      await tester.pump();
      await server.save(tester);
      expect(server.writes.single[field], value);
      expect(server.group[field], value);
      await server.pump(tester);
      expect(tester.widget<DInput>(_field(field)).controller!.text, value);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a changed staff capability rebinds profile permissions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final staff = ValueNotifier(true);
    addTearDown(staff.dispose);
    Map<String, Object?>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: staff,
            builder: (_, isStaff, _) => GroupPage(
              siteUrl: 'https://forum.example',
              route: GroupRoute.detail(
                'support',
                section: GroupRoute.manage,
                subsection: GroupRoute.profile,
              ),
              registry: PluginRegistry.empty,
              data: GroupPageData(
                detail: const GroupDetail(
                  group: Group(id: 9, name: 'support', canAdminGroup: true),
                ),
                loaded: true,
                currentUserStaff: isStaff,
              ),
              onOpenMember: (_, _) {},
              onSaveManage: (update) async {
                submitted = update.values;
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(_field('name'), 'staff-draft');
    staff.value = false;
    await tester.pump();
    expect(tester.widget<DInput>(_field('name')).enabled, isFalse);
    expect(tester.widget<DInput>(_field('title')).enabled, isFalse);
    await tester.enterText(_field('bio_raw'), 'Owner biography');
    await tester.pump();
    final save = find.byKey(const ValueKey('save-group-profile'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pump();
    expect(submitted, isNot(contains('name')));
    expect(submitted, isNot(contains('title')));
    expect(submitted?['bio_raw'], 'Owner biography');
    expect(tester.takeException(), isNull);
  });

  for (final (subsection, staff, automatic, field, label, value) in [
    (
      GroupRoute.membership,
      false,
      false,
      'visibility_level',
      'Group visibility',
      1,
    ),
    (
      GroupRoute.membership,
      false,
      false,
      'members_visibility_level',
      'Member-list visibility',
      1,
    ),
    (GroupRoute.membership, false, false, 'grant_trust_level', '', 2),
    (GroupRoute.interaction, false, false, 'publish_read_state', '', true),
    (
      GroupRoute.interaction,
      false,
      false,
      'incoming_email',
      '',
      'new@example.com',
    ),
    (GroupRoute.interaction, true, true, 'publish_read_state', '', true),
    (
      GroupRoute.interaction,
      true,
      true,
      'incoming_email',
      '',
      'new@example.com',
    ),
  ]) {
    testWidgets('setting restricts $field staff=$staff automatic=$automatic', (
      tester,
    ) async {
      final server = _GroupServer(
        staff: staff,
        automatic: automatic,
        subsection: subsection,
      );
      addTearDown(server.transport.close);
      await server.pump(tester);
      final original = server.group[field];
      if (label.isNotEmpty) {
        final select = _level(label);
        expect(tester.widget<DSelect<int>>(select).enabled, isFalse);
        tester.widget<DSelect<int>>(select).onChanged?.call(value as int);
      } else if (value is bool) {
        expect(tester.widget<DSwitchTile>(_publishReadState).enabled, isFalse);
        expect(tester.widget<DSwitchTile>(_publishReadState).onChanged, isNull);
      } else {
        final input = tester.widget<DInput>(_field(field));
        expect(input.enabled, isFalse);
        input.controller!.text = value.toString();
      }
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DButton>(find.byKey(ValueKey('save-group-$subsection')))
            .onPressed,
        isNull,
      );
      if (subsection == GroupRoute.membership) {
        await tester.tap(find.widgetWithText(DSwitchTile, 'Members can leave'));
      } else {
        await _chooseLevel(
          tester,
          'Default notification level',
          'Group owners',
        );
      }
      await tester.pumpAndSettle();
      await server.save(tester);
      expect(server.writes, hasLength(1));
      expect(server.writes.single, isNot(contains(field)));
      expect(server.group[field], original);
      expect(
        server.group[subsection == GroupRoute.membership
            ? 'public_exit'
            : 'default_notification_level'],
        subsection == GroupRoute.membership ? true : 3,
      );
      await server.pump(tester);
      if (label.isNotEmpty) {
        expect(tester.widget<DSelect<int>>(_level(label)).value, original);
      } else if (value is bool) {
        expect(tester.widget<DSwitchTile>(_publishReadState).value, original);
      } else {
        expect(
          tester.widget<DInput>(_field(field)).controller!.text,
          original.toString(),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final (subsection, field, label, value) in [
    (GroupRoute.membership, 'visibility_level', 'Group visibility', 1),
    (
      GroupRoute.membership,
      'members_visibility_level',
      'Member-list visibility',
      1,
    ),
    (GroupRoute.membership, 'grant_trust_level', '', 2),
    (GroupRoute.interaction, 'publish_read_state', '', true),
    (GroupRoute.interaction, 'incoming_email', '', 'new@example.com'),
  ]) {
    testWidgets('staff custom setting saves $field', (tester) async {
      final server = _GroupServer(
        staff: true,
        automatic: false,
        subsection: subsection,
      );
      addTearDown(server.transport.close);
      await server.pump(tester);
      if (label.isNotEmpty) {
        expect(tester.widget<DSelect<int>>(_level(label)).enabled, isTrue);
        await _chooseLevel(tester, label, 'Logged-in users');
      } else if (value is bool) {
        await tester.tap(_publishReadState);
      } else {
        expect(tester.widget<DInput>(_field(field)).enabled, isTrue);
        await tester.enterText(_field(field), value.toString());
      }
      await tester.pumpAndSettle();
      await server.save(tester);
      expect(server.writes.single[field], value);
      expect(server.group[field], value);
      await server.pump(tester);
      if (label.isNotEmpty) {
        expect(tester.widget<DSelect<int>>(_level(label)).value, value);
      } else if (value is bool) {
        expect(tester.widget<DSwitchTile>(_publishReadState).value, value);
      } else {
        expect(
          tester.widget<DInput>(_field(field)).controller!.text,
          value.toString(),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _chooseLevel(
  WidgetTester tester,
  String label,
  String option,
) async {
  final select = _level(label);
  await tester.ensureVisible(select);
  await tester.tap(select);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Finder _field(String name) => find.byKey(ValueKey('group-field-$name'));
Finder _level(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is DSelect<int> &&
      widget.label is Text &&
      (widget.label! as Text).data == label,
);
Finder get _publishReadState =>
    find.widgetWithText(DSwitchTile, 'Publish read state');

class _GroupServer {
  _GroupServer({
    required this.staff,
    required this.automatic,
    bool? admin,
    this.smtpEnabled = false,
    this.subsection = GroupRoute.profile,
  }) : admin = admin ?? staff {
    group = {
      'id': 9,
      'name': 'support',
      'full_name': 'Support Team',
      'title': 'Helper',
      'bio_raw': 'Helpful people.',
      'flair_icon': 'shield-halved',
      'flair_bg_color': 'ffffff',
      'flair_color': '000000',
      'visibility_level': 0,
      'members_visibility_level': 0,
      'grant_trust_level': 1,
      'publish_read_state': false,
      'incoming_email': 'old@example.com',
      'smtp_server': 'smtp.original.example',
      'smtp_port': 587,
      'smtp_ssl_mode': 2,
      'smtp_enabled': true,
      'email_username': 'mailbox-user',
      'email_from_alias': 'Support',
      'allow_unknown_sender_topic_replies': false,
      'default_notification_level': 2,
      'automatic': automatic,
      'can_admin_group': true,
      'is_group_owner': !staff,
    };
    transport = DiscourseApi(
      client: MockClient((request) async {
        if (request.method == 'PUT') {
          expect(request.url.path, '/groups/9.json');
          expect(request.headers['User-Api-Key'], 'fixture-key');
          final values = Map<String, dynamic>.from(
            (jsonDecode(request.body) as Map<String, dynamic>)['group'] as Map,
          );
          writes.add(values);
          // Core GroupsController#group_params deliberately ignores these
          // identity fields for owners and/or automatic groups.
          final permitted = {
            'bio_raw',
            'flair_icon',
            'flair_bg_color',
            'flair_color',
            'default_notification_level',
            'messageable_level',
            'mentionable_level',
            if (!automatic) ...[
              'allow_membership_requests',
              'public_exit',
              'public_admission',
              'membership_request_template',
            ],
            if (staff) ...['visibility_level', 'members_visibility_level'],
            if (!automatic) 'full_name',
            if (!automatic && staff) ...[
              'name',
              'title',
              'grant_trust_level',
              'publish_read_state',
              'incoming_email',
            ],
            if (!automatic && this.admin) ...[
              'smtp_server',
              'smtp_port',
              'smtp_ssl_mode',
              'smtp_enabled',
              'email_username',
              'email_password',
              'email_from_alias',
              'allow_unknown_sender_topic_replies',
            ],
          };
          for (final entry in values.entries) {
            if (permitted.contains(entry.key)) {
              group[entry.key] = entry.key == 'smtp_enabled'
                  ? entry.value == 'true'
                  : entry.value;
            }
          }
        } else {
          expect(request.method, 'GET');
          expect(request.url.path, '/groups/${group['name']}.json');
        }
        return http.Response(jsonEncode({'group': group}), 200);
      }),
    );
    api = GroupsApi(transport, const DiscourseModelCodec.core());
  }

  final bool staff;
  final bool admin;
  final bool automatic;
  final bool smtpEnabled;
  final String subsection;
  late final DiscourseApi transport;
  late final GroupsApi api;
  late final Map<String, dynamic> group;
  final writes = <Map<String, dynamic>>[];
  var generation = 0;

  Future<void> pump(WidgetTester tester) async {
    final detail = await tester.runAsync(
      () => api.detail(
        siteUrl: 'https://forum.example',
        apiKey: 'fixture-key',
        groupName: group['name'] as String,
      ),
    );
    tester.view.physicalSize = const Size(1000, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: GroupPage(
            key: ValueKey(generation++),
            siteUrl: 'https://forum.example',
            route: GroupRoute.detail(
              group['name'] as String,
              section: GroupRoute.manage,
              subsection: subsection,
            ),
            registry: PluginRegistry.empty,
            data: GroupPageData(
              detail: detail,
              loaded: true,
              currentUserStaff: staff,
              isAdmin: admin,
              smtpEnabled: smtpEnabled,
            ),
            onOpenMember: (_, _) {},
            onSaveManage: (update) async {
              await api.updateGroup(
                siteUrl: 'https://forum.example',
                apiKey: 'fixture-key',
                groupId: 9,
                values: update.values,
              );
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, {String? subsection}) async {
    final save = find.byKey(
      ValueKey('save-group-${subsection ?? this.subsection}'),
    );
    await tester.ensureVisible(save);
    await tester.runAsync(() async {
      await tester.tap(save);
      await pumpEventQueue();
    });
    await tester.pumpAndSettle();
    expect(tester.widget<DButton>(save).onPressed, isNull);
    expect(tester.takeException(), isNull);
  }
}
