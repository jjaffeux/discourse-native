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
      h.build(
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
          postType: Post.whisperPostType,
        ),
        _quote,
      )!;
      expect(quote.reply!.target.replyToPostNumber, isNull);
      expect(quote.reply!.target.replyingToWhisper, isFalse);
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
    const bugs = TopicCategory(
      id: 5,
      name: 'Bugs',
      color: '888888',
      minimumRequiredTags: 2,
    );
    final plan = h.owner.prepareEdit(
      h.origin(),
      const Post(
        id: 9,
        postNumber: 1,
        username: 'sam',
        cooked: '',
        canEdit: true,
      ),
      category: bugs,
    )!;
    expect(plan.target, isA<TopicEditComposerTarget>());
    expect(plan.target.topicTitle, 'Stored title');
    expect(plan.target.initialCategoryId, 5);
    expect(plan.target.initialTags.single.name, 'bug');
    expect(plan.target.privateMessageTopic, isTrue);
    expect(plan.minimumRequiredTags, 2);
    final postOnly = h.owner.prepareEdit(h.origin(), _post, category: bugs)!;
    expect(postOnly.target, isA<PostEditComposerTarget>());
    expect(postOnly.minimumRequiredTags, 0);
  });

  test('edit plans follow topic and post edit permissions', () {
    final h = _Harness();
    addTearDown(h.dispose);
    final plan = h.owner.prepareEdit(
      h.origin(canEditTopic: false),
      const Post(
        id: 9,
        postNumber: 1,
        username: 'sam',
        cooked: '',
        canEdit: true,
      ),
    )!;
    expect(plan.target, isA<PostEditComposerTarget>());
    expect(
      h.owner.prepareEdit(
        h.origin(),
        const Post(id: 9, postNumber: 2, username: 'sam', cooked: ''),
      ),
      isNull,
    );
  });

  test('reply and quote openings require reply permission', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reply();
    final origin = h.origin(canReply: false);
    expect(h.owner.prepareReply(origin), isNull);
    expect(h.owner.prepareQuote(origin, _post, _quote), isNull);
  });

  for (final stale in ['reader', 'account']) {
    test('a stale $stale origin opens neither a reply nor a quote', () {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reply();
      final origin = h.origin();
      switch (stale) {
        case 'reader':
          h.readerCurrent = false;
        case 'account':
          h.lifecycle.invalidate(_site);
      }
      expect(h.owner.prepareReply(origin), isNull);
      expect(h.owner.prepareQuote(origin, _post, _quote), isNull);
    });
  }

  test('reply finds its topic editor behind another selected topic', () {
    final h = _Harness();
    addTearDown(h.dispose);
    final other = h.build(
      const ReplyComposerTarget(
        siteUrl: _site,
        topicId: 8,
        slug: '',
        topicTitle: 'Other',
        privateMessageTopic: false,
      ),
    );
    final retained = h.reply();
    h.selectedComposer = other;
    final plan = h.owner.prepareReply(h.origin());
    expect(plan, isA<ReuseReplyOpeningPlan>());
    expect((plan as ReuseReplyOpeningPlan).composer, same(retained));
  });

  test('another site editor for the same topic id is never reused', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.build(
      const ReplyComposerTarget(
        siteUrl: 'https://other.example',
        topicId: 7,
        slug: '',
        topicTitle: 'Other site',
        privateMessageTopic: false,
      ),
    );
    expect(h.owner.prepareReply(h.origin()), isA<CreateReplyOpeningPlan>());
    expect(h.owner.prepareQuote(h.origin(), _post, _quote)!.composer, isNull);
  });

  for (final retired in ['account', 'editor']) {
    test(
      'a reply started after $retired retirement restores nothing',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.local.saved['$_site::topic_7'] = const ComposerDraft(
          reply: 'Restored draft',
        ).encode();
        final reply =
            h.owner.prepareReply(h.origin()) as CreateReplyOpeningPlan;
        final composer = h.build(reply.target, drafting: true);
        switch (retired) {
          case 'account':
            h.lifecycle.invalidate(_site);
          case 'editor':
            h.members.remove(composer);
        }
        h.owner.startReply(reply, composer);
        await pumpEventQueue();
        expect(h.drafts.restoreTaskFor(composer), isNull);
        expect(composer.raw, isEmpty);
      },
    );
  }

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

  test('editor retirement during a credential read requests no raw', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final gate = Completer<void>();
    h.credentials.readGate = gate;
    final plan = h.owner.prepareEdit(h.origin(), _post)!;
    final composer = h.build(plan.target);
    final loading = h.owner.loadEditBody(plan, composer);
    await pumpEventQueue();
    h.members.remove(composer);
    gate.complete();
    await loading;
    expect(h.api.postFetches, isEmpty);
  });

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

  ExistingTopicOpeningOrigin origin({
    bool canReply = true,
    bool canEditTopic = true,
  }) => ExistingTopicOpeningOrigin(
    siteUrl: _site,
    lease: lifecycle.capture(_site),
    tabId: 'source-tab',
    reader: this,
    route: route,
    canReply: canReply,
    topic: TopicDetail(
      id: 7,
      title: 'Stored title',
      stream: const [9],
      canEdit: canEditTopic,
      categoryId: 5,
      privateMessage: true,
      tags: const [TopicTag(name: 'bug')],
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
