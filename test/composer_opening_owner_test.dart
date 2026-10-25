import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/draft_coordinator.dart';
import 'package:discourse_native/src/shell/composer/opening_owner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _category = TopicCategory(
  id: 5,
  name: 'Bugs',
  color: '888888',
  slug: 'bugs',
  permission: 1,
  minimumRequiredTags: 2,
  topicTemplate: 'Describe the bug',
);
const _listed = UserDraft(key: 'new_topic_listed', sequence: 1, data: null);
const _ideas = TopicCategory(
  id: 6,
  name: 'Ideas',
  color: '888888',
  slug: 'ideas',
  permission: 1,
  topicTemplate: 'Pitch the idea',
);
final _tagRoute = ContentRoute.list(ListLink.parse('/tag/release')!);

void main() {
  test('setup refines a retained editor without selecting it again', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final plan = await harness.plan();
    final composer = harness.build(plan);
    final setup = harness.owner.start(plan, composer);
    final successor = harness.build(await harness.plan());
    expect(harness.selectedComposer, same(successor));
    expect(composer.taxonomyValidationMessage, isNull);
    expect(composer.text.text, isEmpty);

    harness.metadataReady.complete();
    await setup;
    await pumpEventQueue();

    expect(
      composer.taxonomyValidationMessage,
      'Choose at least 2 tags for this category.',
    );
    expect(composer.text.text, _category.topicTemplate);
    expect(successor.text.text, isEmpty);
    expect(harness.selectedComposer, same(successor));
  });

  for (final retirement in ['account', 'editor', 'owner']) {
    test('$retirement retirement suppresses delayed setup', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final plan = await harness.plan();
      final composer = harness.build(plan);
      final setup = harness.owner.start(plan, composer);
      switch (retirement) {
        case 'account':
          harness.lifecycle.invalidate(_site);
        case 'editor':
          harness.members.remove(composer);
        case 'owner':
          harness.owner.dispose();
      }
      final successor = harness.build(await harness.planUnchecked());
      successor.text.text = 'Successor body';
      harness.metadataReady.complete();
      await setup;
      await pumpEventQueue();

      expect(composer.taxonomyValidationMessage, isNull);
      expect(composer.text.text, isEmpty);
      expect(successor.text.text, 'Successor body');
    });
  }

  test(
    'late metadata keeps user text and the current category minimum',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final plan = await harness.plan();
      final composer = harness.build(plan);
      final setup = harness.owner.start(plan, composer);
      composer.text.text = 'User body';
      composer.setCategory(null);
      harness.metadataReady.complete();
      await setup;
      await pumpEventQueue();

      expect(composer.taxonomyValidationMessage, isNull);
      expect(composer.categoryId, isNull);
      expect(composer.text.text, 'User body');
    },
  );

  test(
    'a synchronous minimum-tags listener can retire setup before template',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final plan = await harness.plan();
      final composer = harness.build(plan);
      composer.addListener(() {
        if (composer.taxonomyValidationMessage != null) {
          harness.lifecycle.invalidate(_site);
        }
      });
      final setup = harness.owner.start(plan, composer);
      harness.metadataReady.complete();
      await setup;
      await pumpEventQueue();

      expect(
        composer.taxonomyValidationMessage,
        'Choose at least 2 tags for this category.',
      );
      expect(composer.text.text, isEmpty);
    },
  );

  for (final edited in [false, true]) {
    test('late tag seed respects user edits $edited', () async {
      final harness = _Harness(
        route: _tagRoute,
        api: FakeDiscourseApi(
          topicTagSearches: const {
            'release': TopicTagSearch(tags: [TopicTag(id: 7, name: 'release')]),
          },
        ),
      );
      addTearDown(harness.dispose);
      final plan = await harness.plan();
      final composer = harness.build(plan);
      final setup = harness.owner.start(plan, composer);
      if (edited) composer.setTags([const TopicTag(id: 8, name: 'authored')]);
      harness.metadataReady.complete();
      await setup;
      expect(composer.tags.single.name, edited ? 'authored' : 'release');
    });
  }

  test(
    'placeholder category adopts full taxonomy before minimum and template',
    () async {
      final harness = _Harness(
        emptyTaxonomy: true,
        api: FakeDiscourseApi(categoryFindResults: [_category]),
      );
      addTearDown(harness.dispose);
      final plan = await harness.plan();
      expect(plan.placeholderCategory?.topicTemplate, isNull);
      expect(harness.categoryFor(_site, 5), same(plan.placeholderCategory));
      final composer = harness.build(plan);
      final setup = harness.owner.start(plan, composer);
      harness.metadataReady.complete();
      await setup;
      await pumpEventQueue();
      expect(harness.api.categoryIdsRequested, [
        [5],
      ]);
      expect(harness.categoryFor(_site, 5), same(_category));
      expect(composer.text.text, _category.topicTemplate);
      expect(
        composer.taxonomyValidationMessage,
        'Choose at least 2 tags for this category.',
      );
    },
  );

  test(
    'canonical metadata notification can retire the exact editor setup',
    () async {
      final harness = _Harness(
        emptyTaxonomy: true,
        api: FakeDiscourseApi(categoryFindResults: [_category]),
      );
      addTearDown(harness.dispose);
      final plan = await harness.plan();
      final composer = harness.build(plan);
      final setup = harness.owner.start(plan, composer);
      harness.onPublish = () => harness.members.remove(composer);
      harness.metadataReady.complete();
      await setup;
      await pumpEventQueue();
      expect(composer.text.text, isEmpty);
      expect(composer.taxonomyValidationMessage, isNull);
    },
  );

  test(
    'origin replacement while admission awaits restoration refuses opening',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final first = harness.build(await harness.plan());
      harness.drafts.startNewDraft(first);
      final opening = harness.planOrNull();
      harness.originCurrent = false;

      expect(await opening, isNull);
      expect(harness.members, [first]);
    },
  );

  test(
    'selection change while admission awaits restoration refuses opening',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final first = harness.build(await harness.plan());
      harness.local.readGate = Completer<void>();
      harness.drafts.startRestore(first);
      final opening = harness.planOrNull();
      final other = harness.build(await harness.planUnchecked());
      harness.local.readGate!.complete();

      expect(await opening, isNull);
      expect(harness.selectedComposer, same(other));
    },
  );

  test('an opening captured under a retired account is refused', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final plan = await harness.plan();
    harness.lifecycle.invalidate(_site);

    expect(harness.owner.isCurrent(plan), isFalse);
    expect(await harness.planOrNull(origin: plan.origin), isNull);
  });

  test('a draft-backed editor is replaced without confirmation', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final first = harness.build(await harness.plan());
    harness.drafts.startNewDraft(first);
    first.text.text = 'Kept by its draft';

    expect(await harness.planOrNull(), isNotNull);
    expect(harness.confirmations, isEmpty);
  });

  test(
    'an editor busy loading at the request refuses replacement after it settles',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final first = harness.build(await harness.plan());
      harness.local.readGate = Completer<void>();
      harness.drafts.startRestore(first);
      first.beginLoadingBody();
      final opening = harness.planOrNull();
      first.loadedBody('');
      harness.local.readGate!.complete();

      expect(await opening, isNull);
      expect(harness.selectedComposer, same(first));
    },
  );

  for (final edit in [
    'no changes',
    'metadata changes',
    'body changes',
    'an unapplied draft',
  ]) {
    test(
      'an undrafted editor with $edit '
      '${edit == 'no changes' ? 'is replaced silently' : 'needs confirmation'}',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final first = harness.buildUndrafted(await harness.plan());
        switch (edit) {
          case 'metadata changes':
            first.setTags([const TopicTag(id: 8, name: 'authored')]);
          case 'body changes':
            first.text.text = 'Unsaved body';
          case 'an unapplied draft':
            first.protectUnappliedDraft(
              const ComposerDraft(reply: 'Stored elsewhere'),
              wasLocal: true,
            );
        }

        final plan = await harness.planOrNull();

        expect(plan, edit == 'no changes' ? isNotNull : isNull);
        expect(harness.confirmations, edit == 'no changes' ? isEmpty : [first]);
      },
    );
  }

  for (final pending in ['submitting', 'checking']) {
    test(
      'a draft-backed editor $pending its post refuses replacement',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final first = harness.build(await harness.plan());
        harness.drafts.startNewDraft(first);
        first.text.text = 'Posted body';
        const sent = _Sent(Object());
        first.beginSubmit(attempt: sent.attempt);
        first.retainSubmission(sent);
        if (pending == 'checking') first.checking();

        expect(await harness.planOrNull(), isNull);
        expect(harness.selectedComposer, same(first));
        expect(harness.confirmations, isEmpty);
      },
    );
  }

  for (final outcome in ['discards', 'keeps', 'selects past']) {
    test('confirmation that $outcome the editor '
        '${outcome == 'discards' ? 'admits' : 'refuses'} opening', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final first = harness.buildUndrafted(await harness.plan());
      first.text.text = 'Unsaved body';
      harness.onConfirm = (composer) async {
        if (outcome == 'keeps') return;
        harness.members.remove(composer);
        composer.dispose();
        harness.selectedComposer = null;
        if (outcome == 'selects past') {
          harness.buildUndrafted(await harness.planUnchecked());
        }
      };

      expect(
        await harness.planOrNull(),
        outcome == 'discards' ? isNotNull : isNull,
      );
    });
  }

  for (final (canCreateHere, hasSourceRoute, feed, category) in [
    (true, false, 'categories', 5),
    (false, true, 'latest', 5),
    (false, false, 'latest', null),
  ]) {
    test('revealed opening with creation here $canCreateHere and source route '
        '$hasSourceRoute returns to $feed in category $category', () async {
      final harness = _Harness()..canCreateTopicHere = canCreateHere;
      addTearDown(harness.dispose);
      final plan = (await harness.planOrNull(
        origin: harness.origin(
          feedId: 'categories',
          revealContent: true,
          hasSourceRoute: hasSourceRoute,
        ),
      ))!;

      expect(plan.target.originFeedId, feed);
      expect(plan.target.initialCategoryId, category);
    });
  }

  test('a listed draft opens under its own key', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final plan = (await harness.planOrNull(listedDraft: _listed))!;

    expect(plan.target.draftKey, _listed.key);
    expect(harness.nextKey, 0);
  });

  test('a failed draft restoration withholds the category template', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.local.readFailure = StateError('Draft storage unavailable');
    final plan = (await harness.planOrNull(listedDraft: _listed))!;
    final composer = harness.build(plan);
    final setup = harness.owner.start(plan, composer);
    harness.metadataReady.complete();
    await setup;
    await pumpEventQueue();

    expect(
      composer.taxonomyValidationMessage,
      'Choose at least 2 tags for this category.',
    );
    expect(composer.text.text, isEmpty);
  });

  for (final read in ['category', 'tag']) {
    test(
      'a $read read landing after account retirement publishes nothing',
      () async {
        final api = _GatedApi();
        final harness = _Harness(
          api: api,
          emptyTaxonomy: read == 'category',
          route: read == 'tag' ? _tagRoute : null,
        );
        addTearDown(harness.dispose);
        var published = 0;
        harness.onPublish = () => published++;
        final plan = await harness.plan();
        final composer = harness.build(plan);
        final setup = harness.owner.start(plan, composer);
        harness.metadataReady.complete();
        await pumpEventQueue();
        expect(api.waiting, 1);

        harness.lifecycle.invalidate(_site);
        api.readGate.complete();
        await setup;
        await pumpEventQueue();

        expect(published, 0);
        expect(composer.tags, isEmpty);
        expect(composer.text.text, isEmpty);
        if (read == 'category') {
          expect(harness.categoryFor(_site, 5), same(plan.placeholderCategory));
        }
      },
    );
  }

  test('a disabled exact tag is not seeded', () async {
    final harness = _Harness(
      route: _tagRoute,
      api: FakeDiscourseApi(
        topicTagSearches: const {
          'release': TopicTagSearch(
            tags: [TopicTag(id: 7, name: 'release', disabled: true)],
          ),
        },
      ),
    );
    addTearDown(harness.dispose);
    final plan = await harness.plan();
    final composer = harness.build(plan);
    final setup = harness.owner.start(plan, composer);
    harness.metadataReady.complete();
    await setup;

    expect(composer.tags, isEmpty);
  });

  test(
    'category change replaces the untouched template and drops refused tags',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.categories[6] = _ideas;
      final plan = await harness.plan();
      final composer = harness.build(plan);
      final setup = harness.owner.start(plan, composer);
      harness.metadataReady.complete();
      await setup;
      await pumpEventQueue();
      expect(composer.text.text, _category.topicTemplate);
      composer.setTags(const [
        TopicTag(id: 1, name: 'kept'),
        TopicTag(id: 2, name: 'refused'),
      ]);
      harness.tagResults = (term) => TopicTagSearch(
        tags: [TopicTag(id: term == 'kept' ? 1 : 2, name: term)],
        forbidden: term == 'refused',
      );

      await harness.owner.changeCategory(composer, 6);

      expect(composer.categoryId, 6);
      expect(composer.text.text, 'Pitch the idea');
      expect(composer.tags.map((tag) => tag.name), ['kept']);
    },
  );

  test(
    'a superseded category change stops checking its remaining tags',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.categories[6] = _ideas;
      final composer = harness.build(await harness.plan());
      composer.setTags(const [
        TopicTag(id: 1, name: 'first'),
        TopicTag(id: 2, name: 'second'),
      ]);
      harness.tagGate = Completer<void>();
      final change = harness.owner.changeCategory(composer, 6);
      await pumpEventQueue();
      composer.setCategory(5);
      harness.tagGate!.complete();
      await change;

      expect(harness.searchedTags, ['first']);
      expect(composer.tags.map((tag) => tag.name), ['first', 'second']);
    },
  );
}

