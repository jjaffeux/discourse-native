import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 9, username: 'admin', admin: true, staff: true);
const _group = {
  'id': 9,
  'name': 'support',
  'full_name': 'Support Team',
  'can_see_members': true,
  'can_admin_group': true,
  'allow_membership_requests': true,
  'user_count': 1,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          null,
        ),
  );
  for (final section in [
    'members',
    'activity',
    'requests',
    'permissions',
    'logs',
  ]) {
    for (final outcome in ['loaded', 'empty', 'error']) {
      testWidgets(
        'cached group $section shows its pending section then $outcome',
        (tester) async {
          final api = _Api(section);
          addTearDown(api.finish);
          final shell = await _open(tester, api);
          await _select(tester, section);
          await _frames(tester);
          expect(api.sectionRequests, 1);
          expect(api.pending.isCompleted, isFalse);
          expect(renderedText('Support Team'), findsOneWidget);
          expect(api.detailRequests, 1);
          await _expectLoading(tester, section);
          api.finish(outcome: outcome);
          await tester.pumpAndSettle();
          expect(find.byType(DSkeletonRegion), findsNothing);
          if (outcome == 'loaded') {
            expect(find.text('Loaded section row'), findsWidgets);
          } else if (outcome == 'error') {
            final page = tester.widget<GroupPage>(find.byType(GroupPage));
            expect(page.data.sectionError, isNotNull);
            expect(find.text(page.data.sectionError!), findsWidgets);
          } else {
            expect(
              find.text(switch (section) {
                'members' => 'This group has no members.',
                'activity' => 'No posts yet.',
                'requests' => 'There are no pending membership requests.',
                'permissions' =>
                  'There are no categories associated with this group.',
                _ => 'No group changes have been recorded.',
              }),
              findsOneWidget,
            );
          }
          expect(shell.currentContent!.groupRoute!.groupName, 'support');
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.macOS,
          TargetPlatform.iOS,
        }),
      );
    }
    testWidgets(
      'cached $section rows remain visible during refresh',
      (tester) async {
        final api = _Api(section);
        addTearDown(api.finish);
        await _open(tester, api);
        await _select(tester, section);
        await _frames(tester);
        api.finish();
        await tester.pumpAndSettle();
        expect(find.text('Loaded section row'), findsWidgets);
        api.pending = Completer<Object>();
        final refreshing = tester
            .widget<GroupPage>(find.byType(GroupPage))
            .onRefresh!();
        await _frames(tester);
        expect(api.sectionRequests, 2);
        expect(find.byType(DSkeletonRegion), findsNothing);
        expect(find.text('Loaded section row'), findsWidgets);
        api.finish();
        await refreshing;
        await tester.pumpAndSettle();
        expect(find.text('Loaded section row'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      }),
    );
  }
}

Future<ShellController> _open(WidgetTester tester, _Api api) async {
  await pumpShell(
    tester,
    defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
    instances: [instance('meta.discourse.org').copyWith(user: _user)],
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
  );
  final shell = ShellScope.read(
    tester.element(find.byType(MainContent, skipOffstage: false).first),
  );
  shell.pushContent(
    ContentRoute.group(
      GroupRoute.detail(
        'support',
        section: GroupRoute.manage,
        subsection: GroupRoute.profile,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(renderedText('Support Team'), findsOneWidget);
  expect(find.byType(DSkeletonRegion), findsNothing);
  expect(api.detailRequests, 1);
  return shell;
}

Future<void> _expectLoading(WidgetTester tester, String section) async {
  final skeleton = find.byType(DSkeletonRegion);
  expect(skeleton, findsOneWidget);
  expect(find.byType(DSkeleton), findsWidgets);
  expect(tester.getRect(skeleton).height, greaterThan(150));
  expect(tester.getRect(skeleton).width, greaterThan(200));
  final semantics = tester.ensureSemantics();
  try {
    await tester.pump();
    final label = switch (section) {
      'members' => 'Members',
      'activity' => 'Posts',
      'requests' => 'Requests',
      'permissions' => 'Permissions',
      _ => 'Logs',
    };
    expect(
      tester.getSemantics(skeleton),
      isSemantics(label: 'Loading $label', isLiveRegion: true),
    );
  } finally {
    semantics.dispose();
  }
  expect(tester.takeException(), isNull);
}

Future<void> _select(WidgetTester tester, String section) async {
  if (section == 'logs') {
    if (find.byKey(const ValueKey('group-subtab-logs')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('group-subtab-logs')));
    } else {
      await tester.tap(find.byKey(const ValueKey('group-manage-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('group-manage-sheet-logs')));
    }
  } else {
    final tab = find.byKey(ValueKey('group-tab-$section'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => pumpEventQueue());
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() => pumpEventQueue());
  await tester.pump();
}

class _Api extends FakeDiscourseApi {
  _Api(this.section) : super(user: _user, feeds: const {'/latest.json': []});
  final String section;
  var pending = Completer<Object>();
  final readPaths = <String>[];
  int detailRequests = 0;
  int sectionRequests = 0;

  Object get result => switch (section) {
    'members' || 'requests' => {
      'members': [
        {'id': 7, 'username': 'loaded', 'name': 'Loaded section row'},
      ],
      'meta': {'total': 1, 'limit': 50, 'offset': 0},
    },
    'activity' => {
      'posts': [
        {
          'id': 7,
          'topic_id': 42,
          'post_number': 1,
          'topic_title': 'Loaded section row',
          'excerpt': 'Excerpt',
        },
      ],
    },
    'permissions' => [
      {
        'permission_type': 1,
        'category': {'id': 12, 'name': 'Loaded section row'},
      },
    ],
    _ => {
      'logs': [
        {'action': 'change', 'subject': 'Loaded section row'},
      ],
      'all_loaded': true,
    },
  };

  void finish({String outcome = 'loaded'}) {
    if (pending.isCompleted) return;
    if (outcome == 'error') {
      pending.completeError(StateError('Section unavailable'));
    } else if (outcome == 'empty') {
      pending.complete(switch (section) {
        'members' || 'requests' => {
          'members': <Object>[],
          'meta': {'total': 0, 'limit': 50, 'offset': 0},
        },
        'activity' => {'posts': <Object>[]},
        'permissions' => <Map<String, dynamic>>[],
        _ => {'logs': <Object>[], 'all_loaded': true},
      });
    } else {
      pending.complete(result);
    }
  }

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    readPaths.add(path);
    final uri = Uri.parse(path);
    if (uri.path == '/groups/support.json') {
      detailRequests++;
      return {'group': _group};
    }
    final match = switch (section) {
      'members' =>
        uri.path == '/groups/support/members.json' &&
            uri.queryParameters['requesters'] != 'true',
      'requests' =>
        uri.path == '/groups/support/members.json' &&
            uri.queryParameters['requesters'] == 'true',
      'activity' => uri.path == '/groups/support/posts.json',
      'logs' => uri.path == '/groups/support/logs.json',
      _ => false,
    };
    if (match) {
      sectionRequests++;
      return Map<String, dynamic>.from(await pending.future as Map);
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    if (path == '/g/support/permissions.json') {
      sectionRequests++;
      return (await pending.future as List).cast<Map<String, dynamic>>();
    }
    return super.pluginGetJsonList(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
