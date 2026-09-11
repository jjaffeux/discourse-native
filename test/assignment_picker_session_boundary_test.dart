import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/assign/assign_services.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_controller.dart';
import 'package:discourse_native/src/plugins/assign/assignment_sheet.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _sam = AssignmentUser(username: 'sam', name: 'Sam');
const _forbidden =
    "You can't post that here — or the connection to this site has expired.";

void main() {
  for (final size in [const Size(1000, 800), const Size(390, 844)]) {
    for (final action in ['save', 'unassign']) {
      testWidgets(
        '$action blocks every dismissal while writing at width ${size.width}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final fixture = await _fixture(tester);
          await tester.pumpWidget(fixture.host());
          await _openAndSelect(tester);
          fixture.api.pendingWrite = Completer<Map<String, dynamic>>();
          await tester.tap(find.byKey(Key('assignment-$action')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('assignment-close')));
          await tester.tap(find.byKey(const Key('assignment-cancel')));
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.binding.handlePopRoute();
          await tester.tapAt(const Offset(4, 4));
          if (size.width < 768) {
            await tester.drag(
              find.byType(DDrawerSwipeHandle),
              const Offset(0, 650),
            );
          }
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(AssignmentEditor), findsOneWidget);
          expect(fixture.writeAdmissions, 1);
          fixture.api.pendingWrite!.complete(const {'success': 'OK'});
          await tester.pumpAndSettle();
          expect(find.byType(AssignmentEditor), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'a resize preserves the mounted draft and selects the next presentation on reopen',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _fixture(tester);
      await tester.pumpWidget(fixture.host());
      await _openAndSelect(tester);
      final state = tester.state(find.byType(AssignmentEditor));
      await tester.tap(find.byKey(const Key('assignment-note-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('assignment-note')),
        'Retain this note',
      );
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AssignmentEditor)), same(state));
      expect(find.byType(DDialogContent), findsOneWidget);
      expect(
        tester
            .widget<DTextarea>(find.byKey(const Key('assignment-note')))
            .controller!
            .text,
        'Retain this note',
      );
      expect(tester.takeException(), isNull);
      await _close(tester);
      await _openAndSelect(tester);
      expect(find.byType(DDrawerContent), findsOneWidget);
      expect(
        tester
            .widget<DTextarea>(
              find.byKey(const Key('assignment-note'), skipOffstage: false),
            )
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  for (final target in [
    const AssignmentTarget.topic(7),
    const AssignmentTarget.post(12, topicId: 7),
  ]) {
    for (final action in ['search', 'save', 'remove']) {
      for (final disconnect in [false, true]) {
        testWidgets(
          '${target.type.name} $action refuses an open picker after '
          '${disconnect ? 'disconnect and reconnect' : 'account replacement'}',
          (tester) async {
            final fixture = await _fixture(tester, target: target);
            await tester.pumpWidget(fixture.host());
            await _openAndSelect(tester);
            final editor = tester.state(find.byType(AssignmentEditor));

            if (disconnect) {
              await fixture.shell.disconnectCurrentInstance();
            }
            await fixture.shell.connectCurrentInstance();
            await _loadTarget(fixture.shell);
            await tester.pumpAndSettle();
            expect(
              fixture.shell.currentInstance?.user?.username,
              'replacement',
            );
            expect(fixture.assignments.canAssign(_site, target), isTrue);
            expect(tester.state(find.byType(AssignmentEditor)), same(editor));
            fixture.clearCalls();

            await _act(tester, action);

            fixture.expectNoCalls();
            expect(find.text(_forbidden), findsOneWidget);
            expect(find.byType(AssignmentEditor), findsOneWidget);
            await _close(tester);

            await _openAndSelect(tester);
            expect(fixture.api.calls.single.apiKey, 'api-key');
            fixture.clearCalls();
            await _act(tester, action);
            _expectAction(fixture, action, apiKey: 'api-key');
          },
        );
      }

      testWidgets('${target.type.name} $action works on the opening account', (
        tester,
      ) async {
        final fixture = await _fixture(tester, target: target);
        await tester.pumpWidget(fixture.host(existing: action == 'remove'));
        await _openAndSelect(tester);
        expect(fixture.api.calls.single.apiKey, 'original-key');
        fixture.clearCalls();

        await _act(tester, action);

        _expectAction(fixture, action, apiKey: 'original-key');
        expect(find.text(_forbidden), findsNothing);
      });
    }
  }

  for (final action in ['search', 'save', 'remove']) {
    for (final dispose in [false, true]) {
      testWidgets('$action refuses a picker whose plugin controller was '
          '${dispose ? 'disposed' : 'replaced'}', (tester) async {
        final first = await _fixture(tester);
        await tester.pumpWidget(first.host());
        await _openAndSelect(tester);
        final editor = tester.state(find.byType(AssignmentEditor));
        final second = await _fixture(tester);
        if (dispose) {
          await first.shell.pluginSession.close();
        } else {
          await tester.pumpWidget(second.host());
        }
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(AssignmentEditor)), same(editor));
        first.clearCalls();
        second.clearCalls();

        await _act(tester, action);

        first.expectNoCalls();
        second.expectNoCalls();
        expect(find.text(_forbidden), findsOneWidget);
        await _close(tester);
        if (dispose) await tester.pumpWidget(second.host());
        await _openAndSelect(tester);
        first.expectNoCalls();
        expect(second.api.calls.single.apiKey, 'original-key');
        second.clearCalls();
        await _act(tester, action);
        _expectAction(second, action, apiKey: 'original-key');
      });
    }
  }

  for (final reconnect in [false, true]) {
    testWidgets(
      'suggestions retry ${reconnect ? 'refuses a replacement' : 'keeps the opening'} account',
      (tester) async {
        final fixture = await _fixture(tester);
        fixture.api.failSuggestions = true;
        await tester.pumpWidget(fixture.host());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('assignment-retry-suggestions')),
          findsOneWidget,
        );
        fixture.api.failSuggestions = false;
        if (reconnect) {
          await fixture.shell.connectCurrentInstance();
          await _loadTarget(fixture.shell);
          await tester.pumpAndSettle();
          expect(fixture.assignments.canAssign(_site, fixture.target), isTrue);
        }
        fixture.clearCalls();

        await tester.tap(find.byKey(const Key('assignment-retry-suggestions')));
        await tester.pumpAndSettle();

        if (reconnect) {
          fixture.expectNoCalls();
          expect(find.text(_forbidden), findsOneWidget);
          await _close(tester);
        } else {
          expect(fixture.api.calls.single.apiKey, 'original-key');
          expect(
            find.byKey(const Key('assignment-assignee-user:sam')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('assignment-error')), findsNothing);
        }
      },
    );
  }
}

