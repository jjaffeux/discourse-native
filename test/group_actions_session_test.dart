import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader', admin: true);
const _group = {
  'id': 9,
  'name': 'support',
  'full_name': 'Support Team',
  'can_admin_group': true,
  'can_see_members': true,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final (change, repaint) in [
    ('connect rollback', false),
    ('connect rollback', true),
    ('disconnect rollback', false),
    ('disconnect rollback', true),
    ('counts', true),
  ]) {
    testWidgets(
      'group deletion confirmation keeps its opening session across $change '
      '${repaint ? 'after repaint' : 'before repaint'}',
      (tester) async {
        final server = _Server();
        addTearDown(server.api.close);
        final store = _FailingStore();
        final shell = ShellController(
          api: server.api,
          instanceStore: store,
          authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updater: FakeUpdater(),
          updateStore: FakeUpdateStore(),
          ownsApi: false,
        );
        addTearDown(shell.dispose);
        await tester.runAsync(shell.load);
        expect(shell.currentInstance?.url, _site);
        expect(shell.currentInstance?.user?.username, 'reader');
        expect(shell.openGroupUrl('$_site/g/support'), isTrue);
        expect(shell.currentContent?.groupRoute?.groupName, 'support');
        final width = defaultTargetPlatform == TargetPlatform.iOS
            ? 390.0
            : 1000.0;
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
              builder: (_, child) => DToaster(child: child!),
              home: Scaffold(
                body: MainContent(layout: ShellLayout.forWidth(width)),
              ),
            ),
          ),
        );
        await _settle(tester);
        expect(find.byType(GroupPage), findsOneWidget);
        await _openConfirmation(tester);
        final confirmation = find.byKey(
          const ValueKey('group-delete-confirmation'),
        );
        final confirmationState = tester.state(confirmation);
        final opening = shell.lifecycle.capture(_site);
        final tabId = shell.activeTabId;
        final account = shell.currentAccountIdentity;
        final rollback = change != 'counts';
        store.failSignedOut = rollback;
        if (change == 'connect rollback') {
          await tester.runAsync(shell.connectCurrentInstance);
        } else if (change == 'disconnect rollback') {
          expect(
            await tester.runAsync(() => shell.disconnectInstance(_site)),
            isFalse,
          );
        } else {
          FakeSiteTracker.built.last.deliverNotification(const {
            'all_unread_notifications_count': 4,
          });
        }
        expect(opening.isCurrent, !rollback);
        expect(shell.currentAccountIdentity, account);
        expect(shell.activeTabId, tabId);
        expect(shell.currentContent?.groupRoute?.groupName, 'support');
        if (repaint) await _settle(tester);
        expect(tester.state(confirmation), same(confirmationState));
        await _confirm(tester);
        expect(server.deletions, hasLength(rollback ? 0 : 1));
        expect(server.detailReads, rollback ? 2 : 1);
        if (rollback) {
          // A newly rendered page owns the restored session and remains usable.
          expect(find.text('Support Team'), findsOneWidget);
          await _openConfirmation(tester);
          await _confirm(tester);
          expect(server.deletions, hasLength(1));
        }
        expect(server.deletions.single, 'api-key');
        expect(shell.currentContent?.groupRoute?.isDirectory, isTrue);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      }),
    );
  }
}

Future<void> _openConfirmation(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('group-actions')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('delete-group')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('group-delete-confirmation')),
    'support',
  );
  await tester.pump();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const ValueKey('confirm-delete-group')));
    await pumpEventQueue();
  });
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => pumpEventQueue());
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() => pumpEventQueue());
  await tester.pump(const Duration(milliseconds: 300));
}

class _FailingStore extends FakeInstanceStore {
  _FailingStore()
    : super([instance('meta.discourse.org').copyWith(user: _user)]);
  bool failSignedOut = false;
  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut && instances.any((site) => site.user == null)) {
      return Future.error(StateError('Account snapshot storage unavailable'));
    }
    return super.save(instances);
  }
}

class _Server {
  final deletions = <String?>[];
  int detailReads = 0;
  late final api = DiscourseApi(
    client: MockClient((request) async {
      if (request.method == 'DELETE') {
        expect(request.url.path, '/admin/groups/9.json');
        deletions.add(request.headers['User-Api-Key']);
        return http.Response('{}', 200);
      }
      if (request.url.path == '/groups/support.json') detailReads++;
      final Object body = switch (request.url.path) {
        '/session/current.json' => {
          'current_user': {'id': 7, 'username': 'reader', 'admin': true},
        },
        '/site/basic-info.json' => {'title': 'Test forum'},
        '/site/settings.json' => {
          'site_settings': {'default_homepage': 'latest'},
        },
        '/groups/support.json' => {'group': _group},
        '/groups/support/members.json' => {
          'members': <Object?>[],
          'owners': <Object?>[],
          'meta': {'total': 0},
        },
        '/groups.json' => {
          'groups': [_group],
        },
        '/latest.json' => {
          'topic_list': {'topics': <Object?>[]},
        },
        _ => <String, Object?>{},
      };
      return http.Response(jsonEncode(body), 200);
    }),
  );
}
