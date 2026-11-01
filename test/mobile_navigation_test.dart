import 'dart:convert';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

ForumTabLocation page(String id) => ForumTabLocation(
  rootDestinationId: id,
  contentStack: [
    ContentRoute(
      destination: ExtensionDestination(id),
      title: id,
      icon: DIcons.layerGroup,
    ),
  ],
);

void main() {
  test(
    'updating the current visit keeps its identity and surrounding history',
    () {
      final navigation = MobileNavigation();
      navigation.push(page('latest'));
      navigation.push(page('reader'));
      final readerEntry = navigation.entryId;
      navigation.push(page('next'));
      final nextEntry = navigation.entryId;
      expect(navigation.goBack(), isTrue);
      navigation.updateCurrent(page('updated reader'));
      expect(navigation.entryId, readerEntry);
      expect(navigation.location, page('updated reader'));
      expect(navigation.goForward(), isTrue);
      expect(navigation.entryId, nextEntry);
      expect(navigation.goBack(), isTrue);
      expect(navigation.entryId, readerEntry);
      expect(navigation.location, page('updated reader'));
      expect(navigation.goBack(), isTrue);
      expect(navigation.location, page('latest'));
    },
  );

  test('updating a restored root visit does not create a new entry', () {
    final navigation = MobileNavigation();
    navigation.startJourney(tab: MobileTab.topics, root: page('reader'));
    final entry = navigation.entryId;
    navigation.updateCurrent(page('updated reader'));
    navigation.push(page('updated reader'));
    expect(navigation.entryId, entry);
    expect(navigation.canGoBack, isFalse);
    expect(navigation.location, page('updated reader'));
  });

  test(
    'typed kind and mode changes retain distinct mobile visits under one key',
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
        ForumTabLocation location(ContentDestination destination) =>
            ForumTabLocation(
              rootDestinationId: 'root',
              contentStack: [
                ContentRoute(
                  destination: destination,
                  title: 'Same',
                  icon: DIcons.list,
                ),
              ],
            );
        final navigation = MobileNavigation();
        navigation.push(location(before));
        final firstId = navigation.entryId;
        navigation.push(location(after));
        expect(navigation.entryId, isNot(firstId));
        expect(navigation.goBack(), isTrue);
        expect(
          navigation.location!.contentStack.single.destination.identity,
          before.identity,
        );
        expect(navigation.goForward(), isTrue);
        expect(
          navigation.location!.contentStack.single.destination.identity,
          after.identity,
        );
      }
    },
  );

  test('content tabs root their own history and isolate earlier journeys', () {
    final navigation = MobileNavigation();
    navigation.startJourney(tab: MobileTab.topics, root: page('latest'));
    expect(navigation.canGoBack, isFalse);
    navigation.push(page('topic'));
    expect(navigation.goBack(), isTrue);
    expect(navigation.location, page('latest'));
    navigation.selectTab(MobileTab.messages);
    navigation.startJourney(tab: MobileTab.messages, root: page('messages'));
    expect(navigation.tab, MobileTab.messages);
    expect(navigation.canGoBack, isFalse);
    expect(navigation.canGoForward, isFalse);
    navigation.selectTab(const MobileTab.panel('chat'));
    navigation.returnToPanelRoot();
    navigation.push(page('channel'));
    expect(navigation.goBack(), isTrue);
    expect(navigation.atRoot, isTrue);
    expect(navigation.tab, const MobileTab.panel('chat'));
    navigation.startJourney(tab: MobileTab.topics, root: page('latest'));
    expect(navigation.tab, MobileTab.topics);
    expect(navigation.panelOwner, isNull);
    expect(navigation.canGoForward, isFalse);
  });

  test('hydrated display metadata updates without creating a visit', () {
    final navigation = MobileNavigation();
    navigation.push(page('topic'));
    final entryId = navigation.entryId;
    final historyId = navigation.historyId;
    final rootId = navigation.previousEntryId;
    final hydrated = ForumTabLocation(
      rootDestinationId: 'topic',
      contentStack: const [
        ContentRoute(
          destination: ExtensionDestination('topic'),
          title: 'Loaded title',
          icon: DIcons.layerGroup,
        ),
      ],
    );
    navigation.updateCurrent(hydrated);
    expect(navigation.location, hydrated);
    expect(navigation.entryId, entryId);
    expect(navigation.historyId, historyId);
    navigation.goBack();
    expect(navigation.atRoot, isTrue);
    expect(navigation.entryId, rootId);
    expect(navigation.nextEntryId, entryId);
    navigation.goForward();
    expect(navigation.location, hydrated);
    expect(navigation.entryId, entryId);
  });

  test(
    'ordinary navigation keeps actual visits separate from document ancestry',
    () {
      final navigation = MobileNavigation();
      navigation.selectPanel('chat');
      final root = navigation.entryId;
      final source = page('source').contentStack.single;
      final reader = page('reader').contentStack.single;
      navigation.replaceCurrent(
        ForumTabLocation(
          rootDestinationId: 'source',
          contentStack: [source, reader],
        ),
      );
      expect(navigation.previousEntryId, same(root));
      expect(navigation.state.visits, hasLength(2));
      expect(navigation.goBack(), isTrue);
      expect(navigation.atRoot, isTrue);
      expect(navigation.canGoBack, isFalse);
      expect(navigation.goForward(), isTrue);
      expect(navigation.location!.contentStack, [source, reader]);
    },
  );

  test('replacement updates this visit and clears a forward branch', () {
    final navigation = MobileNavigation();
    navigation.push(page('latest'));
    navigation.push(page('topic'));
    navigation.goBack();
    final entryId = navigation.entryId;
    navigation.replaceCurrent(page('new'));
    navigation.push(page('new'));
    expect(navigation.location, page('new'));
    expect(navigation.canGoForward, isFalse);
    expect(navigation.entryId, isNot(entryId));
    expect(navigation.nextEntryId, isNull);
    navigation.goBack();
    expect(navigation.atRoot, isTrue);
  });

  test('root, content, back and forward form one mobile journey', () {
    final navigation = MobileNavigation();
    navigation.returnToPanelRoot();
    navigation.selectPanel('chat');
    navigation.push(page('channel'));
    navigation.push(page('thread'));
    expect(navigation.goBack(), isTrue);
    expect(navigation.location, page('channel'));
    // Projecting a restored location must not create another visit.
    navigation.push(page('channel'));
    expect(navigation.goBack(), isTrue);
    expect(navigation.atRoot, isTrue);
    expect(navigation.panelOwner, 'chat');
    expect(navigation.goBack(), isFalse);
    expect(navigation.goForward(), isTrue);
    expect(navigation.location, page('channel'));
    expect(navigation.goForward(), isTrue);
    expect(navigation.location, page('thread'));
  });

  test('new destinations after back discard forward history', () {
    final navigation = MobileNavigation();
    navigation.push(page('topics'));
    navigation.push(page('topic'));
    navigation.goBack();
    navigation.push(page('category'));
    expect(navigation.goForward(), isFalse);
    navigation.goBack();
    expect(navigation.location, page('topics'));
    navigation.goBack();
    expect(navigation.atRoot, isTrue);
  });

  test('site/account and sidebar-mode changes isolate history', () {
    final navigation = MobileNavigation();
    navigation.push(page('private'));
    navigation.openSidebar();
    final privateHistoryId = navigation.historyId;
    navigation.reset();
    expect(navigation.sidebarOpen, isFalse);
    expect(navigation.historyId, isNot(privateHistoryId));
    expect(navigation.canGoForward, isFalse);
    expect(navigation.canGoBack, isFalse);
    navigation.push(page('topics'));
    navigation.goBack();
    final historyId = navigation.historyId;
    navigation.selectPanel('chat');
    expect(navigation.historyId, isNot(historyId));
    expect(navigation.canGoForward, isFalse);
    navigation.reset();
    navigation.push(page('link'));
    expect(navigation.panelOwner, isNull);
    navigation.goBack();
    expect(navigation.atRoot, isTrue);
    expect(navigation.canGoBack, isFalse);
  });

  test('bounded history always retains the sidebar root', () {
    final navigation = MobileNavigation();
    for (var i = 0; i < MobileNavigation.maximumPages + 20; i++) {
      navigation.push(page('$i'));
    }
    var count = 0;
    while (navigation.goBack()) {
      count++;
    }
    expect(count, MobileNavigation.maximumPages);
    expect(navigation.atRoot, isTrue);
  });

  test('a restored stack keeps its root and bounds its parent history', () {
    final routes = [
      for (var i = 0; i < ForumTab.maximumContentRoutes; i++)
        page('$i').contentStack.single,
    ];
    final navigation = MobileNavigation();
    navigation.startJourney(
      tab: MobileTab.topics,
      root: ForumTabLocation(rootDestinationId: '0', contentStack: routes),
    );
    final currentId = navigation.entryId;
    expect(navigation.location?.contentStack.last, routes.last);
    expect(navigation.goBack(), isTrue);
    expect(navigation.location?.contentStack.last, routes[routes.length - 2]);
    expect(navigation.goForward(), isTrue);
    expect(navigation.entryId, currentId);
    var count = 0;
    while (navigation.goBack()) {
      count++;
    }
    expect(count, MobileNavigation.maximumPages);
    expect(navigation.location?.contentStack, [routes.first]);
    expect(navigation.canGoBack, isFalse);
    navigation.reset();
    navigation.push(page('private'));
    expect(navigation.previousLocation, isNull);
    expect(navigation.canGoForward, isFalse);
  });

  test('a saved place and its visits survive a JSON round trip', () {
    final navigation = MobileNavigation()
      ..returnToPanelRoot()
      ..selectPanel('chat');
    navigation.push(page('chat-c-10'));
    navigation.push(page('chat-t-10-4'));
    expect(navigation.goBack(), isTrue);

    final saved = MobileNavigationState.tryFromJson(
      jsonDecode(jsonEncode(navigation.state)),
    );
    expect(saved, navigation.state);

    final relaunched = MobileNavigation();
    expect(relaunched.restore(state: saved!), isTrue);
    expect(relaunched.tab, const MobileTab.panel('chat'));
    expect(relaunched.panelOwner, 'chat');
    expect(relaunched.location, page('chat-c-10'));
    expect(relaunched.canGoForward, isTrue);
    expect(relaunched.goBack(), isTrue);
    expect(relaunched.atRoot, isTrue);
    expect(relaunched.canGoBack, isFalse);

    // The same owner keeps the restored visits; another owner starts over.
    relaunched.returnToPanelRoot();
    expect(relaunched.tab, const MobileTab.panel('chat'));
    relaunched.reset();
    expect(relaunched.tab, MobileTab.topics);
  });

  test('a saved state from an unknown build is declined', () {
    for (final json in <Object?>[
      null,
      {'place': 'topics', 'visits': <Object?>[], 'index': 0},
      {
        'place': 'topics',
        'visits': [null],
        'index': 1,
      },
      {
        'place': 'topics',
        'visits': [null, null],
        'index': 0,
      },
    ]) {
      expect(MobileNavigationState.tryFromJson(json), isNull, reason: '$json');
    }
    final navigation = MobileNavigation();
    expect(
      navigation.restore(
        state: MobileNavigationState(
          place: 'sideways',
          visits: const [null],
          index: 0,
        ),
      ),
      isFalse,
    );
    expect(navigation.tab, MobileTab.topics);
  });
}