Future<void> _openAndSelect(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('assignment-assignee-user:sam')));
  await tester.pump();
}

Future<void> _act(WidgetTester tester, String action) async {
  if (action == 'search') {
    await tester.enterText(find.byKey(const Key('assignment-search')), 'sam');
    await tester.pump(const Duration(milliseconds: 300));
  } else {
    await tester.tap(
      find.byKey(Key('assignment-${action == 'save' ? 'save' : 'unassign'}')),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Close'));
  await tester.pumpAndSettle();
  expect(find.byType(AssignmentEditor), findsNothing);
}

void _expectAction(_Fixture fixture, String action, {required String apiKey}) {
  final call = fixture.api.calls.single;
  expect(call.siteUrl, _site);
  expect(call.method, action == 'search' ? 'GET' : 'PUT');
  expect(call.apiKey, apiKey);
  expect(Uri.parse(call.path).path, switch (action) {
    'search' => '/u/search/users.json',
    'save' => '/assign/assign.json',
    _ => '/assign/unassign.json',
  });
  if (action != 'search') {
    expect(call.body, {
      'target_id': fixture.target.id,
      'target_type': fixture.target.type.wireName,
      if (action == 'save') 'username': 'sam',
    });
    expect(find.byType(AssignmentEditor), findsNothing);
  }
}

Future<_Fixture> _fixture(
  WidgetTester tester, {
  AssignmentTarget target = const AssignmentTarget.topic(7),
}) async {
  final auth = _CountingAuthenticator()..keys[_site] = 'original-key';
  final api = _AssignmentApi();
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(username: 'reader')),
    ]),
    api: api,
    authenticator: auth,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await tester.runAsync(() async {
    await shell.load();
    await pumpEventQueue();
    await _loadTarget(shell);
  });
  return _Fixture(shell, api, auth, target);
}