final class _Harness
    implements ComposerOpeningPresentation, ComposerOpeningMetadata {
  _Harness({FakeDiscourseApi? api, this.route, bool emptyTaxonomy = false})
    : api = api ?? FakeDiscourseApi() {
    if (!emptyTaxonomy) categories[5] = _category;
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
    owner = ComposerOpeningOwner(
      presentation: this,
      metadata: this,
      drafts: drafts,
      credentials: credentials,
      categories: this.api,
      queries: this.api,
    );
  }

  final FakeDiscourseApi api;
  final ContentRoute? route;
  final categories = <int, TopicCategory>{};
  final local = _GatedDrafts();
  final confirmations = <ComposerController>[];
  Future<void>? Function(ComposerController composer)? onConfirm;
  TopicTagSearch Function(String term)? tagResults;
  Completer<void>? tagGate;
  final searchedTags = <String>[];
  void Function()? onPublish;
  final credentials = FakeAuthenticator()..keys[_site] = 'api-key';
  final lifecycle = SiteLifecycle();
  final metadataReady = Completer<void>();
  final members = <ComposerController>[];
  final allEditors = <ComposerController>[];
  late final ComposerDraftCoordinator drafts;
  late final ComposerOpeningOwner owner;
  bool disposed = false;
  bool originCurrent = true;
  int nextKey = 0;

  @override
  ComposerController? selectedComposer;

  @override
  bool canCreateTopicHere = true;

  NewTopicOpeningOrigin origin({
    String feedId = 'latest',
    bool revealContent = false,
    bool hasSourceRoute = false,
  }) {
    final route = this.route ?? ContentRoute.list(ListLink.parse('/c/bugs/5')!);
    return NewTopicOpeningOrigin(
      siteUrl: _site,
      lease: lifecycle.capture(_site),
      tabId: 'tab',
      feedId: feedId,
      content: route,
      route: route,
      defaultFeedId: 'latest',
      revealContent: revealContent,
      hasSourceRoute: hasSourceRoute,
    );
  }

  Future<NewTopicOpeningPlan?> planOrNull({
    NewTopicOpeningOrigin? origin,
    UserDraft? listedDraft,
  }) => owner.prepareNewTopic(
    origin ?? this.origin(),
    allocateDraftKey: () => 'new_topic_${++nextKey}',
    topicTitle: () => 'New topic',
    listedDraft: listedDraft,
  );

  Future<NewTopicOpeningPlan> plan() async => (await planOrNull())!;

  Future<NewTopicOpeningPlan> planUnchecked() async => NewTopicOpeningPlan(
    origin: origin(),
    target: NewTopicComposerTarget(
      siteUrl: _site,
      topicTitle: 'New topic',
      draftKey: 'new_topic_${++nextKey}',
    ),
    link: null,
    category: null,
    placeholderCategory: null,
    listedDraft: null,
  );

  ComposerController build(NewTopicOpeningPlan plan) {
    final session = drafts.openSession(plan.target);
    final composer = ComposerController(
      plan.target,
      onSaveDraft: session.save,
      onStageDraft: session.stage,
    );
    members.add(composer);
    allEditors.add(composer);
    selectedComposer = composer;
    drafts.attach(session, composer);
    return composer;
  }

  ComposerController buildUndrafted(NewTopicOpeningPlan plan) {
    final composer = ComposerController(plan.target);
    members.add(composer);
    allEditors.add(composer);
    selectedComposer = composer;
    return composer;
  }

  @override
  bool owns(ComposerController composer) => members.contains(composer);

  @override
  bool isCurrentOrigin(NewTopicOpeningOrigin origin) => originCurrent;

  @override
  Future<void>? confirmReplacement(ComposerController composer) {
    confirmations.add(composer);
    return onConfirm?.call(composer);
  }

  @override
  void publishOpening() {
    onPublish?.call();
  }

  @override
  TopicCategory? categoryFor(String siteUrl, int? categoryId) =>
      categories[categoryId];

  @override
  List<TopicCategory> categoriesFor(String siteUrl) =>
      categories.values.toList();

  @override
  void mergeCategories(String siteUrl, List<TopicCategory> categories) {
    for (final category in categories) {
      this.categories[category.id] = category;
    }
  }

  @override
  void Function(List<TopicCategory>) captureCategoryRead(String siteUrl) =>
      (categories) => mergeCategories(siteUrl, categories);

  @override
  Future<void> ensureForOpening(String siteUrl) => metadataReady.future;

  @override
  TopicComposerCapabilities capabilitiesFor(String siteUrl) =>
      const TopicComposerCapabilities(canTagTopics: true);

  @override
  Future<TopicTagSearch> searchTags(
    ComposerController composer,
    String term,
  ) async {
    searchedTags.add(term);
    await tagGate?.future;
    return tagResults?.call(term) ?? const TopicTagSearch();
  }

  void dispose() {
    disposed = true;
    owner.dispose();
    if (!metadataReady.isCompleted) metadataReady.complete();
    for (final composer in allEditors) {
      drafts.retire(composer);
      if (!composer.isDisposed) composer.dispose();
    }
    members.clear();
  }
}

