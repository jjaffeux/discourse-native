import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/post_flag_editor.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _otherSite = 'https://team.discourse.org';
const _reader = DiscourseUser(id: 9, username: 'moderator', staff: true);
const _replacement = DiscourseUser(
  id: 10,
  username: 'replacement',
  staff: true,
);
const _flag = PostFlagType(
  id: 3,
  nameKey: 'off_topic',
  name: 'Off-Topic',
  description: '',
  appliesTo: ['Topic'],
);
final _trigger = find.byKey(const ValueKey('topic-status-button'));

void main() {
  testWidgets('topic dropdown supports keyboard selection and restores focus', (
    tester,
  ) async {
    final api = _MenuApi();
    final shell = await _fixture(tester, api);
    final triggerFocus = tester.widget<DButton>(_trigger).focusNode!;
    triggerFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(tester.widget<DButton>(_trigger).expanded, isTrue);
    expect(find.byType(DDropdownMenuContent), findsOneWidget);
    expect(Focus.of(tester.element(find.text('Flag topic'))).hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Unpin topic'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(triggerFocus.hasFocus, isTrue);
    expect(api.writes, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Close topic'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(api.writes, [_write('closed', true)]);
    expect(shell.currentTopic?.closed, isTrue);
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(triggerFocus.hasFocus, isTrue);
  });

  testWidgets('outside dismissal leaves the topic unchanged', (tester) async {
    final api = _MenuApi();
    await _fixture(tester, api);
    await _open(tester);
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(tester.widget<DButton>(_trigger).expanded, isFalse);
    expect(api.writes, isEmpty);
  });

  for (final (status, enableLabel, disableLabel) in [
    (TopicStatusProperty.closed, 'Close topic', 'Open topic'),
    (TopicStatusProperty.archived, 'Archive topic', 'Unarchive topic'),
    (TopicStatusProperty.visible, 'Make topic visible', 'Make topic unlisted'),
  ]) {
    for (final enabled in [false, true]) {
      final label = enabled ? enableLabel : disableLabel;
      final opposite = enabled ? disableLabel : enableLabel;
      testWidgets('$label keeps its intent after a live status refresh', (
        tester,
      ) async {
        final api = _MenuApi();
        final shell = await _fixture(tester, api);
        shell.store.put(
          _site,
          shell.currentTopic!.withStatus(status, !enabled),
        );
        await _pumpButton(tester, shell);
        final anchor = tester.element(_trigger);
        await _open(tester);

        shell.store.put(_site, shell.currentTopic!.withStatus(status, enabled));
        await _pumpButton(tester, shell);
        expect(tester.element(_trigger), same(anchor));
        expect(find.text(label), findsOneWidget);
        await _choose(tester, label);

        expect(api.writes, isEmpty);
        expect(shell.currentTopic!.statusValue(status), enabled);
        await _open(tester);
        await _choose(tester, opposite);
        expect(api.writes, [_write(status.name, !enabled)]);
        expect(shell.currentTopic!.statusValue(status), !enabled);
      });
    }
  }

  for (final pinned in [false, true]) {
    final label = pinned ? 'Pin topic' : 'Unpin topic';
    testWidgets('$label keeps its intent after a live pin refresh', (
      tester,
    ) async {
      final api = _MenuApi();
      final shell = await _fixture(tester, api);
      shell.store.put(
        _site,
        shell.currentTopic!.copyWith(pinned: !pinned, unpinned: pinned),
      );
      await _pumpButton(tester, shell);
      await _open(tester);

      shell.store.put(
        _site,
        shell.currentTopic!.copyWith(pinned: pinned, unpinned: !pinned),
      );
      await _pumpButton(tester, shell);
      await _choose(tester, label);
      expect(api.writes, isEmpty);
      expect(shell.currentTopic?.pinned, pinned);

      await _open(tester);
      await _choose(tester, pinned ? 'Unpin topic' : 'Pin topic');
      expect(api.writes, [_write('pinned', !pinned)]);
      expect(shell.currentTopic?.pinned, !pinned);
    });
  }

  testWidgets(
    'the shell popup keeps Close topic through a live store refresh',
    (tester) async {
      final api = _MenuApi();
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [instance('meta.discourse.org').copyWith(user: _reader)],
        authenticator: FakeAuthenticator()..keys[_site] = 'original-key',
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      await _open(tester);
      api.closed = true;
      await shell.loadTopic(7, 'topic', force: true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TopicStatusButton>(find.byType(TopicStatusButton))
            .topic
            .closed,
        isTrue,
      );
      await _choose(tester, 'Close topic');
      expect(api.writes, isEmpty);
      expect(shell.currentTopic?.closed, isTrue);
    },
  );

  for (final destination in ['topic', 'forum']) {
    for (final rebuild in [false, true]) {
      testWidgets(
        'old menu keeps its target after $destination navigation (rebuild: $rebuild)',
        (tester) async {
          final api = _MenuApi();
          final shell = await _fixture(tester, api);
          final anchor = tester.element(_trigger);
          await _open(tester);
          final site = destination == 'forum' ? _otherSite : _site;
          final id = destination == 'topic' ? 8 : 7;
          shell.openTopicPost(siteUrl: site, topicId: id, postNumber: 1);
          await shell.loadTopic(id, 'topic');
          await tester.idle();
          if (rebuild) await _pumpButton(tester, shell);
          expect(tester.element(_trigger), same(anchor));
          final route = shell.currentContent;

          await _choose(tester, 'Close topic');
          expect(api.writes, [_write('closed', true)]);
          expect(shell.store.read<TopicDetail>(_site, 7)?.closed, isTrue);
          expect(shell.currentTopic?.closed, isFalse);
          expect(shell.currentContent, same(route));

          await _pumpButton(tester, shell);
          await _open(tester);
          await _choose(tester, 'Close topic');
          expect(api.writes.last, _write('closed', true, site: site, id: id));
        },
      );
    }
  }

  for (final change in ['replacement', 'reconnect', 'direct reconnect']) {
    for (final rebuild in [false, true]) {
      testWidgets('old menu rejects $change credentials (rebuild: $rebuild)', (
        tester,
      ) async {
        final api = _MenuApi()
          ..reader = change == 'replacement' ? _replacement : _reader;
        final shell = await _fixture(tester, api);
        final anchor = tester.element(_trigger);
        await _open(tester);
        if (change != 'direct reconnect') {
          await shell.disconnectCurrentInstance();
        }
        await shell.connectCurrentInstance();
        shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
        await shell.loadTopic(7, 'topic');
        await tester.idle();
        if (rebuild) await _pumpButton(tester, shell);
        expect(tester.element(_trigger), same(anchor));
        expect(shell.currentInstance?.user, api.reader);

        await _choose(tester, 'Close topic');
        expect(api.writes, isEmpty);
        expect(shell.currentTopic?.closed, isFalse);

        await _pumpButton(tester, shell);
        await _open(tester);
        await _choose(tester, 'Close topic');
        expect(api.writes, [_write('closed', true, key: 'api-key')]);
      });
    }
  }

  for (final label in [
    'Unpin topic',
    'Delete topic',
    'Recover topic',
    'Select posts',
    'Flag topic',
  ]) {
    testWidgets('old $label choice cannot act for a replacement account', (
      tester,
    ) async {
      final api = _MenuApi(initiallyDeleted: label == 'Recover topic');
      final shell = await _fixture(tester, api);
      await _open(tester);
      await shell.disconnectCurrentInstance();
      await shell.connectCurrentInstance();
      shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
      await shell.loadTopic(7, 'topic');
      await tester.idle();
      await _pumpButton(tester, shell);
      await _choose(tester, label);

      expect(api.writes, isEmpty);
      expect(shell.topicPostSelectionEnabled(_site, 7), isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(PostFlagEditor), findsNothing);
    });
  }

  testWidgets('old menu rejects a replacement controller on the same site', (
    tester,
  ) async {
    final originalApi = _MenuApi();
    await _fixture(tester, originalApi);
    final anchor = tester.element(_trigger);
    await _open(tester);
    final replacementApi = _MenuApi();
    final replacement = await _fixture(tester, replacementApi);
    expect(tester.element(_trigger), same(anchor));
    await _choose(tester, 'Close topic');
    expect(originalApi.writes, isEmpty);
    expect(replacementApi.writes, isEmpty);

    await _open(tester);
    await _choose(tester, 'Close topic');
    expect(replacementApi.writes, [_write('closed', true)]);
    expect(replacement.currentTopic?.closed, isTrue);
  });

  testWidgets('old menu rejects a disposed controller before unmounting', (
    tester,
  ) async {
    final api = _MenuApi();
    final shell = await _fixture(tester, api);
    await _open(tester);
    shell.dispose();
    await _choose(tester, 'Close topic');
    expect(api.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final label in [
    'Close topic',
    'Unpin topic',
    'Delete topic',
    'Recover topic',
    'Select posts',
    'Flag topic',
  ]) {
    testWidgets(
      'old $label choice rechecks permissions before the next rebuild',
      (tester) async {
        final api = _MenuApi(initiallyDeleted: label == 'Recover topic');
        final shell = await _fixture(tester, api);
        await _open(tester);
        shell.store.put(
          _site,
          topicPayload(id: 7, title: 'No permissions').detail,
        );
        await _choose(tester, label);

        expect(api.writes, isEmpty);
        expect(shell.topicPostSelectionEnabled(_site, 7), isFalse);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(PostFlagEditor), findsNothing);
      },
    );
  }

  testWidgets('a retained menu observes another action becoming busy', (
    tester,
  ) async {
    final api = _MenuApi();
    final shell = await _fixture(tester, api);
    await _open(tester);
    final gate = Completer<void>();
    api.statusGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final pending = shell.updateTopicStatus(
      _site,
      7,
      TopicStatusProperty.closed,
      true,
    );
    await tester.pump();
    expect(tester.widget<DButton>(_trigger).onPressed, isNull);
    await tester.tap(find.text('Unpin topic'));
    await tester.pump();
    expect(api.writes, [_write('closed', true)]);
    expect(shell.currentTopic?.pinned, isTrue);
    gate.complete();
    expect(await pending, isNull);
    await tester.pumpAndSettle();

    await _pumpButton(tester, shell);
    await _open(tester);
    await _choose(tester, 'Unpin topic');
    expect(api.writes.last, _write('pinned', false));
  });

  testWidgets('an open menu remains usable once another action finishes', (
    tester,
  ) async {
    final api = _MenuApi();
    final shell = await _fixture(tester, api);
    await _open(tester);
    final gate = Completer<void>();
    api.statusGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final pending = shell.updateTopicStatus(
      _site,
      7,
      TopicStatusProperty.closed,
      true,
    );
    await tester.pump();
    gate.complete();
    expect(await pending, isNull);
    await tester.pumpAndSettle();
    await _choose(tester, 'Unpin topic');
    expect(api.writes, [_write('closed', true), _write('pinned', false)]);
    expect(shell.currentTopic?.pinned, isFalse);
  });

  testWidgets(
    'Select posts still means select when selection starts under the popup',
    (tester) async {
      final shell = await _fixture(tester, _MenuApi());
      await _open(tester);
      shell.setTopicPostSelectionEnabled(_site, 7, true);
      await _pumpButton(tester, shell);
      await _choose(tester, 'Select posts');
      expect(shell.topicPostSelectionEnabled(_site, 7), isTrue);
    },
  );
}

Future<ShellController> _fixture(WidgetTester tester, _MenuApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _reader),
      instance('team.discourse.org').copyWith(user: _reader),
    ]),
    api: api,
    authenticator: FakeAuthenticator()
      ..keys[_site] = 'original-key'
      ..keys[_otherSite] = 'other-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    initialRootMode: ShellRootMode.forum,
  );
  addTearDown(() {
    if (!shell.accountSessionDisposed) shell.dispose();
  });
  await shell.load();
  shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
  await shell.loadTopic(7, 'topic');
  await tester.idle();
  await _pumpButton(tester, shell);
  return shell;
}

