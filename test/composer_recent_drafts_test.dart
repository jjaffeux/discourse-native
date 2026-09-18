import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 1, username: 'reader', canCreateTopic: true);
final _drafts = [
  for (var i = 1; i <= 6; i++)
    UserDraft(
      key: 'topic_$i',
      sequence: 4,
      topicId: i,
      title: 'Recent draft $i',
      data: ComposerDraft(reply: 'Saved reply $i'),
    ),
];

FakeDiscourseApi _api({
  Completer<void>? gate,
  Completer<void>? topicGate,
  List<UserDraft>? drafts,
}) => FakeDiscourseApi(
  user: _user,
  feeds: const {
    '/latest.json': [Topic(id: 1, title: 'A topic', slug: 'a-topic')],
  },
  creatableFeedPaths: const {'/latest.json'},
  userDraftList: drafts ?? _drafts,
  userDraftGate: gate,
  topicGate: topicGate,
  topics: {
    for (var i = 1; i <= 6; i++)
      i: topicPayload(id: i, title: 'Recent draft $i', canCreatePost: true),
  },
);

Future<ShellController> _pump(
  WidgetTester tester,
  FakeDiscourseApi api, {
  FakeDraftStore? drafts,
  TextDirection direction = TextDirection.ltr,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: drafts ?? FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    forumTabs: FakeForumTabStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await tester.binding.setSurfaceSize(const Size(1440, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) =>
          Directionality(textDirection: direction, child: child!),
      home: ShellScope(
        controller: shell,
        child: Scaffold(
          body: ListenableBuilder(
            listenable: shell,
            builder: (context, _) {
              final composer = shell.visibleComposer;
              return composer == null
                  ? const SizedBox.shrink()
                  : ComposerPanel(composer: composer, height: 400);
            },
          ),
        ),
      ),
    ),
  );
  await shell.openNewTopicFromSidebar();
  await tester.pump();
  return shell;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'opens immediately, loads only five drafts, and does not refetch on typing',
    (tester) async {
      final gate = Completer<void>();
      final api = _api(gate: gate);
      final shell = await _pump(tester, api);
      expect(find.byType(ComposerEditor), findsOneWidget);
      expect(api.userDraftRequests, [(siteUrl: _site, offset: 0, limit: 5)]);
      shell.visibleComposer!.text.text = 'Keep writing while loading';
      await tester.pump();
      expect(api.userDraftRequests, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      for (var i = 1; i <= 5; i++) {
        expect(find.text('Recent draft $i'), findsOneWidget);
      }
      expect(find.text('Recent draft 6'), findsNothing);
      expect(shell.visibleComposer!.raw, 'Keep writing while loading');
      shell.closeComposer();
      await tester.pump();
      await shell.openNewTopicFromSidebar();
      await tester.pumpAndSettle();
      expect(api.userDraftRequests, hasLength(2));
      expect(shell.draftList.feedFor(_site).loaded, isFalse);
    },
  );

  testWidgets('selecting a reply draft preserves the current new-topic draft', (
    tester,
  ) async {
    final local = FakeDraftStore();
    final api = _api();
    final shell = await _pump(tester, api, drafts: local);
    await tester.pumpAndSettle();
    shell.visibleComposer!
      ..title.text = 'Unfinished topic'
      ..text.text = 'Keep this topic body';
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('composer-recent-draft-topic_2')),
    );
    await tester.pumpAndSettle();
    expect(shell.visibleComposer!.target.topicId, 2);
    expect(shell.visibleComposer!.raw, 'Saved reply 2');
    final saved = ComposerDraft.fromJson(
      jsonDecode(
            api.draftsSaved.firstWhere(
                  (save) => save['draftKey'] == 'new_topic',
                )['data']!
                as String,
          )
          as Map<String, dynamic>,
    );
    expect(saved.reply, 'Keep this topic body');
    expect(saved.title, 'Unfinished topic');
    expect(
      find.byKey(const ValueKey('composer-recent-draft-topic_2')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selects a separate new-topic draft and blocks switching while submitting',
    (tester) async {
      const draft = UserDraft(
        key: 'new_topic_alternate',
        sequence: 2,
        data: ComposerDraft(
          title: 'Another topic',
          reply: 'Another topic body',
          action: 'createTopic',
        ),
      );
      final shell = await _pump(tester, _api(drafts: [draft, ..._drafts]));
      await tester.pumpAndSettle();
      final button = find.byKey(
        const ValueKey('composer-recent-draft-new_topic_alternate'),
      );
      final original = shell.visibleComposer!;
      original.beginSubmit();
      await tester.pump();
      expect(tester.widget<DButton>(button).onPressed, isNull);
      original.unresolved();
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(shell.visibleComposer!.target.draftKey, draft.key);
      expect(shell.visibleComposer!.title.text, 'Another topic');
      expect(shell.visibleComposer!.raw, 'Another topic body');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed loading is retryable without replacing the editor', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = _api(gate: gate);
    final shell = await _pump(tester, api);
    final composer = shell.visibleComposer!;
    gate.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-retry-drafts')), findsOneWidget);
    expect(shell.visibleComposer, same(composer));
    expect(composer.isEditing, isTrue);
    await tester.tap(find.byKey(const ValueKey('composer-retry-drafts')));
    await tester.pumpAndSettle();
    expect(api.userDraftRequests, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a draft selection cannot reopen a composer closed while its topic loads',
    (tester) async {
      final topicGate = Completer<void>();
      final shell = await _pump(tester, _api(topicGate: topicGate));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('composer-recent-draft-topic_2')),
      );
      await tester.pump();
      shell.closeComposer();
      await tester.pump();
      topicGate.complete();
      await tester.pumpAndSettle();
      expect(shell.visibleComposer, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recent drafts scroll in a narrow RTL header without overflow', (
    tester,
  ) async {
    await _pump(tester, _api(), direction: TextDirection.rtl);
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(340, 700));
    await tester.pumpAndSettle();
    final last = find.byKey(const ValueKey('composer-recent-draft-topic_5'));
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
