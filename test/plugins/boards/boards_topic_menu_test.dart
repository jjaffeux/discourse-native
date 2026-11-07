import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/models/post.dart' show TopicPayload;
import 'package:discourse_native/src/plugins/boards/boards_controller.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/plugins/boards/boards_module.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/boards_fixture.dart';
import '../../support/fakes.dart';
import '../../support/native_ui_evidence.dart';

const _site = 'https://meta.discourse.org';
const _available =
    '/boards/api/boards/available.json?allowed_permissions=edit,manage&topic_id=7';

void main() {
  for (final phone in [false, true]) {
    testWidgets(
      '${phone ? 'phone' : 'desktop'} eligible topic action adds to selected board',
      (tester) async {
        final api = _BoardMenuApi();
        final shell = await _fixture(tester, api, phone: phone);
        expect(find.text('Add existing topic'), findsNothing);
        expect(find.text('Add to board…'), findsNothing);
        await _open(tester);
        expect(find.text('Add to board…'), findsOneWidget);
        expect(api.availableReads, 1);
        await prepareNativeUiEvidence(tester);
        await captureNativeUi(
          tester,
          'boards-topic-menu-${phone ? 'phone' : 'desktop'}',
        );
        await tester.tap(find.text('Add to board…'));
        await tester.pumpAndSettle();
        expect(api.availableReads, 2);
        expect(find.text('Product roadmap'), findsOneWidget);
        await tester.tap(find.text('Backlog'));
        await tester.pumpAndSettle();
        expect(
          api.board.transport.writes
              .where((write) => write.path.endsWith('/cards'))
              .single
              .body,
          {
            'card': {'column_id': 10, 'topic_id': 7},
          },
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        shell.dispose();
      },
    );
  }

  for (final eligibility in [
    'empty',
    'read-only',
    'archived',
    'failed',
    'disabled',
    'anonymous',
  ]) {
    testWidgets('$eligibility has no board topic action', (tester) async {
      final api = _BoardMenuApi();
      if (eligibility == 'empty') api.empty = true;
      if (eligibility == 'read-only') {
        (api.board.data['board'] as Map)['can_write'] = false;
      }
      if (eligibility == 'archived') {
        (api.board.data['board'] as Map)['archived'] = true;
      }
      if (eligibility == 'failed') {
        api.eligibilityFailure = StateError('Unavailable');
      }
      final shell = await _fixture(
        tester,
        api,
        enabled: eligibility != 'disabled',
        connected: eligibility != 'anonymous',
      );
      await _open(tester);
      expect(find.text('Add to board…'), findsNothing);
      expect(find.text('Add existing topic'), findsNothing);
      expect(
        api.availableReads,
        eligibility == 'disabled' || eligibility == 'anonymous'
            ? 0
            : eligibility == 'failed'
            ? 2
            : 1,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      shell.dispose();
    });
  }

  testWidgets('reopening the menu retries failed board eligibility', (
    tester,
  ) async {
    final api = _BoardMenuApi()..eligibilityFailure = StateError('Unavailable');
    final shell = await _fixture(tester, api);
    await _open(tester);
    expect(find.text('Add to board…'), findsNothing);
    final failedReads = api.availableReads;
    expect(failedReads, 2);
    expect(
      shell.pluginSession.require(boardsControllerKey).eligibleBoards(_site, 7),
      isNull,
    );
    await tester.pumpAndSettle();
    expect(api.availableReads, failedReads);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final readsBeforeReopening = api.availableReads;
    api.eligibilityFailure = null;
    await _open(tester);

    expect(find.text('Add to board…'), findsOneWidget);
    expect(api.availableReads, readsBeforeReopening + 1);
    await tester.pumpWidget(const SizedBox.shrink());
    shell.dispose();
  });

  testWidgets('pending eligibility updates an already open menu', (
    tester,
  ) async {
    final api = _BoardMenuApi()..eligibilityGate = Completer<void>();
    final shell = await _fixture(tester, api);
    await _open(tester);
    expect(find.text('Add to board…'), findsNothing);
    api.eligibilityGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Add to board…'), findsOneWidget);
    expect(api.availableReads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    shell.dispose();
  });

  testWidgets('late account response cannot restore an obsolete menu action', (
    tester,
  ) async {
    final api = _BoardMenuApi()..eligibilityGate = Completer<void>();
    final shell = await _fixture(tester, api);
    await _open(tester);
    final controller = shell.pluginSession.require(boardsControllerKey);
    controller.pluginCurrentUserRefreshed(_site);
    api.empty = true;
    api.eligibilityGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Add to board…'), findsNothing);
    expect(controller.eligibleBoards(_site, 7), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    shell.dispose();
  });

  for (final field in ['can_write', 'archived']) {
    testWidgets('open menu drops last board after $field refresh', (
      tester,
    ) async {
      final api = _BoardMenuApi();
      final shell = await _fixture(tester, api);
      await _open(tester);
      expect(find.text('Add to board…'), findsOneWidget);
      (api.board.data['board'] as Map)[field] = field == 'archived';
      final controller = shell.pluginSession.require(boardsControllerKey);
      final handle = controller.acquire(_site, 1);
      await handle.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Add to board…'), findsNothing);
      handle.release();
      await tester.pumpWidget(const SizedBox.shrink());
      shell.dispose();
    });
  }

  testWidgets(
    'navigation during fresh eligibility does not open old topic picker',
    (tester) async {
      final api = _BoardMenuApi();
      final shell = await _fixture(tester, api);
      await _open(tester);
      api.eligibilityGate = Completer<void>();
      await tester.tap(find.text('Add to board…'));
      await tester.pump();
      shell.openTopicPost(siteUrl: _site, topicId: 8, postNumber: 1);
      api.eligibilityGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Product roadmap'), findsNothing);
      expect(api.board.transport.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      shell.dispose();
    },
  );

  testWidgets('selection rechecks eligibility before opening board picker', (
    tester,
  ) async {
    final api = _BoardMenuApi();
    final shell = await _fixture(tester, api);
    await _open(tester);
    api.empty = true;
    await tester.tap(find.text('Add to board…'));
    await tester.pumpAndSettle();
    expect(find.text('Product roadmap'), findsNothing);
    expect(api.board.transport.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    shell.dispose();
  });
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('topic-more-actions')));
  await tester.pumpAndSettle();
}

Future<ShellController> _fixture(
  WidgetTester tester,
  _BoardMenuApi api, {
  bool phone = false,
  bool enabled = true,
  bool connected = true,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      boardsSettingsKey,
      BoardsSettings(enabled: enabled),
    ),
  );
  api.config = config;
  final installed = PluginInstaller.install(
    const PluginManifest([boardsModule]),
  );
  addTearDown(installed.close);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
        user: connected ? const DiscourseUser(id: 2, username: 'lee') : null,
      ).copyWith(config: config),
    ]),
    api: api,
    plugins: installed,
    authenticator: FakeAuthenticator()
      ..keys.addAll({if (connected) _site: 'key'}),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() {
    if (!shell.accountSessionDisposed) shell.dispose();
  });
  addTearDown(api.board.dispose);
  await shell.load();
  shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
  await shell.loadTopic(7, 'topic');
  await tester.idle();
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.dark.copyWith(
          platform: phone ? TargetPlatform.android : TargetPlatform.macOS,
        ),
        builder: nativeUiEvidenceBuilder,
        home: Builder(
          builder: (context) {
            expect(
              shell.plugins.registry
                  .topicMapActions(context, _site, shell.currentTopic!)
                  .actions,
              isEmpty,
            );
            return Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: phone
                    ? TopicActionsButton(
                        siteUrl: _site,
                        topic: shell.currentTopic!,
                      )
                    : TopicStatusButton(
                        siteUrl: _site,
                        topic: shell.currentTopic!,
                      ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

class _BoardMenuApi extends FakeDiscourseApi {
  final board = BoardsFixture();
  late SiteConfig config;
  Completer<void>? eligibilityGate;
  Object? eligibilityFailure;
  bool empty = false;
  int availableReads = 0;

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => config;

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async => topicPayload(id: id, title: 'A real topic');

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    if (path == _available) {
      availableReads++;
      final boards = empty ? <Object?>[] : [board.data['board']];
      await eligibilityGate?.future;
      if (eligibilityFailure case final error?) throw error;
      return {'boards': boards};
    }
    return board.transport.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => board.transport.pluginWriteJson(
    siteUrl: siteUrl,
    path: path,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );
}
