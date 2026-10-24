import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:discourse_native/src/models/topic.dart';
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
        route: ContentRoute.list(ListLink.parse('/tag/release')!),
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
}

final class _Harness
    implements ComposerOpeningPresentation, ComposerOpeningMetadata {
  _Harness({FakeDiscourseApi? api, this.route, bool emptyTaxonomy = false})
    : api = api ?? FakeDiscourseApi() {
    if (!emptyTaxonomy) categories[5] = _category;
    drafts = ComposerDraftCoordinator(
      localStore: FakeDraftStore(),
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

  NewTopicOpeningOrigin origin() {
    final route = this.route ?? ContentRoute.list(ListLink.parse('/c/bugs/5')!);
    return NewTopicOpeningOrigin(
      siteUrl: _site,
      lease: lifecycle.capture(_site),
      tabId: 'tab',
      feedId: 'latest',
      content: route,
      route: route,
      originFeedId: 'latest',
      seedCategory: true,
    );
  }

  Future<NewTopicOpeningPlan?> planOrNull() => owner.prepareNewTopic(
    origin(),
    allocateDraftKey: () => 'new_topic_${++nextKey}',
    topicTitle: () => 'New topic',
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

  @override
  bool owns(ComposerController composer) => members.contains(composer);

  @override
  bool isCurrentOrigin(NewTopicOpeningOrigin origin) => originCurrent;

  @override
  Future<void>? confirmReplacement(ComposerController composer) => null;

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
  Future<void> ensureForOpening(String siteUrl) => metadataReady.future;

  @override
  TopicComposerCapabilities capabilitiesFor(String siteUrl) =>
      const TopicComposerCapabilities(canTagTopics: true);

  @override
  Future<TopicTagSearch> searchTags(
    ComposerController composer,
    String term,
  ) async => const TopicTagSearch();

  void dispose() {
    disposed = true;
    owner.dispose();
    if (!metadataReady.isCompleted) metadataReady.complete();
    for (final composer in allEditors) {
      drafts.retire(composer);
      composer.dispose();
    }
    members.clear();
  }
}
