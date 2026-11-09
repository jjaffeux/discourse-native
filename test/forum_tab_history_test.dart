import 'dart:convert';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'typed kind and mode changes create distinct desktop visits under one key',
    () {
      for (final (before, after) in [
        (
          const PageDestination(CorePage.users),
          const ExtensionDestination('users'),
        ),
        (
          const FeedDestination(key: 'shared', mode: TopicListMode.latest),
          const FeedDestination(key: 'shared', mode: TopicListMode.unread),
        ),
      ]) {
        ContentRoute route(ContentDestination destination) => ContentRoute(
          destination: destination,
          title: 'Same',
          icon: ContentRoute.topicList(TopicListMode.latest).icon,
        );
        final first = ForumTab(
          id: 'typed',
          rootDestinationId: 'root',
          contentStack: [route(before)],
        );
        final second = first.navigate(contentStack: [route(after)]);
        expect(second.currentContent.destination.identity, after.identity);
        expect(second.backHistory, hasLength(1));
        expect(
          second.goBack().currentContent.destination.identity,
          before.identity,
        );
      }
    },
  );

  ForumTab initial() => ForumTab(
    id: 'history',
    rootDestinationId: 'latest',
    contentStack: [ContentRoute.topicList(TopicListMode.latest)],
  );

  group('the list before a directory page', () {
    final latest = ContentRoute.topicList(TopicListMode.latest);
    ContentRoute page(CorePage core) => ContentRoute(
      destination: PageDestination(core),
      title: core.name,
      icon: latest.icon,
    );
    final categories = page(CorePage.categories);
    ContentRoute list(String slug, int id) => ContentRoute(
      destination: FeedDestination.fromPath(
        key: 'category-$id',
        path: '/c/$slug/$id.json',
      ),
      title: slug,
      icon: latest.icon,
    );
    final baking = list('baking', 1);
    final cooking = list('cooking', 2);
    ForumTab startingAt(ContentRoute route) => ForumTab(
      id: 'directory',
      rootDestinationId: route.id,
      contentStack: [route],
    );
    ForumTab visit(ForumTab tab, ContentRoute route) =>
        tab.navigate(rootDestinationId: route.id, contentStack: [route]);

    test('is the list the tab was just showing', () {
      final tab = visit(startingAt(baking), categories);
      expect(tab.listBefore(CorePage.categories), baking);
    });

    test('is found under the topic read from it and past other pages', () {
      final reading = startingAt(baking).push(_topic(1));
      final tab = visit(visit(reading, page(CorePage.users)), categories);
      expect(tab.listBefore(CorePage.categories), baking);
    });

    test('stops at an unfiltered list rather than an older filtered one', () {
      final tab = visit(visit(startingAt(baking), latest), categories);
      expect(tab.listBefore(CorePage.categories), latest);
      expect(tab.listBefore(CorePage.categories)?.categoryId, isNull);
    });

    test('ignores what the page itself opened while it stays mounted', () {
      final arrived = visit(startingAt(baking), categories);
      final covered = arrived.push(cooking);
      expect(covered.listBefore(CorePage.categories), baking);
    });

    test('is null for a tab that never came from a list', () {
      expect(startingAt(categories).listBefore(CorePage.categories), isNull);
      expect(startingAt(baking).listBefore(CorePage.categories), isNull);
    });
  });

  test('a reader beside its list keeps that only while it stays a reader', () {
    final list = ContentRoute.topicList(TopicListMode.latest);
    final beside = ForumTab(
      id: 'beside',
      rootDestinationId: 'latest',
      contentStack: [list, _topic(1)],
      readsBesideSource: true,
    );

    expect(
      ForumTab.tryFromJson(jsonDecode(jsonEncode(beside.toJson()))),
      beside,
    );
    expect(beside.push(_topic(2)).readsBesideSource, isTrue);

    final returned = beside.navigate(contentStack: [list]);
    expect(returned.readsBesideSource, isFalse);
    expect(returned.push(_topic(2)).readsBesideSource, isFalse);
  });

  test('retains the 50 most recent visits in both directions', () {
    var tab = initial();
    for (var id = 1; id <= 60; id++) {
      tab = tab.navigate(contentStack: [_topic(id)]);
    }
    expect(tab.backHistory, hasLength(50));
    for (var id = 59; id >= 10; id--) {
      tab = tab.goBack();
      expect(tab.currentContent.topicId, id);
    }
    expect(tab.canGoBack, isFalse);
    expect(tab.goBack(), same(tab));
    expect(tab.forwardHistory, hasLength(50));

    for (var id = 11; id <= 60; id++) {
      tab = tab.goForward();
      expect(tab.currentContent.topicId, id);
    }
    expect(tab.canGoForward, isFalse);
    expect(tab.goForward(), same(tab));
    expect(tab.backHistory, hasLength(50));
  });

  test('bounds each restored direction and discards the farthest entries', () {
    var tab = ForumTab.tryFromJson({
      ...initial().toJson(),
      'back_history': [
        {
          'root_destination_id': 'latest',
          'content_stack': [
            {
              'id': 'topic-0',
              'topic_id': 0,
              'title': 'Invalid',
              'icon': 'comments',
            },
          ],
        },
        for (var id = 1; id < 60; id++) _location(id).toJson(),
        {'root_destination_id': 'broken'},
      ],
      'forward_history': [
        'broken',
        for (var id = 120; id > 60; id--) _location(id).toJson(),
      ],
    })!;
    expect(tab.backHistory, hasLength(50));
    expect(tab.backHistory.first.contentStack.single.topicId, 10);
    expect(tab.forwardHistory, hasLength(50));
    expect(tab.forwardHistory.first.contentStack.single.topicId, 110);
    tab = tab.goBack();
    expect(tab.currentContent.topicId, 59);
    expect(tab.forwardHistory, hasLength(50));
    expect(tab.forwardHistory.first.contentStack.single.topicId, 109);
    tab = tab.goForward().goForward();
    expect(tab.currentContent.topicId, 61);
    expect(tab.backHistory, hasLength(50));
    expect(tab.backHistory.first.contentStack.single.topicId, 11);
  });

  test('a new visit clears Forward and prunes abandoned anchors', () {
    var tab = initial().navigate(contentStack: [_topic(1)]);
    tab = tab
        .navigate(contentStack: [_topic(2)])
        .copyWith(
          anchors: const {
            'topic-1': ForumTabAnchor(kind: 'topic', itemId: 7),
            'topic-2': ForumTabAnchor(kind: 'topic', itemId: 9),
          },
        );
    tab = tab.goBack().navigate(contentStack: [_topic(3)]);
    expect(tab.canGoForward, isFalse);
    expect(tab.anchors.keys, ['topic-1']);
    expect(tab.goBack().currentContent.topicId, 1);
  });

  test('reselecting the same location preserves both directions', () {
    final tab = initial().push(_topic(1)).push(_topic(2)).goBack();
    expect(tab.navigate(contentStack: tab.contentStack), same(tab));
    expect(tab.canGoForward, isTrue);
  });

  test('round trips parent routes, destinations, and scroll anchors', () {
    final latest = initial().currentContent;
    final top = ContentRoute.topicList(TopicListMode.topYearly);
    final tab = initial()
        .navigate(contentStack: [latest, _topic(1)])
        .navigate(rootDestinationId: 'top', contentStack: [top, _topic(2)])
        .copyWith(
          anchors: const {
            'topic-1': ForumTabAnchor(kind: 'topic', itemId: 7, offset: 0.5),
          },
        )
        .goBack();
    final restored = ForumTab.tryFromJson(
      jsonDecode(jsonEncode(tab.toJson())),
    )!;
    expect(restored, tab);
    expect(restored.hashCode, tab.hashCode);
    expect(restored.rootDestinationId, 'latest');
    expect(restored.contentStack, [latest, _topic(1)]);
    expect(restored.anchors['topic-1']?.offset, 0.5);
    expect(restored.goForward().rootDestinationId, 'top');
    expect(restored.goForward().contentStack, [top, _topic(2)]);
    expect(restored.goBack().canGoBack, isFalse);
  });

  test('rewrites routes in both directions without recording a visit', () {
    final tab = initial()
        .navigate(contentStack: [_topic(1)])
        .navigate(contentStack: [_topic(2)])
        .goBack();
    final updated = tab.rewriteRoutes(
      (route) => route.topicId != null
          ? ContentRoute.topic(
              topicId: route.topicId!,
              slug: 'updated',
              title: 'Updated',
            )
          : route,
    );
    expect(updated.backHistory.length, tab.backHistory.length);
    expect(updated.forwardHistory.length, tab.forwardHistory.length);
    expect(updated.goForward().currentContent.title, 'Updated');
    expect(updated.goForward().goBack().currentContent.title, 'Updated');
    expect(updated.rewriteRoutes((route) => route), same(updated));
    // An entry with no rewritten route keeps its instance and its encoding.
    expect(updated.backHistory.single, same(tab.backHistory.single));
    expect(
      updated.forwardHistory.single,
      isNot(same(tab.forwardHistory.single)),
    );
  });
}

ContentRoute _topic(int id) =>
    ContentRoute.topic(topicId: id, slug: 'topic-$id', title: 'Topic $id');

ForumTabLocation _location(int id) =>
    ForumTabLocation(rootDestinationId: 'latest', contentStack: [_topic(id)]);
