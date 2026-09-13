import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('$state preserves a draft before its debounce fires', (
      tester,
    ) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(draftGate: gate);
      final shell = await _pumpApp(tester, api: api, drafts: drafts);
      final composer = await _openReply(shell);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(ComposerPanel),
          matching: find.byType(TextField),
        ),
        'Keep this fresh thought',
      );
      expect(drafts.saved, isEmpty);
      expect(api.draftsSaved, isEmpty);

      _lifecycle(tester).didChangeAppLifecycleState(state);
      await tester.pump();

      expect(_localReply(drafts), 'Keep this fresh thought');
      expect(composer.isDisposed, isFalse);
      expect(gate.isCompleted, isFalse);

      gate.complete();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('backgrounding stages the latest edit behind a remote save', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final drafts = FakeDraftStore();
    final api = FakeDiscourseApi(draftGate: gate);
    final shell = await _pumpApp(tester, api: api, drafts: drafts);
    final composer = await _openReply(shell);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(ComposerPanel),
        matching: find.byType(TextField),
      ),
      'First revision',
    );
    final saving = composer.flushDraft();
    await tester.pump();
    expect(api.draftsSaved, hasLength(1));
    expect(_localReply(drafts), 'First revision');

    await tester.enterText(
      find.descendant(
        of: find.byType(ComposerPanel),
        matching: find.byType(TextField),
      ),
      'Newest revision',
    );
    _lifecycle(tester).didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump();

    expect(gate.isCompleted, isFalse);
    expect(api.draftsSaved, hasLength(1));
    expect(_localReply(drafts), 'Newest revision');

    gate.complete();
    await saving;
    expect(api.draftsSaved, hasLength(2));
    expect(api.draftsSaved.last['data'], contains('Newest revision'));
    expect(drafts.events.where((event) => event == 'clear'), hasLength(1));
    expect(drafts.saved, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'inactive stays foreground and repeated transitions reuse saves',
    (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(draftGate: gate);
      final shell = await _pumpApp(tester, api: api, drafts: drafts);
      final composer = await _openReply(shell);
      composer.text.text = 'Pending while inactive';
      final lifecycle = _lifecycle(tester);

      lifecycle.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();
      expect(drafts.saved, isEmpty);
      expect(api.draftsSaved, isEmpty);

      lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump();
      expect(_localReply(drafts), 'Pending while inactive');
      final writes = drafts.events.length;

      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
        AppLifecycleState.resumed,
        AppLifecycleState.hidden,
      ]) {
        lifecycle.didChangeAppLifecycleState(state);
        await tester.pump();
      }
      expect(drafts.events, hasLength(writes));
      expect(api.draftsSaved, hasLength(1));

      lifecycle.didChangeAppLifecycleState(AppLifecycleState.inactive);
      composer.text.text = 'Edited after returning';
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(_localReply(drafts), 'Edited after returning');
      expect(api.draftsSaved, hasLength(1));

      gate.complete();
      await composer.finishDraftSaves();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('backgrounding preserves composers in retained tabs and forums', (
    tester,
  ) async {
    final drafts = FakeDraftStore();
    final api = FakeDiscourseApi(
      draftFailure: const WriteException(WriteFailure.unreachable),
    );
    final shell = await _pumpApp(tester, api: api, drafts: drafts);
    final first = await _openReply(shell);
    first.text.text = 'First tab';
    expect(shell.canCreateTab, isTrue);
    shell.createTab();
    final second = await _openReply(shell, topicId: 8);
    expect(second, isNot(same(first)));
    second.text.text = 'Second tab';
    shell.selectInstance(1);
    final otherForum = await _openReply(shell);
    otherForum.text.text = 'Other forum';
    shell.createTab();
    expect(shell.visibleComposer, isNull);

    _lifecycle(tester).didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump();

    expect(_localReply(drafts), 'First tab');
    expect(_localReply(drafts, topicId: 8), 'Second tab');
    expect(
      ComposerDraft.decode(
        drafts.saved['https://team.discourse.org::topic_7'],
      )?.reply,
      'Other forum',
    );
    expect(api.draftsSaved, hasLength(3));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a retained in-flight composer cannot reclaim a shared draft', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final drafts = FakeDraftStore();
    final api = FakeDiscourseApi(draftGate: gate);
    final shell = await _pumpApp(tester, api: api, drafts: drafts);
    final first = await _openReply(shell);
    expect(shell.canCreateTab, isTrue);
    shell.createTab();
    final second = await _openReply(shell);
    expect(second, isNot(same(first)));
    second.text.text = 'Older retained writer';
    final savingSecond = second.flushDraft();
    await tester.pump();
    expect(api.draftsSaved, hasLength(1));

    // The first composer is visited first by the background hook. Re-saving
    // the second's in-flight-only snapshot would overwrite this newer text.
    first.text.text = 'Latest pending writer';
    _lifecycle(tester).didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump();
    expect(_localReply(drafts), 'Latest pending writer');
    expect(api.draftsSaved, hasLength(1));

    gate.complete();
    await savingSecond;
    await first.finishDraftSaves();
    expect(api.draftsSaved, hasLength(2));
    expect(api.draftsSaved.last['data'], contains('Latest pending writer'));
    expect(drafts.events.where((event) => event == 'clear'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('backgrounding does not re-stage an older queued shared draft', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final drafts = FakeDraftStore();
    final api = FakeDiscourseApi(draftGate: gate);
    final shell = await _pumpApp(tester, api: api, drafts: drafts);
    final first = await _openReply(shell);
    expect(shell.canCreateTab, isTrue);
    shell.createTab();
    final second = await _openReply(shell);
    expect(second, isNot(same(first)));
    second.text.text = 'Older remote revision';
    final savingSecond = second.flushDraft();
    await tester.pump();
    second.text.text = 'Older queued revision';
    unawaited(second.flushDraft());
    await tester.pump();
    expect(_localReply(drafts), 'Older queued revision');

    first.text.text = 'Newest debounced revision';
    final lifecycle = _lifecycle(tester);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump();
    expect(_localReply(drafts), 'Newest debounced revision');
    expect(api.draftsSaved, hasLength(1));

    final writes = drafts.events.length;
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump();
    expect(drafts.events, hasLength(writes));

    gate.complete();
    await savingSecond;
    await first.finishDraftSaves();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final state in ['discarding', 'submitting', 'checking', 'settled']) {
    testWidgets('backgrounding leaves a $state composer alone', (tester) async {
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi();
      final shell = await _pumpApp(tester, api: api, drafts: drafts);
      final composer = await _openReply(shell);
      composer.text.text = 'Do not start another save';
      switch (state) {
        case 'discarding':
          expect(composer.beginDiscard(), isNotNull);
        case 'submitting':
          composer.beginSubmit();
        case 'checking':
          composer.checking();
        case 'settled':
          composer.draftSettled();
      }

      _lifecycle(tester).didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump();

      expect(drafts.saved, isEmpty);
      expect(api.draftsSaved, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('backgrounding preserves edits after an unresolved submission', (
    tester,
  ) async {
    final drafts = FakeDraftStore();
    final api = FakeDiscourseApi(
      draftFailure: const WriteException(WriteFailure.unreachable),
    );
    final shell = await _pumpApp(tester, api: api, drafts: drafts);
    final composer = await _openReply(shell);
    composer.unresolved();
    composer.text.text = 'Edited while the outcome is unknown';

    _lifecycle(tester).didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump();

    expect(_localReply(drafts), 'Edited while the outcome is unknown');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a delayed background write cannot cross an account boundary', (
    tester,
  ) async {
    final drafts = _GatedDraftStore();
    addTearDown(() {
      if (!drafts.release.isCompleted) drafts.release.complete();
    });
    final api = FakeDiscourseApi(
      user: const DiscourseUser(id: 2, username: 'new-reader'),
      draftFailure: const WriteException(WriteFailure.unreachable),
    );
    final shell = await _pumpApp(tester, api: api, drafts: drafts);
    final first = await _openReply(shell);
    first.text.text = 'Previous account';
    _lifecycle(tester).didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump();
    expect(drafts.started.isCompleted, isTrue);

    await shell.disconnectCurrentInstance();
    await shell.connectCurrentInstance();
    final second = await _openReply(shell);
    second.text.text = 'Current account';
    drafts.gateWrites = false;
    final lifecycle = _lifecycle(tester);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump();
    expect(_localReply(drafts), 'Current account');

    drafts.release.complete();
    await first.finishDraftSaves();
    expect(_localReply(drafts), 'Current account');
    expect(api.draftsSaved, hasLength(1));
    expect(api.draftsSaved.single['data'], contains('Current account'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background saves retain local failure reporting and retry', (
    tester,
  ) async {
    final drafts = _FailingDraftStore();
    final api = FakeDiscourseApi(
      draftFailure: const WriteException(WriteFailure.unreachable),
    );
    final shell = await _pumpApp(tester, api: api, drafts: drafts);
    final composer = await _openReply(shell);
    composer.text.text = 'Not durable yet';
    final lifecycle = _lifecycle(tester);

    lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump();
    expect(composer.localDraftFailed, isTrue);
    expect(composer.draftStatus, DraftStatus.failing);
    expect(drafts.saved, isEmpty);
    expect(tester.takeException(), isNull);

    drafts.failWrites = false;
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    composer.text.text = 'Durable after storage recovers';
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump();

    expect(_localReply(drafts), 'Durable after storage recovers');
    expect(composer.localDraftFailed, isFalse);
    expect(composer.draftStatus, DraftStatus.failing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<ShellController> _pumpApp(
  WidgetTester tester, {
  required FakeDiscourseApi api,
  required FakeDraftStore drafts,
}) async {
  await pumpShell(
    tester,
    desktop,
    api: api,
    drafts: drafts,
    instances: [
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
      instance(
        'team.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
    ],
    authenticator: FakeAuthenticator()
      ..keys[_siteUrl] = 'api-key'
      ..keys['https://team.discourse.org'] = 'team-key',
  );
  return tester.widget<ShellScope>(find.byType(ShellScope)).notifier!;
}

Future<ComposerController> _openReply(
  ShellController shell, {
  int topicId = 7,
}) async {
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
  final composer = shell.visibleComposer!;
  await shell.finishComposerDraftRestore(composer);
  return composer;
}

WidgetsBindingObserver _lifecycle(WidgetTester tester) =>
    tester.state(find.byType(DiscourseApp)) as WidgetsBindingObserver;

String? _localReply(FakeDraftStore drafts, {int topicId = 7}) =>
    ComposerDraft.decode(drafts.saved['$_siteUrl::topic_$topicId'])?.reply;

final class _GatedDraftStore extends FakeDraftStore {
  final started = Completer<void>();
  final release = Completer<void>();
  bool gateWrites = true;

  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (gateWrites) {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    await super.write(siteUrl, draftKey, data, ifCurrent: ifCurrent);
  }
}

final class _FailingDraftStore extends FakeDraftStore {
  bool failWrites = true;

  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (failWrites) throw const DraftWriteException();
    await super.write(siteUrl, draftKey, data, ifCurrent: ifCurrent);
  }
}
