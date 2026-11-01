import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_module.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/user_card_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/fakes.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'installed Cakeday decoder and services reach real post/card identity, mobile=$mobile',
      (tester) async {
        const site = 'https://cakeday.example';
        final installed = PluginInstaller.install(
          const PluginManifest([cakedayModule]),
        );
        final now = DateTime.now();
        final md =
            '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        const user = DiscourseUser(id: 7, username: 'maya');
        final config = installed.models.siteConfig({
          'cakeday_enabled': true,
          'cakeday_birthday_enabled': true,
          'enable_emoji': false,
        }, site);
        final api = FakeDiscourseApi(
          models: installed.models,
          user: user,
          feeds: const {'/latest.json': []},
          siteConfigs: {site: config},
        );
        final shell = ShellController(
          plugins: installed,
          instanceStore: FakeInstanceStore([
            instance('cakeday.example', user: user).copyWith(config: config),
          ]),
          api: api,
          authenticator: FakeAuthenticator()..keys[site] = 'key',
          drafts: FakeDraftStore(),
          forumTabs: FakeForumTabStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        await shell.load();
        final post = installed.models.post({
          'id': 1,
          'post_number': 1,
          'user_id': 7,
          'username': 'maya',
          'cooked': '<p>A community milestone.</p>',
          'user_birthdate': '1904-$md',
          'user_cakedate': '${now.year - 4}-$md',
        }, site);
        final card = installed.models.userCard({
          'id': 7,
          'username': 'maya',
          'name': 'Maya',
          'birthdate': '1904-$md',
          'cakedate': '${now.year - 4}-$md',
        }, site);
        shell.store.put(
          site,
          const TopicDetail(id: 55, title: 'Milestone', stream: [1]),
        );
        shell.store.put(site, post);
        shell.pushContent(
          ContentRoute.topic(
            topicId: 55,
            slug: 'milestone',
            title: 'Milestone',
          ),
        );
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      UserCardHeader(
                        siteUrl: site,
                        card: card,
                        mobileSheet: mobile,
                      ),
                      const TopicPostPresentation(
                        siteUrl: site,
                        topicId: 55,
                        postId: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is DTooltip &&
                widget.message == 'Today is your birthday!',
          ),
          findsNWidgets(2),
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is DTooltip &&
                widget.message ==
                    'Today is the anniversary of the day you joined our community!',
          ),
          findsNWidgets(2),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        shell.dispose();
        await shell.pluginTeardown;
        await installed.close();
      },
    );
  }
}
