import 'dart:async';

import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_discard.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _firstSite = 'https://one.example';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShellController shell;
  late FakeDiscourseApi api;
  late _GatedDraftStore drafts;
  late Completer<void> createPostGate;
  var shellDisposed = false;

  void disposeShell() {
    if (shellDisposed) return;
    shellDisposed = true;
    shell.dispose();
  }

  setUp(() async {
    shellDisposed = false;
    createPostGate = Completer<void>();
    addTearDown(() {
      if (!createPostGate.isCompleted) createPostGate.complete();
    });
    drafts = _GatedDraftStore();
    const user = DiscourseUser(id: 1, username: 'reader');
    api = FakeDiscourseApi(
      user: user,
      feeds: const {'/latest.json': []},
      creatableFeedPaths: const {'/latest.json'},
      createPostGate: createPostGate,
    );
    shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('one.example', title: 'One').copyWith(user: user),
        instance('two.example', title: 'Two').copyWith(user: user),
      ]),
      api: api,
      authenticator: FakeAuthenticator()
        ..keys[_firstSite] = 'api-key'
        ..keys['https://two.example'] = 'second-api-key',
      drafts: drafts,
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(disposeShell);
    await shell.load();
    await shell.loadFeed('latest');
    await shell.openNewTopic();
  });

  ComposerController openReply(int topicId) {
    shell.store.put(
      shell.currentInstance!.url,
      TopicDetail(
        id: topicId,
        title: 'Topic $topicId',
        stream: const [],
        canCreatePost: true,
      ),
    );
    shell.pushContent(
      ContentRoute.topic(
        topicId: topicId,
        slug: 'topic-$topicId',
        title: 'Topic $topicId',
      ),
    );
    shell.openReply();
    return shell.visibleComposer!;
  }

  test('keeps the same composer visible while its tab changes route', () {
    final composer = shell.visibleComposer!;
    composer.text.text = 'An unfinished topic';

    shell.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'first-topic', title: 'First topic'),
    );

    expect(shell.visibleComposer, same(composer));
    expect(shell.visibleComposer?.raw, 'An unfinished topic');

    shell.handleBack();

    expect(shell.visibleComposer, same(composer));
  });

  test('hides the composer in another tab and restores it on return', () {
    final sourceTabId = shell.activeTabId!;
    final composer = shell.visibleComposer!;

    shell.createTab();

    expect(shell.visibleComposer, isNull);

    shell.selectTab(sourceTabId);

    expect(shell.visibleComposer, same(composer));
  });

  test('hides the composer in another forum and restores it on return', () {
    final composer = shell.visibleComposer!;

    shell.selectInstance(1);

    expect(shell.visibleComposer, isNull);

    shell.selectInstance(0);

    expect(shell.visibleComposer, same(composer));
  });

  test(
    'retains each tab reply and its selection while another reply opens',
    () async {
      final firstTab = shell.activeTabId!;
      final first = openReply(7);
      await shell.finishComposerDraftRestore(first);
      first.text.value = const TextEditingValue(
        text: 'An unfinished first reply',
        selection: TextSelection.collapsed(offset: 5),
      );

      shell.createTab();
      final secondTab = shell.activeTabId!;
      final second = openReply(8);
      await shell.finishComposerDraftRestore(second);
      second.text.text = 'A separate second reply';

      shell.selectTab(firstTab);
      expect(shell.visibleComposer, same(first));
      expect(first.raw, 'An unfinished first reply');
      expect(first.text.selection, const TextSelection.collapsed(offset: 5));
      expect(first.isCurrent, isTrue);

      shell.selectTab(secondTab);
      expect(shell.visibleComposer, same(second));
      expect(second.raw, 'A separate second reply');
    },
  );

  test('opening a composer on another forum retains both drafts', () async {
    final first = shell.visibleComposer!;
    first.text.text = 'A topic on the first forum';

    shell.selectInstance(1);
    final second = openReply(7);
    await shell.finishComposerDraftRestore(second);
    second.text.text = 'A reply on the second forum';

    shell.selectInstance(0);
    expect(shell.visibleComposer, same(first));
    expect(first.raw, 'A topic on the first forum');
    shell.selectInstance(1);
    expect(shell.visibleComposer, same(second));
    expect(second.raw, 'A reply on the second forum');
  });

  test('closing an inactive tab flushes only its composer', () async {
    final firstTab = shell.activeTabId!;
    final first = openReply(7);
    await shell.finishComposerDraftRestore(first);
    first.text.text = 'Save this before closing its tab';
    shell.createTab();
    final second = openReply(8);

    shell.closeTab(firstTab);
    await first.finishDraftSaves();

    expect(first.isDisposed, isTrue);
    expect(shell.visibleComposer, same(second));
    expect(
      ComposerDraft.decode(api.draftsSaved.single['data']! as String)?.reply,
      'Save this before closing its tab',
    );
  });

  test('closing other tabs preserves composers on another forum', () async {
    final firstForumComposer = shell.visibleComposer!;
    shell.selectInstance(1);
    final closed = openReply(7);
    shell.createTab();
    final kept = openReply(8);

    shell.closeOtherTabs(shell.activeTabId!);

    expect(closed.isDisposed, isTrue);
    expect(shell.visibleComposer, same(kept));
    shell.selectInstance(0);
    expect(shell.visibleComposer, same(firstForumComposer));
  });

  test('a draft lookup completes in its inactive tab', () async {
    final gate = Completer<void>();
    drafts.readGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await drafts.write(
      _firstSite,
      'topic_7',
      const ComposerDraft(reply: 'Restored in the background').encode(),
    );
    final firstTab = shell.activeTabId!;
    final first = openReply(7);
    shell.createTab();
    final second = openReply(8);

    gate.complete();
    expect(await shell.finishComposerDraftRestore(first), isTrue);
    expect(shell.visibleComposer, same(second));
    shell.selectTab(firstTab);
    expect(shell.visibleComposer?.raw, 'Restored in the background');
  });

  testWidgets(
    'a delayed close closes its original composer after a tab switch',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final gate = Completer<void>();
      drafts.readGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final firstTab = shell.activeTabId!;
      final first = openReply(7);
      first.text.text = 'Keep this draft when closing';
      final closing = closeComposerFromPanel(
        context: context,
        composer: first,
        controller: shell,
      );
      shell.createTab();
      final second = openReply(8);

      gate.complete();
      await closing;
      expect(first.isDisposed, isTrue);
      expect(shell.visibleComposer, same(second));
      shell.selectTab(firstTab);
      expect(shell.visibleComposer, isNull);
    },
  );

  test(
    'a submitted reply closes its original composer after a tab switch',
    () async {
      final firstTab = shell.activeTabId!;
      final first = openReply(7);
      await shell.finishComposerDraftRestore(first);
      first.text.text = 'Submit this first reply';
      final submission = shell.submitComposer();

      shell.createTab();
      final second = openReply(8);
      second.text.text = 'Keep this second reply open';
      createPostGate.complete();
      await submission;

      expect(first.isDisposed, isTrue);
      expect(shell.visibleComposer, same(second));
      expect(second.raw, 'Keep this second reply open');
      shell.selectTab(firstTab);
      expect(shell.visibleComposer, isNull);
      expect(api.created.single['raw'], 'Submit this first reply');
    },
  );

  test('hides the composer in Aggregate and restores it on return', () {
    final composer = shell.visibleComposer!;

    shell.selectAggregate();

    expect(shell.visibleComposer, isNull);

    shell.selectInstance(0);

    expect(shell.visibleComposer, same(composer));
  });

  test('a new topic submission navigates only its original tab', () async {
    final firstTab = shell.activeTabId!;
    final first = shell.visibleComposer!;
    await shell.finishComposerDraftRestore(first);
    first.title.text = 'A new topic created in the original tab';
    first.text.text =
        'This new topic should open in the tab that submitted it.';
    final submission = shell.submitComposer();
    shell.createTab();
    final second = openReply(8);

    await submission;

    expect(shell.currentContent?.topicId, 8);
    expect(shell.visibleComposer, same(second));
    shell.selectTab(firstTab);
    expect(shell.currentContent?.topicId, 901);
    expect(shell.visibleComposer, isNull);
  });

  test('disconnecting a forum disposes all its retained composers', () async {
    final first = openReply(7);
    shell.createTab();
    final second = openReply(8);
    shell.selectInstance(1);
    final otherForum = openReply(7);

    expect(await shell.disconnectInstance(_firstSite), isTrue);

    expect(first.isDisposed, isTrue);
    expect(second.isDisposed, isTrue);
    expect(shell.visibleComposer, same(otherForum));
  });

  test('disposing the shell preserves pending drafts in every tab', () async {
    final first = openReply(7);
    await shell.finishComposerDraftRestore(first);
    first.text.text = 'First pending reply';
    shell.createTab();
    final second = openReply(8);
    await shell.finishComposerDraftRestore(second);
    second.text.text = 'Second pending reply';

    disposeShell();

    expect(first.isDisposed, isTrue);
    expect(second.isDisposed, isTrue);
    expect(
      ComposerDraft.decode(await drafts.read(_firstSite, 'topic_7'))?.reply,
      'First pending reply',
    );
    expect(
      ComposerDraft.decode(await drafts.read(_firstSite, 'topic_8'))?.reply,
      'Second pending reply',
    );
    expect(api.draftsSaved, isEmpty);
  });

  testWidgets('switching between composed tabs renders their own editor text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final firstTab = shell.activeTabId!;
    shell.visibleComposer!.text.text = 'First editor text';
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(theme: AppTheme.light, home: const AdaptiveShell()),
      ),
    );
    await tester.pumpAndSettle();

    shell.createTab();
    final secondTab = shell.activeTabId!;
    await shell.openNewTopic();
    await shell.finishComposerDraftRestore(shell.visibleComposer!);
    shell.visibleComposer!.text.text = 'Second editor text';
    await tester.pumpAndSettle();

    shell.selectTab(firstTab);
    await tester.pumpAndSettle();
    expect(find.byType(ComposerPanel), findsOneWidget);
    expect(find.text('First editor text'), findsOneWidget);
    expect(find.text('Second editor text'), findsNothing);

    shell.selectTab(secondTab);
    await tester.pumpAndSettle();
    expect(find.byType(ComposerPanel), findsOneWidget);
    expect(find.text('Second editor text'), findsOneWidget);
    expect(find.text('First editor text'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    disposeShell();
    await tester.pump();
  });

  test('preserves the composer while the Settings modal is open', () {
    final composer = shell.visibleComposer!;
    composer.text.text = 'Keep this app settings draft';

    expect(shell.openAppSettingsModal(), isTrue);

    expect(shell.rootMode, ShellRootMode.forum);
    expect(shell.visibleComposer, isNull);
    shell.closeAppSettingsModal();
    expect(shell.rootMode, ShellRootMode.forum);
    expect(shell.visibleComposer, same(composer));
    expect(shell.visibleComposer?.raw, 'Keep this app settings draft');
  });
}

final class _GatedDraftStore extends FakeDraftStore {
  Completer<void>? readGate;

  @override
  Future<String?> read(String siteUrl, String draftKey) async {
    await readGate?.future;
    return super.read(siteUrl, draftKey);
  }
}
