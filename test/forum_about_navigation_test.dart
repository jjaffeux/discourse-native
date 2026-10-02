import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_about.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:discourse_native/src/shell/forum_about_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const siteUrl = 'https://forum.example/discuss';
const otherUrl = 'https://other.example';

class _AboutApi extends FakeDiscourseApi {
  _AboutApi()
    : super(
        siteConfigs: {
          siteUrl: SiteConfig(
            plugins: PluginData.none.withValue(
              voiceSettingsDataKey,
              const VoiceClientConfig(enabled: true),
            ),
          ),
          otherUrl: const SiteConfig(),
        },
      );

  final requests = <({String url, String? apiKey, String? clientId})>[];
  final gates = <String, Completer<ForumAbout>>{};

  @override
  Future<ForumAbout> forumAbout({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    requests.add((url: siteUrl, apiKey: apiKey, clientId: clientId));
    return gates[siteUrl]?.future ??
        ForumAbout(
          title: 'About $siteUrl',
          stats: const {'voice_users_7_days': 17},
        );
  }
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.linux]) {
    testWidgets('forum About is native and public on $platform', (
      tester,
    ) async {
      final launched = watchBrowser(tester);
      final api = _AboutApi();
      final auth = FakeAuthenticator();
      // Orphaned credentials must never authenticate an anonymous instance.
      auth.keys[siteUrl] = 'orphan-key';
      await pumpShell(
        tester,
        platform == TargetPlatform.iOS ? phone : desktop,
        instances: const [DiscourseInstance(url: siteUrl, title: 'Forum')],
        api: api,
        authenticator: auth,
        revealMobileNavigation: false,
      );
      final shell = ShellScope.read(tester.element(primaryMainContent));
      expect(shell.openCorePageUrl('$siteUrl/about'), isTrue);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.isForumAbout, isTrue);
      expect(find.byType(ForumAboutPage), findsOneWidget);
      expect(api.requests.single.apiKey, isNull);
      expect(api.requests.single.clientId, isNull);
      expect(find.text('17 voice participants'), findsOneWidget);
      expect(launched, isEmpty);
      await shell.refreshCurrentTab();
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(2));
      await tester.tap(find.text('Open full About page'));
      await tester.pumpAndSettle();
      expect(launched, ['$siteUrl/about']);
      expect(shell.openCorePageUrl('https://unrelated.example/about'), isFalse);
      expect(shell.openCorePageUrl('$siteUrl/about/extra'), isFalse);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('desktop refresh reaches each About panel independently', (
    tester,
  ) async {
    final api = _AboutApi();
    await pumpShell(
      tester,
      desktop,
      api: api,
      instances: const [DiscourseInstance(url: siteUrl, title: 'Forum')],
    );
    final shell = ShellScope.read(tester.element(primaryMainContent));
    shell.openCorePageUrl('$siteUrl/about');
    await tester.pumpAndSettle();
    final mainTab = shell.activeTabId!;
    shell.openLinkInPanel('$siteUrl/about', panel: ForumPanel.secondary);
    await tester.pumpAndSettle();
    expect(find.byType(ForumAboutPage), findsNWidgets(2));
    expect(api.requests, hasLength(2));
    await shell.refreshCurrentTab();
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(3));
    shell.selectTab(mainTab);
    await tester.pumpAndSettle();
    await shell.refreshCurrentTab();
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(4));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('site change drops an in-flight About response', (tester) async {
    final api = _AboutApi();
    final gate = Completer<ForumAbout>();
    api.gates[siteUrl] = gate;
    await pumpShell(
      tester,
      desktop,
      api: api,
      instances: const [
        DiscourseInstance(url: siteUrl, title: 'Forum'),
        DiscourseInstance(url: otherUrl, title: 'Other'),
      ],
    );
    final shell = ShellScope.read(tester.element(primaryMainContent));
    shell.openCorePageUrl('$siteUrl/about');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    shell.openCorePageUrl('$otherUrl/about');
    await tester.pumpAndSettle();
    gate.complete(const ForumAbout(title: 'Old delayed identity'));
    await tester.pumpAndSettle();
    expect(find.text('About $otherUrl'), findsOneWidget);
    expect(find.text('Old delayed identity'), findsNothing);
    expect(find.text('17 voice participants'), findsNothing);
    expect(api.requests.map((r) => r.url), [siteUrl, otherUrl]);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'sign-out clears private identity and rejects delayed account data',
    (tester) async {
      final api = _AboutApi();
      final gate = Completer<ForumAbout>();
      api.gates[siteUrl] = gate;
      final auth = FakeAuthenticator();
      auth.keys[siteUrl] = 'account-key';
      await pumpShell(
        tester,
        desktop,
        api: api,
        authenticator: auth,
        instances: const [
          DiscourseInstance(
            url: siteUrl,
            title: 'Private forum',
            loginRequired: true,
            user: DiscourseUser(id: 7, username: 'reader'),
          ),
        ],
      );
      final shell = ShellScope.read(tester.element(primaryMainContent));
      shell.openCorePageUrl('$siteUrl/about');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(api.requests.single.apiKey, 'account-key');
      expect(api.requests.single.clientId, isNotNull);
      await shell.disconnectInstance(siteUrl);
      await tester.pumpAndSettle();
      shell.openCorePageUrl('$siteUrl/about');
      await tester.pumpAndSettle();
      gate.complete(const ForumAbout(title: 'Signed-out account data'));
      await tester.pumpAndSettle();
      expect(find.text('Signed-out account data'), findsNothing);
      expect(shell.instanceFor(siteUrl)?.isConnected, isFalse);
      expect(shell.instanceFor(siteUrl)?.loginRequired, isTrue);
      expect(api.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
