import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

ForumTabLocation page(String id) => ForumTabLocation(
  rootDestinationId: id,
  contentStack: [ContentRoute(id: id, title: id, icon: DIcons.layerGroup)],
);

void main() {
  test('hydrated display metadata updates without creating a visit', () {
    final navigation = MobileNavigation();
    navigation.synchronize(owner: 'forum', location: page('topic'));
    final entryId = navigation.entryId;
    final historyId = navigation.historyId;
    final rootId = navigation.previousEntryId;
    final hydrated = ForumTabLocation(
      rootDestinationId: 'topic',
      contentStack: const [
        ContentRoute(
          id: 'topic',
          title: 'Loaded title',
          icon: DIcons.layerGroup,
        ),
      ],
    );
    navigation.synchronize(owner: 'forum', location: hydrated);
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

  test('replacement updates this visit and clears a forward branch', () {
    final navigation = MobileNavigation();
    navigation.synchronize(owner: 'forum', location: page('latest'));
    navigation.synchronize(owner: 'forum', location: page('topic'));
    navigation.goBack();
    final entryId = navigation.entryId;
    navigation.replaceCurrent(page('new'));
    navigation.synchronize(owner: 'forum', location: page('new'));
    expect(navigation.location, page('new'));
    expect(navigation.canGoForward, isFalse);
    expect(navigation.entryId, isNot(entryId));
    expect(navigation.nextEntryId, isNull);
    navigation.goBack();
    expect(navigation.atRoot, isTrue);
  });

  test('aggregate participates in the same back and forward history', () {
    final navigation = MobileNavigation();
    navigation.synchronize(owner: 'forum', location: null, aggregate: true);
    expect(navigation.atRoot, isFalse);
    expect(navigation.aggregate, isTrue);
    navigation.goBack();
    expect(navigation.atRoot, isTrue);
    navigation.goForward();
    expect(navigation.aggregate, isTrue);
    navigation.synchronize(owner: 'forum', location: page('topic'));
    navigation.goBack();
    expect(navigation.aggregate, isTrue);
  });
  test('root, content, back and forward form one mobile journey', () {
    final navigation = MobileNavigation();
    navigation.synchronize(owner: ('forum', 'user'), location: null);
    navigation.selectPanel('chat');
    navigation.synchronize(owner: ('forum', 'user'), location: page('channel'));
    navigation.synchronize(owner: ('forum', 'user'), location: page('thread'));
    expect(navigation.goBack(), isTrue);
    expect(navigation.location, page('channel'));
    // Projecting a restored location must not create another visit.
    navigation.synchronize(owner: ('forum', 'user'), location: page('channel'));
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
    navigation.synchronize(owner: 'forum', location: page('topics'));
    navigation.synchronize(owner: 'forum', location: page('topic'));
    navigation.goBack();
    navigation.synchronize(owner: 'forum', location: page('category'));
    expect(navigation.goForward(), isFalse);
    navigation.goBack();
    expect(navigation.location, page('topics'));
    navigation.goBack();
    expect(navigation.atRoot, isTrue);
  });

  test('site/account and sidebar-mode changes isolate history', () {
    final navigation = MobileNavigation();
    navigation.synchronize(owner: ('forum', 'one'), location: page('private'));
    final privateHistoryId = navigation.historyId;
    navigation.synchronize(owner: ('forum', 'two'), location: null);
    expect(navigation.historyId, isNot(privateHistoryId));
    expect(navigation.canGoForward, isFalse);
    expect(navigation.canGoBack, isFalse);
    navigation.synchronize(owner: ('forum', 'two'), location: page('topics'));
    navigation.goBack();
    final historyId = navigation.historyId;
    navigation.selectPanel('chat');
    expect(navigation.historyId, isNot(historyId));
    expect(navigation.canGoForward, isFalse);
    navigation.synchronize(owner: ('another', 'two'), location: page('link'));
    expect(navigation.panelOwner, isNull);
    navigation.goBack();
    expect(navigation.atRoot, isTrue);
    expect(navigation.canGoBack, isFalse);
  });

  test('bounded history always retains the sidebar root', () {
    final navigation = MobileNavigation();
    for (var i = 0; i < MobileNavigation.maximumPages + 20; i++) {
      navigation.synchronize(owner: 'forum', location: page('$i'));
    }
    var count = 0;
    while (navigation.goBack()) {
      count++;
    }
    expect(count, MobileNavigation.maximumPages);
    expect(navigation.atRoot, isTrue);
  });
}
