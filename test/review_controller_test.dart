import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/review_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_lookup_failure.dart';
import 'package:discourse_native/src/data/write_failure.dart';
import 'package:discourse_native/src/models/reviewable.dart';
import 'package:discourse_native/src/shell/review_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/review_fixture.dart';

const site = 'https://forum.example/discuss';

ReviewablePage page({bool more = true}) =>
    ReviewablePage.fromJson(reviewListFixture(more: more));

/// A second page: one row already on screen and one new one.
ReviewablePage secondPage() {
  final json = reviewListFixture(more: false);
  final rows = (json['reviewables'] as List).cast<Map<String, dynamic>>();
  json['reviewables'] = [
    rows.first,
    {...rows[1], 'id': 91},
  ];
  return ReviewablePage.fromJson(json, offset: 10);
}

Reviewable detail(int id, {int? version}) =>
    reviewableFromDetailJson(reviewDetailFixture(id, version: version))!;

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeReviewApi api;
  late SiteLifecycle lifecycle;
  late List<int> unseen;

  ReviewController make({bool permitted = true, FakeCredentials? credentials}) {
    final controller = ReviewController(
      api: api,
      credentials: credentials ?? FakeCredentials(),
      lease: lifecycle.capture(site),
      siteUrl: site,
      permitted: permitted,
      onUnseenCount: unseen.add,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  ReviewableAction action(ReviewController owner, int id, String name) => owner
      .state
      .items
      .firstWhere((item) => item.id == id)
      .actions
      .firstWhere((action) => action.serverAction == name);

  Reviewable held(ReviewController owner, int id) =>
      owner.state.items.firstWhere((item) => item.id == id);

  setUp(() {
    api = FakeReviewApi();
    lifecycle = SiteLifecycle();
    unseen = [];
  });

  test('an account that may not review requests nothing', () async {
    final credentials = FakeCredentials();
    final owner = make(permitted: false, credentials: credentials);
    await owner.refresh();
    await owner.open(77);
    await owner.loadMore();
    expect(credentials.reads, 0);
    expect(api.lists, isEmpty);
    expect(api.items, isEmpty);
    expect(owner.state.loaded, isFalse);
  });

  test('the first page lands with its types and unseen count', () async {
    final owner = make();
    await owner.refresh();
    expect(owner.state.loaded, isTrue);
    expect(owner.state.items.map((item) => item.id), [77, 78, 79, 80]);
    expect(owner.state.hasMore, isTrue);
    expect(owner.state.types, contains('ReviewableUser'));
    expect(unseen, [1]);
    expect(api.lists.single, (const ReviewFilters(), 0));
  });

  test(
    'a refused queue is a permission state, not an error to retry',
    () async {
      api.listError = const SiteLookupException(
        SiteLookupFailure.unreachable,
        site,
        statusCode: 403,
      );
      final owner = make();
      await owner.refresh();
      expect(owner.state.failure, ReviewFailure.forbidden);
      expect(owner.state.loading, isFalse);
    },
  );

  group('paging', () {
    test('the next page appends without repeating a row on screen', () async {
      final owner = make();
      await owner.refresh();
      api.nextPage = secondPage();
      await owner.loadMore();
      expect(api.lists.last, (const ReviewFilters(), 10));
      expect(owner.state.items.map((item) => item.id), [77, 78, 79, 80, 91]);
      expect(owner.state.hasMore, isFalse);

      await owner.loadMore();
      expect(api.lists, hasLength(2));
    });

    test('only one next page is requested at a time', () async {
      final owner = make();
      await owner.refresh();
      api.deferLists = true;
      final first = owner.loadMore();
      await flush();
      await owner.loadMore();
      expect(api.pendingLists, hasLength(1));
      api.pendingLists.single.complete(secondPage());
      await first;
      expect(owner.state.loadingMore, isFalse);
    });

    test('a page for filters that were since changed is dropped', () async {
      final owner = make();
      await owner.refresh();
      api.deferLists = true;
      final stale = owner.loadMore();
      await flush();
      const users = ReviewFilters(type: 'ReviewableUser');
      final changed = owner.setFilters(users);
      await flush();
      expect(owner.state.items, isEmpty);
      expect(owner.state.loaded, isFalse);

      api.pendingLists[1].complete(page(more: false));
      await changed;
      api.pendingLists[0].complete(secondPage());
      await stale;

      expect(owner.state.filters, users);
      expect(owner.state.items.map((item) => item.id), [77, 78, 79, 80]);
      expect(owner.state.hasMore, isFalse);
      expect(owner.state.loadingMore, isFalse);
    });
  });

  test('of two refreshes only the later one is published', () async {
    api.deferLists = true;
    final owner = make();
    final first = owner.refresh();
    await flush();
    final second = owner.refresh();
    await flush();
    api.pendingLists[1].complete(page(more: false));
    await second;
    api.pendingLists[0].complete(ReviewablePage());
    await first;
    expect(owner.state.items, hasLength(4));
    expect(owner.state.loading, isFalse);
  });

  group('perform', () {
    test('a settled item leaves the list without another read', () async {
      final owner = make();
      await owner.refresh();
      api.performResult = ReviewablePerformResult.fromJson(
        reviewPerformFixture(77),
      );
      await owner.perform(held(owner, 77), action(owner, 77, 'agree_and_keep'));

      expect(api.performs.single, (77, 'agree_and_keep', 2));
      expect(owner.state.items.map((item) => item.id), [78, 79, 80]);
      expect(api.lists, hasLength(1));
      expect(
        owner.state.notice,
        isA<ReviewPerformed>().having(
          (n) => n.message,
          'message',
          'Flag agreed.',
        ),
      );
      expect(owner.state.performing, isNull);
      expect(unseen.last, 0);
    });

    test('the open item closes when it is settled', () async {
      final owner = make();
      await owner.refresh();
      api.itemValue = detail(77);
      await owner.open(77);
      expect(owner.state.selected?.id, 77);
      api.performResult = ReviewablePerformResult.fromJson(
        reviewPerformFixture(77),
      );
      await owner.perform(
        owner.state.selected!,
        owner.state.selected!.actions.first,
      );
      expect(owner.state.selectedId, isNull);
      expect(owner.state.selected, isNull);
    });

    test(
      'an item that stays pending keeps its row and takes the new lock',
      () async {
        final owner = make();
        await owner.refresh();
        api.performResult = ReviewablePerformResult.fromJson(
          reviewPerformFixture(77, version: 9, stillPending: true),
        );
        api.itemValue = detail(77, version: 9);
        await owner.perform(held(owner, 77), action(owner, 77, 'disagree'));
        expect(held(owner, 77).version, 9);
        expect(held(owner, 77).actions, isNotEmpty);
        expect(api.items, [77], reason: 'only the site lists what is left');
      },
    );

    test('other items the action settled take their new state', () async {
      final owner = make();
      await owner.refresh();
      api.performResult = ReviewablePerformResult.fromJson(
        reviewPerformFixture(77, updates: {78: 2}),
      );
      await owner.perform(held(owner, 77), action(owner, 77, 'delete_user'));
      expect(held(owner, 78).status, ReviewableStatus.rejected);
      expect(held(owner, 78).actions, isEmpty);
    });

    test(
      'a conflict tells the reader and shows the site\'s current item',
      () async {
        final owner = make();
        await owner.refresh();
        await owner.open(77);
        api.performError = const WriteException(
          WriteFailure.conflict,
          statusCode: 409,
        );
        api.itemValue = detail(77, version: 6);
        await owner.perform(
          held(owner, 77),
          action(owner, 77, 'agree_and_keep'),
        );

        expect(owner.state.notice, isA<ReviewConflict>());
        expect(api.performs, hasLength(1));
        expect(api.items.last, 77);
        expect(held(owner, 77).version, 6);
        expect(owner.state.selected?.version, 6);
        expect(owner.state.performing, isNull);
      },
    );

    test(
      'a refusal is reported in the site\'s words and not sent again',
      () async {
        final owner = make();
        await owner.refresh();
        api.performError = const WriteException(
          WriteFailure.validation,
          errors: ['You must claim items before acting on them.'],
          statusCode: 422,
        );
        await owner.perform(
          held(owner, 77),
          action(owner, 77, 'agree_and_keep'),
        );
        expect(
          owner.state.notice,
          isA<ReviewActionFailed>().having(
            (n) => n.message,
            'message',
            'You must claim items before acting on them.',
          ),
        );
        expect(api.performs, hasLength(1));
        expect(api.items, isEmpty);
        expect(owner.state.items, hasLength(4));
      },
    );

    test(
      'a lost answer rereads the item instead of repeating the write',
      () async {
        final owner = make();
        await owner.refresh();
        api.performError = const WriteException(WriteFailure.unreachable);
        api.itemValue = detail(77, version: 3);
        await owner.perform(
          held(owner, 77),
          action(owner, 77, 'agree_and_keep'),
        );
        expect(api.performs, hasLength(1));
        expect(api.items, [77]);
        expect(held(owner, 77).version, 3);

        api.performError = const WriteException(
          WriteFailure.unreachable,
          notSent: true,
        );
        await owner.perform(
          held(owner, 77),
          action(owner, 77, 'agree_and_keep'),
        );
        expect(api.performs, hasLength(2));
        expect(api.items, [77]);
      },
    );

    test(
      'a second action waits for the first, and browser actions never send',
      () async {
        final owner = make();
        await owner.refresh();
        api.performGate = Completer<ReviewablePerformResult>();
        final first = owner.perform(
          held(owner, 77),
          action(owner, 77, 'agree_and_keep'),
        );
        await flush();
        expect(owner.state.performing, '77-post-agree_and_keep');
        await owner.perform(held(owner, 78), action(owner, 78, 'approve_post'));
        expect(api.performs, hasLength(1));
        api.performGate!.complete(
          ReviewablePerformResult.fromJson(reviewPerformFixture(77)),
        );
        await first;

        await owner.perform(
          held(owner, 78),
          action(owner, 78, 'revise_and_reject_post'),
        );
        expect(api.performs, hasLength(1));
      },
    );
  });

  test(
    'a conflict on a row the reader left cannot stall the item they opened',
    () async {
      final owner = make();
      await owner.refresh();
      api.performGate = Completer<ReviewablePerformResult>();
      final write = owner.perform(
        held(owner, 77),
        action(owner, 77, 'agree_and_keep'),
      );
      await flush();
      final gate78 = api.itemGate = Completer<Reviewable?>();
      final opened = owner.open(78);
      await flush();
      api.itemGate = null;
      api.itemValue = detail(77, version: 6);
      api.performGate!.completeError(
        const WriteException(WriteFailure.conflict, statusCode: 409),
      );
      await write;
      gate78.complete(detail(78, version: 8));
      await opened;

      expect(owner.state.selectedId, 78);
      expect(owner.state.selected?.version, 8);
      expect(owner.state.selectedLoading, isFalse);
      expect(held(owner, 77).version, 6);
    },
  );

  test(
    'rows that left a pending queue move the next page up with them',
    () async {
      final owner = make();
      await owner.refresh();
      api.performResult = ReviewablePerformResult.fromJson(
        reviewPerformFixture(77),
      );
      await owner.perform(held(owner, 77), action(owner, 77, 'agree_and_keep'));
      expect(owner.state.nextOffset, 9);
      api.nextPage = secondPage();
      await owner.loadMore();
      expect(api.lists.last.$2, 9);
    },
  );

  test(
    'no action is sent for a type whose dialogs this app cannot know',
    () async {
      final owner = make();
      final plugin = Reviewable(
        id: 5,
        type: 'ReviewableCategoryExpertSuggestion',
        status: ReviewableStatus.pending,
        bundles: [
          ReviewableActionBundle(
            id: '5-approve',
            actions: const [
              ReviewableAction(
                id: '5-approve',
                serverAction: 'approve_category_expert',
                label: 'Approve',
              ),
            ],
          ),
        ],
      );
      await owner.perform(plugin, plugin.actions.single);
      expect(api.performs, isEmpty);
      expect(
        plugin.routeFor(plugin.actions.single),
        ReviewableActionRoute.browser,
      );
    },
  );

  group('stale reads after an action', () {
    test(
      'a refresh that began before the action cannot restore the item',
      () async {
        final owner = make();
        await owner.refresh();
        api.deferLists = true;
        final refresh = owner.refresh();
        await flush();
        api.performResult = ReviewablePerformResult.fromJson(
          reviewPerformFixture(77, updates: {78: 2}),
        );
        await owner.perform(held(owner, 77), action(owner, 77, 'delete_user'));
        api.pendingLists.single.complete(page(more: false));
        await refresh;

        expect(owner.state.items.map((item) => item.id), [78, 79, 80]);
        expect(held(owner, 78).status, ReviewableStatus.rejected);

        api.deferLists = false;
        api.nextPage = page(more: false);
        await owner.refresh();
        expect(owner.state.items.map((item) => item.id), [77, 78, 79, 80]);
      },
    );

    test(
      'an item read that began before the action cannot undo its lock',
      () async {
        final owner = make();
        await owner.refresh();
        final before = api.itemGate = Completer<Reviewable?>();
        final opened = owner.open(77);
        await flush();
        api.itemGate = null;
        api.itemValue = detail(77, version: 9);
        api.performResult = ReviewablePerformResult.fromJson(
          reviewPerformFixture(77, version: 9, stillPending: true),
        );
        await owner.perform(held(owner, 77), action(owner, 77, 'disagree'));
        before.complete(detail(77, version: 2));
        await opened;

        expect(held(owner, 77).version, 9);
        expect(owner.state.selected?.version, 9);
        expect(owner.state.selectedLoading, isFalse);
      },
    );
  });

  group('open item', () {
    test('the row shows at once and the site\'s copy replaces it', () async {
      final owner = make();
      await owner.refresh();
      api.itemGate = Completer<Reviewable?>();
      final opened = owner.open(77);
      await flush();
      expect(owner.state.selected?.version, 2);
      expect(owner.state.selectedLoading, isTrue);
      api.itemGate!.complete(detail(77, version: 4));
      await opened;
      expect(owner.state.selected?.version, 4);
      expect(held(owner, 77).version, 4);
      expect(owner.state.selectedLoading, isFalse);
    });

    test('a linked item outside the loaded page is read on its own', () async {
      final owner = make();
      api.itemValue = detail(79);
      await owner.open(79);
      expect(owner.state.selected?.accountUsername, 'newbie');
      expect(owner.state.items, isEmpty);
    });

    test('a missing item says so', () async {
      final owner = make();
      api.itemError = const SiteLookupException(
        SiteLookupFailure.unreachable,
        site,
        statusCode: 404,
      );
      await owner.open(5);
      expect(owner.state.selectedFailure, ReviewFailure.missing);
      expect(owner.state.selectedLoading, isFalse);
    });

    test(
      'a read for an item that was since closed or replaced is dropped',
      () async {
        final owner = make();
        await owner.refresh();
        api.itemGate = Completer<Reviewable?>();
        final first = owner.open(77);
        await flush();
        final firstGate = api.itemGate!;
        api.itemGate = Completer<Reviewable?>();
        final second = owner.open(78);
        await flush();
        api.itemGate!.complete(detail(78, version: 8));
        await second;
        firstGate.complete(detail(77, version: 7));
        await first;
        expect(owner.state.selected?.id, 78);
        expect(owner.state.selected?.version, 8);
        expect(held(owner, 77).version, 2);

        api.itemGate = Completer<Reviewable?>();
        final third = owner.open(79);
        await flush();
        owner.close();
        api.itemGate!.complete(detail(79));
        await third;
        expect(owner.state.selectedId, isNull);
        expect(owner.state.selected, isNull);
      },
    );
  });

  group('retirement', () {
    test('during the credential read sends nothing and clears state', () async {
      final credentials = FakeCredentials()..pending = Completer<String?>();
      final owner = make(credentials: credentials);
      final read = owner.refresh();
      lifecycle.invalidate(site);
      credentials.pending!.complete('key');
      await read;
      expect(api.lists, isEmpty);
      expect(owner.state.loading, isFalse);
      expect(owner.state.loaded, isFalse);
    });

    test('fences a perform result that arrives afterwards', () async {
      final owner = make();
      await owner.refresh();
      api.performGate = Completer<ReviewablePerformResult>();
      final item = held(owner, 77);
      final write = owner.perform(item, item.actions.first);
      await flush();
      lifecycle.invalidate(site);
      api.performGate!.complete(
        ReviewablePerformResult.fromJson(reviewPerformFixture(77)),
      );
      await write;
      expect(owner.state.items, isEmpty);
      expect(owner.state.notice, isNull);
      expect(owner.state.performing, isNull);
    });
  });
}

class FakeCredentials implements ApiCredentialReader {
  int reads = 0;
  Completer<String?>? pending;

  @override
  Future<String?> apiKeyFor(String _) {
    reads++;
    return pending?.future ?? Future.value('key');
  }

  @override
  Future<String> clientId() async => '';
}

class FakeReviewApi implements ReviewApi {
  final lists = <(ReviewFilters, int)>[];
  final items = <int>[];
  final performs = <(int, String, int)>[];
  final pendingLists = <Completer<ReviewablePage>>[];
  bool deferLists = false;
  ReviewablePage? nextPage;
  Object? listError;
  Reviewable? itemValue;
  Object? itemError;
  Completer<Reviewable?>? itemGate;
  ReviewablePerformResult? performResult;
  Object? performError;
  Completer<ReviewablePerformResult>? performGate;

  @override
  Future<ReviewablePage> list({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required ReviewFilters filters,
    int offset = 0,
  }) {
    lists.add((filters, offset));
    if (listError case final error?) return Future.error(error);
    if (deferLists) {
      final pending = Completer<ReviewablePage>();
      pendingLists.add(pending);
      return pending.future;
    }
    return Future.value(nextPage ?? page());
  }

  @override
  Future<Reviewable?> item({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int id,
  }) {
    items.add(id);
    if (itemError case final error?) return Future.error(error);
    return itemGate?.future ?? Future.value(itemValue);
  }

  @override
  Future<ReviewablePerformResult> perform({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int id,
    required String action,
    required int version,
  }) {
    performs.add((id, action, version));
    if (performError case final error?) return Future.error(error);
    return performGate?.future ??
        Future.value(performResult ?? ReviewablePerformResult(success: true));
  }
}
