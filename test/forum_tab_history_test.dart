import 'dart:convert';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ForumTab initial() => ForumTab(
    id: 'history',
    rootDestinationId: 'latest',
    contentStack: [ContentRoute.topicList(TopicListMode.latest)],
  );

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
        for (var id = 0; id < 60; id++) _location(id).toJson(),
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
