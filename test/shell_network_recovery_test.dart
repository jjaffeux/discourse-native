import 'dart:io';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/network_status_banner.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _banner = ValueKey('network-status-banner');
const _neverConnected = SocketException(
  "Failed host lookup: 'meta.discourse.org'",
);
const _listed = [Topic(id: 7, title: 'A real topic', slug: 'a-real-topic')];

final class _FailingCategoriesApi extends FakeDiscourseApi {
  _FailingCategoriesApi() : super(feeds: {'/latest.json': _listed});

  bool categoriesFail = true;

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) {
    if (categoriesFail) {
      categoryRequests.add(siteUrl);
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return super.loadCategories(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      page: page,
    );
  }
}

void main() {
  final latest = Uri.parse('$_site/latest.json');

  void lose(FakeDiscourseApi api) => api.reachability.failed(
    latest,
    _neverConnected,
    api.reachability.dispatched(),
  );
  void regain(FakeDiscourseApi api) =>
      api.reachability.succeeded(latest, api.reachability.dispatched());

  ShellController shellOf(WidgetTester tester) =>
      ShellScope.read(tester.element(find.byType(AdaptiveShell)));

  Future<void> leaveAndReturn(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  TopicPayload detail() => topicPayload(
    id: 7,
    title: 'A real topic',
    posts: const [
      Post(
        id: 1,
        postNumber: 1,
        username: 'joffreyj',
        cooked: '<p>First post body</p>',
      ),
    ],
    stream: const [1],
  );

  for (final (platform, size) in [
    (TargetPlatform.macOS, desktop),
    (TargetPlatform.iOS, phone),
  ]) {
    testWidgets('a failed feed loads by itself once its site answers again', (
      tester,
    ) async {
      final api = FakeDiscourseApi(feeds: <String, List<Topic>>{});
      await pumpShell(tester, size, api: api);
      expect(topicListTitle('A real topic'), findsNothing);
      final requested = api.feedPaths.length;

      lose(api);
      await tester.pumpAndSettle();
      expect(find.byKey(_banner), findsOneWidget);
      expect(api.feedPaths, hasLength(requested));

      api.feeds['/latest.json'] = _listed;
      regain(api);
      await tester.pumpAndSettle();

      expect(api.feedPaths.skip(requested), ['/latest.json']);
      expect(topicListTitle('A real topic'), findsOneWidget);
      expect(find.byKey(_banner), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('a failed feed loads again when the app returns', (tester) async {
    final api = FakeDiscourseApi(feeds: <String, List<Topic>>{});
    await pumpShell(tester, desktop, api: api);
    final requested = api.feedPaths.length;

    api.feeds['/latest.json'] = _listed;
    await leaveAndReturn(tester);

    expect(api.feedPaths.skip(requested), ['/latest.json']);
    expect(topicListTitle('A real topic'), findsOneWidget);
  });

  testWidgets('a loaded feed is not asked for again by either signal', (
    tester,
  ) async {
    final api = FakeDiscourseApi(feeds: {'/latest.json': _listed});
    await pumpShell(tester, desktop, api: api);
    final requested = api.feedPaths.length;

    await leaveAndReturn(tester);
    lose(api);
    regain(api);
    await tester.pumpAndSettle();

    expect(api.feedPaths, hasLength(requested));
  });

  testWidgets('a rate-limited site is left alone by both signals', (
    tester,
  ) async {
    final api = FakeDiscourseApi(feeds: <String, List<Topic>>{});
    await pumpShell(tester, desktop, api: api);
    final requested = api.feedPaths.length;
    api.feeds['/latest.json'] = _listed;
    api.coolingDown.add(_site);

    await leaveAndReturn(tester);
    lose(api);
    regain(api);
    await tester.pumpAndSettle();

    expect(api.feedPaths, hasLength(requested));
    expect(topicListTitle('A real topic'), findsNothing);

    api.coolingDown.clear();
    await leaveAndReturn(tester);
    expect(api.feedPaths.skip(requested), ['/latest.json']);
  });

  testWidgets('an unreachable site is not asked for its feed on return', (
    tester,
  ) async {
    final api = FakeDiscourseApi(feeds: <String, List<Topic>>{});
    await pumpShell(tester, desktop, api: api);
    final requested = api.feedPaths.length;
    lose(api);

    await leaveAndReturn(tester);

    expect(api.feedPaths, hasLength(requested));
  });

  testWidgets('a topic that failed to open loads once its site answers', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: {'/latest.json': _listed},
      topics: <int, TopicPayload>{},
    );
    await pumpShell(tester, desktop, api: api);
    await tester.tap(topicListTitle('A real topic'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't load this topic"), findsOneWidget);
    final opened = api.topicsOpened.length;

    api.topics[7] = detail();
    lose(api);
    regain(api);
    await tester.pumpAndSettle();

    expect(api.topicsOpened.skip(opened), [7]);
    expect(find.textContaining("Couldn't load this topic"), findsNothing);
    expect(renderedText('First post body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a topic that opened is not asked for again', (tester) async {
    final api = FakeDiscourseApi(
      feeds: {'/latest.json': _listed},
      topics: {7: detail()},
    );
    await pumpShell(tester, desktop, api: api);
    await tester.tap(topicListTitle('A real topic'));
    await tester.pumpAndSettle();
    final opened = api.topicsOpened.length;

    lose(api);
    regain(api);
    await leaveAndReturn(tester);

    expect(api.topicsOpened, hasLength(opened));
  });

  testWidgets('a failed category list loads once its site answers', (
    tester,
  ) async {
    final api = _FailingCategoriesApi();
    await pumpShell(tester, desktop, api: api);
    final shell = shellOf(tester);
    await shell.loadCategories(_site, force: true);
    await tester.pumpAndSettle();
    expect(shell.categoryFeedFor(_site).error, isNotNull);
    final requested = api.categoryRequests.length;

    api.categoriesFail = false;
    lose(api);
    regain(api);
    await tester.pumpAndSettle();

    expect(api.categoryRequests, hasLength(requested + 1));
    expect(shell.categoryFeedFor(_site).error, isNull);
  });

  testWidgets('losing and regaining a site redraws only its notice', (
    tester,
  ) async {
    final api = FakeDiscourseApi(feeds: {'/latest.json': _listed});
    await pumpShell(tester, desktop, api: api);
    final shell = shellOf(tester);
    var notifications = 0;
    void count() => notifications++;
    shell.addListener(count);
    addTearDown(() => shell.removeListener(count));
    final notice = find.descendant(
      of: find.byType(NetworkStatusBanner),
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_UnreachableSiteNotice',
      ),
    );
    final noticeElement = tester.element(notice);
    bool insideNotice(Element element) {
      var inside = identical(element, noticeElement);
      element.visitAncestorElements((ancestor) {
        inside = inside || identical(ancestor, noticeElement);
        return !inside;
      });
      return inside;
    }

    final outside = <Element>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (!insideNotice(element)) outside.add(element);
      previous?.call(element, builtOnce);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    lose(api);
    await tester.pumpAndSettle();
    expect(find.byKey(_banner), findsOneWidget);
    regain(api);
    await tester.pumpAndSettle();
    expect(find.byKey(_banner), findsNothing);

    expect(notifications, 0);
    expect(outside, isEmpty);
    // The phone dock redraws on a timer of its own, which would be counted
    // here although no reachability change caused it.
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the notice ignores other sites and names its own outage', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final api = FakeDiscourseApi(feeds: {'/latest.json': _listed});
    await pumpShell(tester, desktop, api: api);

    api.reachability.failed(
      Uri.parse('https://team.discourse.org/latest.json'),
      _neverConnected,
      api.reachability.dispatched(),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_banner), findsNothing);

    lose(api);
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byKey(_banner)),
      isSemantics(
        isLiveRegion: true,
        label: "Can't connect to meta.discourse.org. Retrying automatically.",
      ),
    );
    handle.dispose();
  });

  testWidgets('with reduced motion the notice appears without animating', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final api = FakeDiscourseApi(feeds: {'/latest.json': _listed});
    await pumpShell(tester, desktop, api: api);

    lose(api);
    await tester.pump();

    expect(find.byKey(_banner), findsOneWidget);
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(_banner),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      1,
    );
    expect(tester.binding.transientCallbackCount, 0);

    regain(api);
    await tester.pump();

    expect(find.byKey(_banner), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
