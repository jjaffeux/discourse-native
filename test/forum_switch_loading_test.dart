import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _firstSite = 'https://one.example';
const _secondSite = 'https://two.example';
const _firstTopic = Topic(id: 1, title: 'First forum topic', slug: 'first');
const _secondTopic = Topic(id: 2, title: 'Second forum topic', slug: 'second');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      '${platform.name} shows loading throughout forum homepage hydration',
      (tester) async {
        final api = _SwitchApi();
        await _pumpForums(tester, api, platform);
        final shell = ShellScope.read(
          tester.element(find.byType(MainContent).first),
        );
        expect(find.text(_firstTopic.title), findsOneWidget);

        shell.selectInstance(1);
        await tester.pump();

        expect(shell.currentInstance?.url, _secondSite);
        expect(shell.currentFeed, isNull);
        expect(api.siteConfigsRequested, contains(_secondSite));
        expect(api.secondFeedRequested, isFalse);
        _expectLoading();
        expect(find.text(_firstTopic.title), findsNothing);
        await tester.pump(const Duration(seconds: 2));
        _expectLoading();

        api.config.complete(const SiteConfig());
        await tester.pump();
        await tester.pump();

        expect(api.secondFeedRequested, isTrue);
        expect(shell.currentFeed?.loading, isTrue);
        _expectLoading();

        api.feed.complete(const TopicList(topics: [_secondTopic]));
        await tester.pumpAndSettle();

        expect(find.byType(TopicListLoadingSkeleton), findsNothing);
        expect(find.text(_secondTopic.title), findsOneWidget);
        expect(find.text(appL10n.notFound), findsNothing);

        shell.selectInstance(0);
        await tester.pumpAndSettle();
        expect(find.text(_firstTopic.title), findsOneWidget);
        expect(find.byType(TopicListLoadingSkeleton), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  for (final fails in [false, true]) {
    testWidgets(
      'forum loading resolves to ${fails ? 'the feed error' : 'the empty state'}',
      (tester) async {
        final api = _SwitchApi();
        await _pumpForums(tester, api, TargetPlatform.macOS);
        final shell = ShellScope.read(
          tester.element(find.byType(MainContent).first),
        );
        shell.selectInstance(1);
        await tester.pump();
        _expectLoading();
        api.config.complete(const SiteConfig());
        await tester.pump();
        await tester.pump();
        if (fails) {
          api.feed.completeError(StateError('Feed unavailable'));
        } else {
          api.feed.complete(const TopicList(topics: []));
        }
        await tester.pumpAndSettle();

        expect(find.byType(TopicListLoadingSkeleton), findsNothing);
        expect(find.text(appL10n.notFound), findsNothing);
        if (fails) {
          expect(shell.currentFeed?.error, isNotNull);
          expect(find.text(shell.currentFeed!.error!), findsOneWidget);
          expect(find.text(appL10n.retry), findsOneWidget);
        } else {
          expect(find.text(appL10n.nothingHereYet), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets('an unknown route still shows not found', (tester) async {
    final api = _SwitchApi();
    await _pumpForums(tester, api, TargetPlatform.macOS);
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.openContentInNewTab(
      const ContentRoute(
        destination: ExtensionDestination('unknown-page'),
        title: 'Unknown page',
        icon: DIcons.folder,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(appL10n.notFound), findsOneWidget);
    expect(find.byType(TopicListLoadingSkeleton), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

void _expectLoading() {
  expect(find.byType(TopicListLoadingSkeleton), findsOneWidget);
  expect(find.text(appL10n.notFound), findsNothing);
  expect(find.text(appL10n.theRequestedPageCouldNotBeFound), findsNothing);
}

Future<void> _pumpForums(
  WidgetTester tester,
  _SwitchApi api,
  TargetPlatform platform,
) async {
  await pumpShell(
    tester,
    platform == TargetPlatform.iOS ? phone : desktop,
    api: api,
    instances: [instance('one.example'), instance('two.example')],
  );
}

final class _SwitchApi extends FakeDiscourseApi {
  _SwitchApi()
    : super(
        siteConfigs: const {_firstSite: SiteConfig()},
        feeds: const {
          '/latest.json': [_firstTopic],
        },
      );

  final config = Completer<SiteConfig>();
  final feed = Completer<TopicList>();
  bool secondFeedRequested = false;

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    if (siteUrl == _secondSite) {
      siteConfigsRequested.add(siteUrl);
      return config.future;
    }
    return super.siteConfig(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    if (siteUrl == _secondSite) {
      secondFeedRequested = true;
      return feed.future;
    }
    return super.topicList(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