final class _GatedDrafts extends FakeDraftStore {
  Completer<void>? readGate;
  Object? readFailure;

  @override
  Future<String?> read(String siteUrl, String draftKey) async {
    await readGate?.future;
    if (readFailure case final failure?) throw failure;
    return super.read(siteUrl, draftKey);
  }
}

final class _GatedApi extends FakeDiscourseApi {
  _GatedApi()
    : super(
        categoryFindResults: const [_category],
        topicTagSearches: const {
          'release': TopicTagSearch(tags: [TopicTag(id: 7, name: 'release')]),
        },
      );

  final readGate = Completer<void>();
  int waiting = 0;

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) async {
    waiting++;
    await readGate.future;
    return super.findCategories(siteUrl: siteUrl, ids: ids, apiKey: apiKey);
  }

  @override
  Future<TopicTagSearch> searchTopicTags({
    required String siteUrl,
    required String apiKey,
    required String term,
    int? categoryId,
    Iterable<int> selectedTagIds = const [],
    int limit = SiteConfig.defaultMaxTagSearchResults,
    String? clientId,
  }) async {
    waiting++;
    await readGate.future;
    return super.searchTopicTags(
      siteUrl: siteUrl,
      apiKey: apiKey,
      term: term,
      categoryId: categoryId,
    );
  }
}

final class _Sent implements ComposerSubmission {
  const _Sent(this.attempt);

  @override
  final Object attempt;
}
