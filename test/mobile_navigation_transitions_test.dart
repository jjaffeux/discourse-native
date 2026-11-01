import 'package:discourse_native/discourse_plugin_sdk.dart'
    show
        PluginRouteNavigationHost,
        PluginRoutePresentationHost,
        PluginAccountEventsHost,
        PluginModule,
        PluginManifest,
        PluginDescriptor,
        PluginId,
        PluginRegistrar,
        PluginSessionContribution,
        PluginSessionLifecycle,
        corePluginRouteNavigationPort,
        corePluginAccountEventsPort;
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';

const _platforms = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
});

void _expectChrome() {
  expect(
    find.byKey(const ValueKey('mobile-menu-button')).hitTestable(),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('mobile-search-button')).hitTestable(),
    findsOneWidget,
  );
  expect(find.byKey(const ValueKey('mobile-bottom-bar')), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('search cancel preserves the topic visit and its source list', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    shell.openTopic(
      const Topic(id: 7, title: 'Shared topic card', slug: 'shared'),
    );
    await tester.pumpAndSettle();
    final list = find.byType(TopicListView, skipOffstage: false);
    final topic = find.byType(TopicView, skipOffstage: false);
    final listState = tester.state(list);
    final visit = shell.mobileNavigation.entryId;

    shell.pushContent(ContentRoute.search());
    await tester.pumpAndSettle();
    expect(tester.state(list), same(listState));
    expect(topic, findsOneWidget);
    expect(shell.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.entryId, visit);
    expect(tester.state(list), same(listState));
    expect(topic, findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets(
    'chat restores chrome after topic and search dismissal',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      shell.selectMobilePanel('chat');
      await tester.pumpAndSettle();
      expect(find.byType(ChatMobileSidebar), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
      shell.openSearchResult(
        const SearchPostHit(
          postId: 1,
          topicId: 7,
          postNumber: 1,
          topicTitle: 'Shared topic card',
          topicSlug: 'shared',
          username: 'reader',
          excerpt: SearchExcerpt([]),
        ),
        words: 'shared',
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 7);
      expect(shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-search-back')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatMobileSidebar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-header')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mobile-bottom-bar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
  for (final source in ['topics', 'messages', 'users', 'chat', 'voice']) {
    for (final dismissal in ['cancel', 'system back', 'swipe']) {
      testWidgets('$source search returns with chrome after $dismissal', (
        tester,
      ) async {
        final shell = await pumpMobileShellFixture(
          tester,
          voice: source == 'voice',
        );
        switch (source) {
          case 'chat':
            shell.selectMobilePanel(source);
          case 'voice':
            shell.selectMobileDestination(
              const MobileTab.destination('voice-rooms'),
              const SidebarDestination(
                id: 'voice-rooms',
                label: 'Voice rooms',
                icon: DIcons.microphoneLines,
              ),
            );
          case 'messages' || 'users':
            shell.selectMobileDestination(
              source == 'messages' ? MobileTab.messages : MobileTab.users,
              SidebarDestination(id: source, label: source, icon: DIcons.list),
            );
        }
        await tester.pumpAndSettle();
        final originalRoute = shell.currentContent;
        final root = shell.mobileNavigation.entryId;
        await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
        await tester.enterText(
          find.byKey(ForumSearch.inputKey),
          'remember this',
        );
        await tester.pump(const Duration(milliseconds: 400));
        switch (dismissal) {
          case 'cancel':
            await tester.tap(find.byKey(const ValueKey('mobile-search-back')));
          case 'system back':
            await tester.binding.handlePopRoute();
          case 'swipe':
            await tester.dragFrom(const Offset(2, 400), const Offset(360, 0));
        }
        await tester.pumpAndSettle();
        expect(shell.mobileNavigation.entryId, root);
        expect(
          shell.currentContent?.destination.identity,
          originalRoute?.destination.identity,
        );
        _expectChrome();
        expect(find.byKey(ForumSearch.inputKey), findsNothing);
        expect(shell.search.panelOpen, isFalse);

        expect(shell.handleForward(), isTrue);
        await tester.pumpAndSettle();
        expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
        expect(shell.globalSearch.query, 'remember this');
        expect(shell.handleBack(), isTrue);
        await tester.pumpAndSettle();
        _expectChrome();
        await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
        if (source == 'chat') {
          expect(shell.activeTab!.contentStack, hasLength(1));
          expect(shell.activeTab!.contentStack.single.isGlobalSearch, isTrue);
        }
        expect(shell.mobileNavigation.canGoForward, isFalse);
        expect(tester.takeException(), isNull);
      }, variant: _platforms);
    }
  }

  for (final departure in [
    'push',
    'replace',
    'topic',
    'topic link',
    'topic post',
    'page link',
    'channel',
  ]) {
    testWidgets('chat root starts a fresh $departure after returning to root', (
      tester,
    ) async {
      final shell = await pumpMobileShellFixture(tester);
      shell.selectMobilePanel('chat');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
      await tester.pumpAndSettle();
      shell.handleBack();
      await tester.pumpAndSettle();
      if (departure.startsWith('topic')) {
        shell.openTopic(
          const Topic(id: 7, title: 'Shared topic card', slug: 'shared'),
        );
        await tester.pumpAndSettle();
        shell.handleBack();
        await tester.pumpAndSettle();
        expect(shell.activeTab!.currentContent.topicId, 7);
      }
      expect(shell.currentContent, isNull);
      _expectChrome();
      switch (departure) {
        case 'push':
          shell.pushContent(ContentRoute.topicList(TopicListMode.latest));
        case 'replace':
          shell.replaceCurrentContent(
            ContentRoute.topicList(TopicListMode.latest),
          );
        case 'topic':
          shell.openTopic(
            const Topic(id: 7, title: 'Shared topic card', slug: 'shared'),
          );
        case 'topic link':
          expect(
            shell.openTopicUrl('https://meta.discourse.org/t/shared/7'),
            isTrue,
          );
        case 'topic post':
          shell.openTopicPost(
            siteUrl: 'https://meta.discourse.org',
            topicId: 7,
            postNumber: 1,
          );
        case 'page link':
          expect(shell.openCorePageUrl('https://meta.discourse.org/u'), isTrue);
        case 'channel':
          expect(shell.openChatChannel(10), isTrue);
      }
      await tester.pumpAndSettle();
      expect(shell.mobilePane, MobilePane.content);
      expect(shell.currentContent, isNotNull);
      expect(shell.activeTab!.contentStack, hasLength(1));
      expect(shell.mobileNavigation.canGoForward, isFalse);
      expect(shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(shell.currentContent, isNull);
      expect(find.byType(ChatMobileSidebar), findsOneWidget);
      _expectChrome();
      expect(tester.takeException(), isNull);
    }, variant: _platforms);
  }
  testWidgets('plugin content opened from Chat is visible until covered', (
    tester,
  ) async {
    final probe = _NavigationProbe();
    final shell = await pumpMobileShellFixture(
      tester,
      pluginManifest: PluginManifest([
        ...bundledWidgetTestManifest.modules,
        probe,
      ]),
    );
    shell.selectMobilePanel('chat');
    await tester.pumpAndSettle();
    final host = probe.navigation as PluginRoutePresentationHost;
    expect(probe.navigation.currentContent, isNull);
    expect(host.currentContentVisible, isFalse);
    probe.navigation.pushContent(ContentRoute.topicList(TopicListMode.latest));
    await tester.pumpAndSettle();
    expect(host.currentContentVisible, isTrue);
    expect(shell.mobileNavigation.panelOwner, 'chat');
    shell.toggleMobileSidebar();
    await tester.pumpAndSettle();
    expect(host.currentContentVisible, isFalse);
    shell.closeMobileSidebar();
    await tester.pumpAndSettle();
    expect(host.currentContentVisible, isTrue);
    shell.handleBack();
    await tester.pumpAndSettle();
    expect(host.currentContentVisible, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets(
    'an unavailable boundary keeps navigation while search is parked',
    (tester) async {
      final probe = _NavigationProbe();
      final shell = await pumpMobileShellFixture(
        tester,
        pluginManifest: PluginManifest([
          ...bundledWidgetTestManifest.modules,
          probe,
        ]),
      );
      await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.isGlobalSearch, isTrue);
      probe.events.markSiteUnreachable('https://meta.discourse.org');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('unavailable-forum-gate')),
        findsOneWidget,
      );
      _expectChrome();
      expect(tester.takeException(), isNull);
    },
    variant: _platforms,
  );
}

final class _NavigationProbe implements PluginModule {
  late PluginRouteNavigationHost navigation;
  late PluginAccountEventsHost events;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('navigation-probe'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (bindings, _) {
        navigation = bindings.require(corePluginRouteNavigationPort);
        events = bindings.require(corePluginAccountEventsPort);
        return PluginSessionContribution(lifecycle: _ProbeLifecycle());
      },
      requires: const [
        corePluginRouteNavigationPort,
        corePluginAccountEventsPort,
      ],
    );
  }
}

final class _ProbeLifecycle extends PluginSessionLifecycle {}
