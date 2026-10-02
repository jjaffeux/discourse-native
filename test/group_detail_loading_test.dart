import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/shell/group_pages_host.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _group = {
  'id': 9,
  'name': 'support',
  'full_name': 'Support Team',
  'can_see_members': true,
  'user_count': 1,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final failFirst in [false, true]) {
    testWidgets(
      'directory opens a loading group then ${failFirst ? 'retries its error' : 'retains detail during refresh'}',
      (tester) async {
        final first = Completer<Map<String, dynamic>>();
        final second = Completer<Map<String, dynamic>>();
        addTearDown(() {
          for (final pending in [first, second]) {
            if (!pending.isCompleted) pending.complete({'group': _group});
          }
        });
        final api = _GroupApi([first, second]);
        await pumpShell(
          tester,
          defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
          instances: [instance('meta.discourse.org')],
          api: api,
        );
        final shell = ShellScope.read(
          tester.element(find.byType(MainContent, skipOffstage: false).first),
        );
        shell.selectDestination(
          const SidebarDestination(
            id: 'groups',
            label: 'Groups',
            icon: DIcons.users,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('group-row-support')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        expect(find.byType(GroupPagesHost), findsOneWidget);
        expect(shell.currentContent?.groupRoute?.groupName, 'support');
        expect(api.detailRequests, 1);
        expect(shell.groups.detailState(_site, 'support').loading, isTrue);
        expect(find.byType(GroupPage), findsOneWidget);
        await _expectLoading(tester);

        if (failFirst) {
          first.completeError(StateError('Group unavailable'));
          await tester.pumpAndSettle();
          expect(find.byType(DSkeletonRegion), findsNothing);
          expect(find.text("Couldn't load this group."), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.widgetWithText(DButton, 'Try again'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await _expectLoading(tester);
        } else {
          first.complete({'group': _group});
          await tester.pumpAndSettle();
          _expectReady(tester);
          final page = tester.widget<GroupPage>(find.byType(GroupPage));
          final refreshing = page.onRefresh!();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(shell.groups.detailState(_site, 'support').loading, isTrue);
          _expectReady(tester);
          second.complete({'group': _group});
          await refreshing;
        }

        expect(api.detailRequests, 2);
        if (failFirst) second.complete({'group': _group});
        await tester.pumpAndSettle();
        _expectReady(tester);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }
}

Future<void> _expectLoading(WidgetTester tester) async {
  final skeleton = find.byType(DSkeletonRegion);
  expect(skeleton, findsOneWidget);
  expect(find.byType(DSkeleton), findsWidgets);
  final page = tester.getRect(find.byType(GroupPage));
  expect(tester.getRect(skeleton), page);
  expect(page.height, greaterThan(300));
  expect(page.width, greaterThan(300));
  expect(find.text('Support Team'), findsNothing);
  expect(tester.takeException(), isNull);
  final semantics = tester.ensureSemantics();
  try {
    await tester.pump();
    expect(
      tester.getSemantics(skeleton),
      isSemantics(label: 'Loading support', isLiveRegion: true),
    );
  } finally {
    semantics.dispose();
  }
}

void _expectReady(WidgetTester tester) {
  expect(find.byType(DSkeletonRegion), findsNothing);
  expect(find.text('Support Team'), findsOneWidget);
  expect(find.text('sam'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

class _GroupApi extends FakeDiscourseApi {
  _GroupApi(this.details) : super(feeds: const {'/latest.json': []});

  final List<Completer<Map<String, dynamic>>> details;
  int detailRequests = 0;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path == '/groups.json') {
      return {
        'groups': [_group],
        'total_rows_groups': 1,
      };
    }
    if (uri.path == '/groups/support.json') {
      detailRequests++;
      return details.removeAt(0).future;
    }
    if (uri.path == '/groups/support/members.json') {
      return {
        'members': [
          {'id': 7, 'username': 'sam'},
        ],
        'meta': {'total': 1, 'limit': 50, 'offset': 0},
      };
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
