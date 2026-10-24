import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/draft_coordinator.dart';
import 'package:discourse_native/src/shell/composer/existing_topic_opening_owner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _post = Post(
  id: 9,
  postNumber: 2,
  username: 'sam',
  cooked: '',
  canEdit: true,
);
const _quote = '[quote="sam"]Quoted words[/quote]';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reply prefers a retained topic editor and infers canonical whisper',
    () {
      final h = _Harness();
      addTearDown(h.dispose);
      h.store.put(
        _site,
        const Post(
          id: 9,
          postNumber: 2,
          username: 'sam',
          cooked: '',
          postType: Post.whisperPostType,
        ),
      );
      final first = h.reply();
      final other = h.build(
        const ReplyComposerTarget(
          siteUrl: _site,
          topicId: 8,
          slug: '',
          topicTitle: 'Other',
          privateMessageTopic: false,
        ),
      );
      final plan =
          h.owner.prepareReply(
                h.origin(),
                replyToPostNumber: 2,
                replyToUsername: 'sam',
              )
              as ReuseReplyOpeningPlan;
      expect(plan.composer, same(first));
      h.owner.reuseReply(plan);
      expect(first.target.replyToPostNumber, 2);
      expect(first.target.replyingToWhisper, isTrue);
      expect(h.selectedComposer, same(other));
    },
  );

  test('discarding and closing editors cannot be reused', () {
    final h = _Harness();
    addTearDown(h.dispose);
    final composer = h.reply();
    composer.beginClose();
    expect(h.owner.prepareReply(h.origin()), isA<CreateReplyOpeningPlan>());
    composer.cancelClose();
    composer.beginDiscard();
    expect(h.owner.prepareReply(h.origin()), isNull);
  });

  for (final changed in [
    'none',
    'route',
    'reader',
    'account',
    'editor',
    'owner',
  ]) {
    test('quote waits for restoration with $changed replacement', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.local.readGate = Completer<void>();
      h.local.saved['$_site::topic_7'] = const ComposerDraft(
        reply: 'Restored draft',
      ).encode();
      final reply = h.owner.prepareReply(h.origin()) as CreateReplyOpeningPlan;
      final composer = h.build(reply.target, drafting: true);
      h.owner.startReply(reply, composer);
      final plan = h.owner.prepareQuote(h.origin(), _post, _quote)!;
      expect(plan.composer, same(composer));
      final insertion = h.owner.insertQuote(plan, composer, _quote);
      expect(composer.raw, isEmpty);
      switch (changed) {
        case 'route':
          h.route = ContentRoute.topic(
            topicId: 7,
            slug: 'topic',
            title: 'Display',
          );
        case 'reader':
          h.readerCurrent = false;
        case 'account':
          h.lifecycle.invalidate(_site);
        case 'editor':
          h.members.remove(composer);
        case 'owner':
          h.owner.dispose();
      }
      h.local.readGate!.complete();
      await insertion;
      expect(composer.raw.contains(_quote), changed == 'none');
      if (changed == 'none') expect(composer.raw, 'Restored draft\n\n$_quote');
    });
  }

  test(
    'quote clears first-post reply targeting but keeps an open reply target',
    () {
      final h = _Harness();
      addTearDown(h.dispose);
      final quote = h.owner.prepareQuote(
        h.origin(),
        const Post(
          id: 9,
          postNumber: 1,
          username: 'sam',
          cooked: '',
          canEdit: true,
        ),
        _quote,
      )!;
      expect(quote.reply!.target.replyToPostNumber, isNull);
      final composer = h.reply(replyToPostNumber: 3);
      final reuse = h.owner.prepareQuote(h.origin(), _post, _quote)!;
      expect(reuse.composer, same(composer));
      expect(composer.target.replyToPostNumber, 3);
      expect(h.owner.prepareQuote(h.origin(), _post, '  '), isNull);
    },
  );

  test('first-post plans keep stored title, taxonomy and tag minimum', () {
    final h = _Harness();
    addTearDown(h.dispose);
    final plan = h.owner.prepareEdit(
      h.origin(),
      const Post(
        id: 9,
        postNumber: 1,
        username: 'sam',
        cooked: '',
        canEdit: true,
      ),
      category: const TopicCategory(
        id: 5,
        name: 'Bugs',
        color: '888888',
        minimumRequiredTags: 2,
      ),
    )!;
    expect(plan.target, isA<TopicEditComposerTarget>());
    expect(plan.target.topicTitle, 'Stored title');
    expect(plan.target.initialCategoryId, 5);
    expect(plan.target.initialTags.single.name, 'bug');
    expect(plan.target.privateMessageTopic, isTrue);
    expect(plan.minimumRequiredTags, 2);
    final postOnly = h.owner.prepareEdit(h.origin(), _post)!;
    expect(postOnly.target, isA<PostEditComposerTarget>());
    expect(postOnly.minimumRequiredTags, 0);
  });

  for (final selection in <String?, int?>{
    null: null,
    '  * "quoted" words\nnext line  ': 8,
    'missing selection': 0,
    ' ': null,
  }.entries) {
    test(
      'raw whitespace and caret survive selection ${selection.key}',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        const raw = '  first\n    “quoted” words\n  tail  ';
        final plan = h.owner.prepareEdit(
          h.origin(),
          _post.withRaw(raw),
          focusText: selection.key,
        )!;
        final composer = h.build(plan.target);
        await h.owner.loadEditBody(plan, composer);
        expect(composer.text.text, raw);
        expect(composer.originalRaw, raw);
        expect(
          composer.text.selection.baseOffset,
          selection.value ?? raw.length,
        );
        expect(h.api.postFetches, isEmpty);
      },
    );
  }

  for (final retired in ['none', 'account', 'editor', 'owner']) {
    test(
      'raw loading retains the editor after reader changes with $retired retirement',
      () async {
        final gate = Completer<void>();
        final h = _Harness(
          api: FakeDiscourseApi(
            postGate: gate,
            postsById: {9: _post.withRaw('  loaded raw  ')},
          ),
        );
        addTearDown(h.dispose);
        final plan = h.owner.prepareEdit(h.origin(), _post)!;
        final composer = h.build(plan.target);
        final loading = h.owner.loadEditBody(plan, composer);
        await pumpEventQueue();
        expect(composer.loadingBody, isTrue);
        expect(h.api.postFetchIncludesRaw, [true]);
        h.readerCurrent = false;
        h.selectedComposer = null;
        switch (retired) {
          case 'account':
            h.lifecycle.invalidate(_site);
          case 'editor':
            h.members.remove(composer);
          case 'owner':
            h.owner.dispose();
        }
        gate.complete();
        await loading;
        expect(
          composer.originalRaw,
          retired == 'none' ? '  loaded raw  ' : isNull,
        );
      },
    );
  }

  for (final missing in [true, false]) {
    test(
      'missing raw or post fails loading without making blank edits saveable $missing',
      () async {
        final h = _Harness(
          api: FakeDiscourseApi(postsById: missing ? {9: _post} : {}),
        );
        addTearDown(h.dispose);
        final plan = h.owner.prepareEdit(h.origin(), _post)!;
        final composer = h.build(plan.target);
        await h.owner.loadEditBody(plan, composer);
        expect(composer.loadingBody, isFalse);
        expect(composer.canSubmit, isFalse);
        expect(composer.error, isNotNull);
      },
    );
  }

  test(
    'account retirement during a credential read cannot fetch with a successor key',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final gate = Completer<void>();
      h.credentials.readGate = gate;
      final plan = h.owner.prepareEdit(h.origin(), _post)!;
      final composer = h.build(plan.target);
      final loading = h.owner.loadEditBody(plan, composer);
      await pumpEventQueue();
      h.lifecycle.invalidate(_site);
      h.lifecycle.capture(_site);
      h.credentials.keys[_site] = 'successor-key';
      gate.complete();
      await loading;
      expect(h.api.postFetches, isEmpty);
      expect(composer.originalRaw, isNull);
    },
  );

  test(
    'publication retirement cannot adopt successor credentials or cached raw',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final plan = h.owner.prepareEdit(
        h.origin(),
        _post.withRaw('Old account'),
      )!;
      final composer = h.build(plan.target);
      h.lifecycle.invalidate(_site);
      h.lifecycle.capture(_site);
      await h.owner.loadEditBody(plan, composer);
      expect(composer.originalRaw, isNull);
      expect(h.api.postFetches, isEmpty);
    },
  );

  test(
    'reentrant body-loading publication retires before requesting raw',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final plan = h.owner.prepareEdit(h.origin(), _post)!;
      final composer = h.build(plan.target);
      composer.addListener(() {
        if (composer.loadingBody) h.lifecycle.invalidate(_site);
      });
      await h.owner.loadEditBody(plan, composer);
      expect(h.api.postFetches, isEmpty);
    },
  );
}

