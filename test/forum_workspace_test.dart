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

    test(
      'restores the native preferences destination without account data',
      () {
        final route = ContentRoute.preferences();

        final restored = ContentRoute.fromJson(_jsonMap(route.toJson()));

        expect(restored, route);
        expect(restored.isPreferences, isTrue);
        expect(restored.toJson().keys, ['id', 'title', 'icon']);
      },
    );

    test('the native Activity destination is durable', () {
      final route = ContentRoute.userActivity();

      final restored = ContentRoute.fromJson(_jsonMap(route.toJson()));

      expect(restored, route);
      expect(restored.id, 'activity');
      expect(restored.title, 'Activity');
      expect(restored.topicId, isNull);
      expect(restored.feedPath, isNull);
    });

    test('rejects persisted routes that could build unsafe requests', () {
      final ordinary = _routeJson(id: 'latest', title: 'Topics');

      for (final invalid in <Map<String, Object?>>[
        {...ordinary, 'topic_id': 0},
        {...ordinary, 'topic_id': -1},
        {...ordinary, 'topic_id': '42'},
        {...ordinary, 'post_number': 0},
        {...ordinary, 'post_number': -1},
        {...ordinary, 'feed_path': 'https://other.example/latest.json'},
        {...ordinary, 'feed_path': '//other.example/latest.json'},
        {...ordinary, 'feed_path': '/latest.json#private'},
        {...ordinary, 'feed_path': '/latest'},
        {
          ...ordinary,
          'feed_path': '/${'a' * ContentRoute.maximumFeedPathLength}.json',
        },
      ]) {
        expect(
          () => ContentRoute.fromJson(Map<String, dynamic>.from(invalid)),
          throwsFormatException,
          reason: '$invalid',
        );
      }

      final restored = ContentRoute.fromJson({
        ...ordinary,
        'feed_path': '/c/support/12.json?page=2',
      });
      expect(restored.feedPath, '/c/support/12.json?page=2');
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

    test('sanitizes corrupt persisted viewport anchors', () {
      final restored = ForumWorkspace.tryFromJson({
        'site_url': 'https://forum.example',
        'account_identity': 'anonymous',
        'active_tab_id': 'kept-tab',
        'tabs': [
          {
            'id': 'kept-tab',
            'root_destination_id': 'latest',
            'content_stack': [_routeJson(id: 'latest', title: 'Topics')],
            'anchors': {
              'latest': {
                'kind': 'topic',
                'item_id': 9,
                'offset': double.infinity,
              },
              'not-a-route': {'kind': 'topic', 'item_id': 10},
              'negative-item': {'kind': 'feed', 'item_id': -1, 'offset': 0},
            },
          },
        ],
      });

      expect(restored, isNotNull);
      expect(restored!.tabs.single.anchors, {
        'latest': const ForumTabAnchor(kind: 'topic', itemId: 9),
      });
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

    test('bounds restored tabs and routes while preserving active history', () {
      const activeTabIndex = ForumWorkspace.maximumTabs + 3;
      final restored = ForumWorkspace.tryFromJson({
        'site_url': 'https://forum.example',
        'account_identity': 'anonymous',
        'active_tab_id': 'tab-$activeTabIndex',
        'tabs': [
          for (var tab = 0; tab <= activeTabIndex; tab++)
            {
              'id': 'tab-$tab',
              'root_destination_id': 'latest',
              'content_stack': [
                _routeJson(id: 'latest', title: 'Topics'),
                for (
                  var route = 1;
                  route <= ForumTab.maximumContentRoutes + 5;
                  route++
                )
                  _routeJson(id: 'topic-$route', title: 'Topic $route'),
              ],
            },
        ],
      });

      expect(restored, isNotNull);
      expect(restored!.tabs, hasLength(ForumWorkspace.maximumTabs));
      expect(restored.activeTabId, 'tab-$activeTabIndex');
      expect(restored.activeTab.contentStack, hasLength(64));
      expect(restored.activeTab.contentStack.first.id, 'latest');
      expect(restored.activeTab.contentStack[1].id, 'topic-7');
      expect(restored.activeTab.contentStack.last.id, 'topic-69');
    });

    test('equal restored tabs with anchors share one hash code', () {
      Map<String, Object?> tabJson() => {
        'id': 'anchored-tab',
        'root_destination_id': 'latest',
        'content_stack': [_routeJson(id: 'latest', title: 'Topics')],
        'anchors': {
          'latest': {'kind': 'feed', 'item_id': 17, 'offset': 0.25},
        },
      };

      final first = ForumTab.tryFromJson(_jsonMap(tabJson()));
      final second = ForumTab.tryFromJson(_jsonMap(tabJson()));

      expect(first, second);
      expect(first.hashCode, second!.hashCode);
    });

    test('discarded restored routes cannot retain orphaned anchors', () {
      final restored = ForumTab.tryFromJson({
        'id': 'bounded',
        'root_destination_id': 'latest',
        'content_stack': [
          _routeJson(id: 'latest', title: 'Topics'),
          for (
            var route = 1;
            route <= ForumTab.maximumContentRoutes + 1;
            route++
          )
            _routeJson(id: 'topic-$route', title: 'Topic $route'),
        ],
        'anchors': {
          'latest': {'kind': 'feed', 'item_id': 1},
          'topic-1': {'kind': 'topic', 'item_id': 1},
          'topic-65': {'kind': 'topic', 'item_id': 65},
          'never-a-route': {'kind': 'topic', 'item_id': 99},
        },
      });

      expect(restored, isNotNull);
      expect(restored!.anchors.keys, ['latest', 'topic-65']);
    });
  });
}

Map<String, dynamic> _jsonMap(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

Map<String, Object?> _routeJson({required String id, required String title}) =>
    {'id': id, 'title': title, 'icon': DIcons.comments.name};