Future<void> _loadTarget(ShellController shell) async {
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  await shell.loadTopic(7, 'topic');
}

class _Fixture {
  _Fixture(this.shell, this.api, this.auth, this.target)
    : assignments = shell.pluginSession.require(assignmentControllerService) {
    assignments.addListener(() {
      if (assignments.isWriting(_site, target)) writeAdmissions++;
    });
  }

  final ShellController shell;
  final _AssignmentApi api;
  final _CountingAuthenticator auth;
  final AssignmentTarget target;
  final AssignmentController assignments;
  int writeAdmissions = 0;

  Widget host({bool existing = true}) => ShellScope(
    controller: shell,
    child: MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
      home: Scaffold(
        body: PluginUiScope.own(
          assignPluginId,
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => unawaited(
                showAssignmentEditor(
                  context: context,
                  siteUrl: _site,
                  target: target,
                  existing: existing ? const Assignment(assignee: _sam) : null,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );

  void clearCalls() {
    api.calls.clear();
    auth.keyReads.clear();
    auth.clientReads = 0;
    writeAdmissions = 0;
  }

  void expectNoCalls() {
    expect(api.calls, isEmpty);
    expect(auth.keyReads, isEmpty);
    expect(auth.clientReads, 0);
    expect(writeAdmissions, 0);
    expect(assignments.isWriting(_site, target), isFalse);
  }
}

class _CountingAuthenticator extends FakeAuthenticator {
  final keyReads = <String>[];
  int clientReads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    keyReads.add(siteUrl);
    return super.apiKeyFor(siteUrl);
  }

  @override
  Future<String> clientId() {
    clientReads++;
    return super.clientId();
  }
}

class _AssignmentApi extends FakeDiscourseApi {
  _AssignmentApi()
    : super(
        feeds: const {'/latest.json': <Topic>[]},
        siteConfigs: const {_site: SiteConfig.unknown()},
      );

  bool failSuggestions = false;
  Completer<Map<String, dynamic>>? pendingWrite;
  final calls =
      <
        ({
          String siteUrl,
          String method,
          String path,
          String? apiKey,
          Map<String, Object?>? body,
        })
      >[];

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async =>
      DiscourseUser(username: apiKey == 'api-key' ? 'replacement' : 'reader');

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async {
    final data = PluginData.none.withValue(
      assignmentsDataKey,
      Assignments(canAssign: true),
    );
    return topicPayload(
      id: id,
      title: 'Topic',
      plugins: data,
      posts: [
        Post(
          id: 12,
          postNumber: 2,
          username: 'author',
          cooked: '<p>Reply</p>',
          plugins: data,
        ),
      ],
    );
  }

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    calls.add((
      siteUrl: siteUrl,
      method: 'GET',
      path: path,
      apiKey: apiKey,
      body: null,
    ));
    if (Uri.parse(path).path == '/assign/suggestions.json') {
      if (failSuggestions) throw const WriteException(WriteFailure.unreachable);
      return const {
        'suggestions': [
          {'username': 'sam', 'name': 'Sam'},
        ],
        'assign_allowed_on_groups': ['staff'],
      };
    }
    return const {
      'users': [
        {'username': 'sam', 'name': 'Sam'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    calls.add((
      siteUrl: siteUrl,
      method: method,
      path: path,
      apiKey: apiKey,
      body: body,
    ));
    return pendingWrite?.future ?? Future.value(const {'success': 'OK'});
  }
}
