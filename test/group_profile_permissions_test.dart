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
}

Finder _field(String name) => find.byKey(ValueKey('group-field-$name'));

class _GroupServer {
  _GroupServer({required this.staff, required this.automatic}) {
    group = {
      'id': 9,
      'name': 'support',
      'full_name': 'Support Team',
      'title': 'Helper',
      'bio_raw': 'Helpful people.',
      'flair_icon': 'shield-halved',
      'flair_bg_color': 'ffffff',
      'flair_color': '000000',
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
            if (!automatic) 'full_name',
            if (!automatic && staff) ...['name', 'title'],
          };
          for (final entry in values.entries) {
            if (permitted.contains(entry.key)) group[entry.key] = entry.value;
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
  final bool automatic;
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
              subsection: GroupRoute.profile,
            ),
            registry: PluginRegistry.empty,
            data: GroupPageData(
              detail: detail,
              loaded: true,
              currentUserStaff: staff,
              isAdmin: staff,
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

  Future<void> save(WidgetTester tester) async {
    final save = find.byKey(const ValueKey('save-group-profile'));
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