Future<void> _pumpButton(WidgetTester tester, ShellController shell) async {
  final site = shell.currentInstance!.url;
  final topic = shell.currentTopic!;
  // Keep the actual button and its popup anchor mounted across topic/account
  // replacements, as happens in the reader header during a live rebuild.
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TopicStatusButton(
            siteUrl: site,
            topic: topic,
            topicFlags: shell.availableTopicFlagTypes(site, topic),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_trigger);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

typedef _Write = ({
  String site,
  String key,
  int id,
  String command,
  bool enabled,
});

_Write _write(
  String command,
  bool enabled, {
  String site = _site,
  String? key,
  int id = 7,
}) => (
  site: site,
  key: key ?? (site == _site ? 'original-key' : 'other-key'),
  id: id,
  command: command,
  enabled: enabled,
);

class _MenuApi extends FakeDiscourseApi {
  _MenuApi({this.initiallyDeleted = false})
    : super(
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'A real topic', slug: 'topic')],
        },
        categoryPostActionCatalog: const SitePostActionCatalog(
          topicFlags: [_flag],
        ),
      );

  DiscourseUser reader = _replacement;
  final bool initiallyDeleted;
  bool closed = false;
  Completer<void>? statusGate;
  final writes = <_Write>[];

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => reader;

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async => topicPayload(
    id: id,
    title: 'A real topic',
    pinned: true,
    closed: closed,
    canCloseTopic: true,
    canArchiveTopic: true,
    canToggleTopicVisibility: true,
    deletedAt: initiallyDeleted ? DateTime.utc(2026) : null,
    canDeleteTopic: !initiallyDeleted,
    canRecoverTopic: initiallyDeleted,
    canSplitMergeTopic: true,
    canFlagTopic: true,
    topicActions: const [PostActionSummary(id: 3, canAct: true)],
    posts: const [
      Post(id: 1, postNumber: 1, username: 'author', cooked: '<p>Body</p>'),
    ],
  );

  @override
  Future<void> updateTopicStatus({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicStatusProperty status,
    required bool enabled,
    String? clientId,
  }) async {
    writes.add(
      _write(status.name, enabled, site: siteUrl, key: apiKey, id: topicId),
    );
    await statusGate?.future;
  }

  @override
  Future<void> updateTopicPinForUser({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required bool pinned,
    String? clientId,
  }) async {
    writes.add(
      _write('pinned', pinned, site: siteUrl, key: apiKey, id: topicId),
    );
  }

  @override
  Future<void> deleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    writes.add(
      _write('deleted', true, site: siteUrl, key: apiKey, id: topicId),
    );
  }

  @override
  Future<void> recoverTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    writes.add(
      _write('deleted', false, site: siteUrl, key: apiKey, id: topicId),
    );
  }
}