final class _Harness
    implements ExistingTopicOpeningEditors, ExistingTopicOpeningReader {
  _Harness({FakeDiscourseApi? api}) : api = api ?? FakeDiscourseApi() {
    drafts = ComposerDraftCoordinator(
      localStore: local,
      persistence: this.api,
      draftsApi: this.api,
      lifecycle: lifecycle,
      credentials: credentials,
      readClientId: () async => '',
      isDisposed: () => disposed,
      isCurrentComposer: members.contains,
      readCachedDraft: (_) => null,
      readCachedSequence: (_) => 0,
      writeCachedDraft: (_, _, _) {},
      minimumRequiredTagsFor: (_, _) => 0,
      isServerDraftKnown: (_) => false,
      recordDraftDestroyed: (_, _, {required knownToExist}) {},
      onComposerClosed: members.remove,
    );
    owner = ExistingTopicComposerOpeningOwner(
      editors: this,
      store: store,
      drafts: drafts,
      credentials: credentials,
      content: this.api,
    );
  }

  final FakeDiscourseApi api;
  final lifecycle = SiteLifecycle();
  final store = Store();
  final credentials = _OpeningCredentials()..keys[_site] = 'api-key';
  final local = _GatedDrafts();
  final members = <ComposerController>[];
  final editors = <ComposerController>[];
  late final ComposerDraftCoordinator drafts;
  late final ExistingTopicComposerOpeningOwner owner;
  bool disposed = false;
  bool readerCurrent = true;
  ContentRoute route = ContentRoute.topic(
    topicId: 7,
    slug: 'topic',
    title: 'Display',
  );
  @override
  ComposerController? selectedComposer;

  ExistingTopicOpeningOrigin origin() => ExistingTopicOpeningOrigin(
    siteUrl: _site,
    lease: lifecycle.capture(_site),
    tabId: 'source-tab',
    reader: this,
    route: route,
    canReply: true,
    topic: const TopicDetail(
      id: 7,
      title: 'Stored title',
      stream: [9],
      canEdit: true,
      categoryId: 5,
      privateMessage: true,
      tags: [TopicTag(name: 'bug')],
    ),
  );

  ComposerController reply({int? replyToPostNumber}) => build(
    owner.prepareReply(origin(), replyToPostNumber: replyToPostNumber)!.target,
  );

  ComposerController build(ComposerTarget target, {bool drafting = false}) {
    final session = drafting ? drafts.openSession(target) : null;
    final composer = ComposerController(
      target,
      onSaveDraft: session?.save,
      onStageDraft: session?.stage,
    );
    members.add(composer);
    editors.add(composer);
    selectedComposer = composer;
    if (session != null) drafts.attach(session, composer);
    return composer;
  }

  @override
  Iterable<ComposerController> forSite(String siteUrl) =>
      members.where((composer) => composer.target.siteUrl == siteUrl);
  @override
  bool owns(ComposerController composer) => members.contains(composer);
  @override
  bool isCurrentRoute(ContentRoute route) =>
      readerCurrent && identical(this.route, route);

  void dispose() {
    disposed = true;
    owner.dispose();
    for (final composer in editors) {
      drafts.retire(composer);
      composer.dispose();
    }
  }
}

final class _GatedDrafts extends FakeDraftStore {
  Completer<void>? readGate;
  @override
  Future<String?> read(String siteUrl, String draftKey) async {
    await readGate?.future;
    return super.read(siteUrl, draftKey);
  }
}

final class _OpeningCredentials extends FakeAuthenticator {
  Completer<void>? readGate;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    await readGate?.future;
    return super.apiKeyFor(siteUrl);
  }
}
