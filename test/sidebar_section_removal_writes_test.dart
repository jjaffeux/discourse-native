import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/sidebar_section_store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _other = 'https://other.example';
const _section = 'custom-9';
String _key(String site) =>
    '${SharedPreferencesSidebarSectionPersistence.keys.of(site)}.$_section';

void main() {
  for (final remove in [false, true]) {
    testWidgets(
      'Native sidebar choices ${remove ? 'cannot revive a durably removed forum' : 'persist in order while the forum remains'}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = _HeldPreferences({'flutter.${_key(_other)}': true});
        SharedPreferencesStorePlatform.instance = preferences;
        addTearDown(() {
          if (!preferences.release.isCompleted) preferences.release.complete();
        });
        const user = DiscourseUser(id: 7, username: 'reader');
        final original = instance('meta.discourse.org').copyWith(user: user);
        final api = FakeDiscourseApi(
          user: user,
          customSidebarSectionsBySite: {
            _site: [
              SidebarSection.customFromJson({
                'id': 9,
                'title': 'Projects',
                'public': true,
                'links': [
                  {
                    'id': 11,
                    'name': 'Handbook',
                    'value': '/handbook',
                    'icon': 'link',
                  },
                ],
              }, index: 0)!,
            ],
          },
        );
        await pumpShell(
          tester,
          desktop,
          instances: [original, instance('other.example')],
          api: api,
          authenticator: FakeAuthenticator()..keys[_site] = 'key',
        );
        final shell = ShellScope.read(
          tester.element(find.byType(InstanceSidebar)),
        );
        await _openShortcuts(tester);
        expect(find.text('Handbook'), findsOneWidget);

        await _toggleProjects(tester);
        await preferences.started.future;
        expect(
          await preferences.getAll(),
          containsPair('flutter.${_key(_site)}', true),
        );
        // The first save reached storage, but its acknowledgement is held.
        // These two real header taps queue newer saves behind it.
        await _toggleProjects(tester);
        await _toggleProjects(tester);
        expect(
          shell.sidebarSections.collapsedFor(
            siteUrl: _site,
            sectionId: _section,
          ),
          isTrue,
        );
        if (remove) {
          expect(await shell.removeInstance(shell.instanceFor(_site)!), isTrue);
          await tester.pumpAndSettle();
          expect(
            await preferences.getAll(),
            isNot(contains('flutter.${_key(_site)}')),
          );
          expect(await shell.addInstance(original), isTrue);
          await shell.connectCurrentInstance();
          // The new sidebar can be restoring behind the held storage queue.
          await tester.pump();
        }

        preferences.release.complete();
        final persisted = await shell.sidebarSections.read(
          siteUrl: _site,
          sectionId: _section,
        );
        await tester.pumpAndSettle();
        expect(persisted, !remove);
        expect(
          await preferences.getAll(),
          containsPair('flutter.${_key(_other)}', true),
        );
        if (remove) {
          expect(
            await preferences.getAll(),
            isNot(contains('flutter.${_key(_site)}')),
          );
          await _openShortcuts(tester);
          expect(find.text('Handbook'), findsOneWidget);
          // A fresh choice for the re-added forum owns a new save.
          await _toggleProjects(tester);
          expect(
            await shell.sidebarSections.read(
              siteUrl: _site,
              sectionId: _section,
            ),
            isTrue,
          );
          expect(
            await preferences.getAll(),
            containsPair('flutter.${_key(_site)}', true),
          );
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }
}

Future<void> _openShortcuts(WidgetTester tester) async {
  final shortcuts = find.byKey(
    const ValueKey('sidebar-panel-switch-shortcuts'),
  );
  await tester.ensureVisible(shortcuts);
  await tester.tapAt(tester.getRect(shortcuts).centerLeft + const Offset(8, 0));
  await tester.pumpAndSettle();
}

Future<void> _toggleProjects(WidgetTester tester) async {
  final header = find.widgetWithText(DCollapsibleTrigger, 'Projects');
  await tester.ensureVisible(header);
  await tester.tap(header);
  await tester.pumpAndSettle();
}

final class _HeldPreferences extends InMemorySharedPreferencesStore {
  _HeldPreferences(super.data) : super.withData();

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final saved = await super.setValue(valueType, key, value);
    if (key == 'flutter.${_key(_site)}' && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    return saved;
  }
}
