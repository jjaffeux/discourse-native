import 'dart:convert';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContentRoute persistence', () {
    test('round-trips every durable route field', () {
      const route = ContentRoute(
        id: 'topic-42',
        title: 'A durable topic',
        icon: DIcons.folder,
        subtitle: 'Topic subtitle',
        color: Color(0xFF123456),
        topicId: 42,
        slug: 'a-durable-topic',
        postNumber: 7,
        feedPath: '/c/durable/42.json',
      );

      final restored = ContentRoute.fromJson(_jsonMap(route.toJson()));

      expect(restored.id, route.id);
      expect(restored.title, route.title);
      expect(restored.icon, route.icon);
      expect(restored.subtitle, route.subtitle);
      expect(restored.color, route.color);
      expect(restored.topicId, route.topicId);
      expect(restored.slug, route.slug);
      expect(restored.postNumber, route.postNumber);
      expect(restored.feedPath, route.feedPath);
    });
  });

  group('ForumWorkspace persistence', () {
    test('round-trips tabs, stacks, anchors, and the active tab', () {
      final workspace = ForumWorkspace(
        siteUrl: 'https://forum.example',
        accountIdentity: 'user:42',
        activeTabId: 'topic-tab',
        tabs: [
          ForumTab(
            id: 'topics-tab',
            rootDestinationId: 'latest',
            contentStack: const [
              ContentRoute(
                id: 'latest',
                title: 'Topics',
                icon: DIcons.layerGroup,
              ),
            ],
            anchors: const {'latest': ForumTabAnchor(kind: 'feed', itemId: 17)},
          ),
          ForumTab(
            id: 'topic-tab',
            rootDestinationId: 'latest',
            contentStack: const [
              ContentRoute(
                id: 'latest',
                title: 'Topics',
                icon: DIcons.layerGroup,
              ),
              ContentRoute(
                id: 'topic-42',
                title: 'A durable topic',
                icon: DIcons.comments,
                subtitle: 'Topic subtitle',
                color: Color(0xFF654321),
                topicId: 42,
                slug: 'a-durable-topic',
                postNumber: 7,
              ),
            ],
            anchors: const {
              'topic-42': ForumTabAnchor(
                kind: 'topic',
                itemId: 4207,
                offset: 0.375,
              ),
            },
          ),
        ],
      );

      final restored = ForumWorkspace.tryFromJson(_jsonMap(workspace.toJson()));

      expect(restored, workspace);
      expect(restored!.activeTab.id, 'topic-tab');
      expect(restored.activeTab.currentContent.topicId, 42);
      expect(restored.activeTab.currentContent.color, const Color(0xFF654321));
      expect(
        restored.activeTab.anchors['topic-42'],
        const ForumTabAnchor(kind: 'topic', itemId: 4207, offset: 0.375),
      );
    });

    test('repairs valid pieces of a partially corrupt workspace', () {
      final restored = ForumWorkspace.tryFromJson({
        'site_url': 'https://forum.example',
        'account_identity': 'anonymous',
        'active_tab_id': 'discarded-tab',
        'tabs': [
          {
            'id': 'kept-tab',
            'root_destination_id': 'latest',
            'content_stack': [
              _routeJson(id: 'latest', title: 'Topics'),
              {'id': 'broken-route', 'title': 'Missing icon'},
              _routeJson(id: 'topic-9', title: 'Still valid'),
            ],
            'anchors': {
              'latest': {'kind': 'feed', 'item_id': 9, 'offset': 0.25},
              'broken': {'kind': '', 'item_id': 'not-an-int'},
              'not-a-map': 'discard me',
            },
          },
          {
            // The first valid tab wins when persisted ids are duplicated.
            'id': 'kept-tab',
            'root_destination_id': 'drafts',
            'content_stack': [_routeJson(id: 'drafts', title: 'Drafts')],
          },
          {
            'id': 'discarded-tab',
            'root_destination_id': 'latest',
            'content_stack': const <Object>[],
          },
          'not-a-tab',
        ],
      });

      expect(restored, isNotNull);
      expect(restored!.tabs, hasLength(1));
      expect(restored.tabs.single.id, 'kept-tab');
      expect(restored.tabs.single.contentStack.map((route) => route.id), [
        'latest',
        'topic-9',
      ]);
      expect(restored.tabs.single.anchors, {
        'latest': const ForumTabAnchor(kind: 'feed', itemId: 9, offset: 0.25),
      });
      expect(restored.activeTabId, 'kept-tab');
    });

    test('discards a tab whose root destination is empty', () {
      final restored = ForumWorkspace.tryFromJson({
        'site_url': 'https://forum.example',
        'account_identity': 'anonymous',
        'active_tab_id': 'valid-tab',
        'tabs': [
          {
            'id': 'invalid-tab',
            'root_destination_id': '',
            'content_stack': [_routeJson(id: 'latest', title: 'Topics')],
          },
          {
            'id': 'valid-tab',
            'root_destination_id': 'latest',
            'content_stack': [_routeJson(id: 'latest', title: 'Topics')],
          },
        ],
      });

      expect(restored, isNotNull);
      expect(restored!.tabs.map((tab) => tab.id), ['valid-tab']);
      expect(restored.activeTabId, 'valid-tab');
    });
  });
}

Map<String, dynamic> _jsonMap(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

Map<String, Object?> _routeJson({required String id, required String title}) =>
    {'id': id, 'title': title, 'icon': DIcons.comments.name};
