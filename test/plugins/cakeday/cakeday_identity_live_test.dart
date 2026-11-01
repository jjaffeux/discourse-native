import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_controller.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_data.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_plugin.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/user_card_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/fakes.dart';
import 'cakeday_fixture.dart';

void main() {
  testWidgets(
    'hidden Cakeday leaves no space and real hosts react to settings and the shared day clock',
    (tester) async {
      final f = CakedayFixture(enabled: false);
      final installed = PluginInstaller.install(
        PluginManifest([_Module(f.controller)]),
      );
      const user = DiscourseUser(id: 7, username: 'reader');
      final api = FakeDiscourseApi(
        models: installed.models,
        user: user,
        feeds: const {'/latest.json': []},
        siteConfigs: {cakedaySite: f.config.value},
      );
      final instances = [
        instance(
          'forum.example/community',
          user: user,
        ).copyWith(config: f.config.value),
      ];
      final shell = ShellController(
        plugins: installed,
        instanceStore: FakeInstanceStore(instances),
        api: api,
        authenticator: FakeAuthenticator.signedIn(instances, site: api),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      await tester.runAsync(shell.load);
      final post = installed.models.post({
        'id': 1,
        'post_number': 1,
        'user_id': 7,
        'username': 'author',
        'cooked': '<p>Body</p>',
        'user_birthdate': '1992-11-02',
      }, cakedaySite);
      final card = installed.models.userCard({
        'id': 7,
        'username': 'author',
        'name': 'Member',
        'birthdate': '1992-11-02',
      }, cakedaySite);
      shell.store.put(
        cakedaySite,
        const TopicDetail(id: 55, title: 'Topic', stream: [1]),
      );
      shell.store.put(cakedaySite, post);
      shell.pushContent(
        ContentRoute.topic(topicId: 55, slug: 'topic', title: 'Topic'),
      );
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Column(
                children: [
                  UserCardHeader(siteUrl: cakedaySite, card: card),
                  const TopicPostPresentation(
                    siteUrl: cakedaySite,
                    topicId: 55,
                    postId: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      List<Rect> geometry() => [
        tester.getRect(find.text('Member')),
        tester.getRect(find.text('author').last),
        tester.getRect(find.text('Body', findRichText: true)),
      ];
      final baseline = geometry();
      final birthday = find.byWidgetPredicate(
        (widget) =>
            widget is DTooltip && widget.message == 'Today is your birthday!',
      );
      expect(birthday, findsNothing);
      void settings(bool birthdays) {
        f.config.value = SiteConfig(
          emojiEnabled: false,
          plugins: PluginData.none.withValue(
            cakedaySettingsKey,
            CakedaySettings(enabled: true, birthdays: birthdays),
          ),
        );
      }

      settings(true);
      await tester.pumpAndSettle();
      expect(birthday, findsNothing);
      expect(geometry(), baseline);
      f.clock = DateTime(2026, 11, 2, 0, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(birthday, findsNWidgets(2));
      settings(false);
      await tester.pumpAndSettle();
      expect(birthday, findsNothing);
      expect(geometry(), baseline);
      settings(true);
      await tester.pumpAndSettle();
      expect(birthday, findsNWidgets(2));
      f.transport.failures['GET /cakeday/birthdays.json?page=0&filter=today'] =
          const WriteException(WriteFailure.validation, statusCode: 404);
      await f.controller.load(cakedaySite, birthdayQuery);
      await tester.pumpAndSettle();
      expect(birthday, findsNothing);
      expect(geometry(), baseline);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      shell.dispose();
      await tester.runAsync(() async {
        await shell.pluginTeardown;
        await installed.close();
      });
      f.dispose();
    },
  );
}

final class _Module implements PluginModule {
  _Module(this.controller);
  final CakedayController controller;
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: cakedayPluginId, routeNamespaces: {'cakeday'});
  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const CakedayPlugin());
    registrar.addRouteNamespace('cakeday');
    registrar.addSession(
      (bindings, _) => PluginSessionContribution(
        lifecycle: _Lifecycle(),
        services: [PluginService<Object>(cakedayControllerKey, controller)],
      ),
    );
  }
}

final class _Lifecycle extends PluginSessionLifecycle {}
