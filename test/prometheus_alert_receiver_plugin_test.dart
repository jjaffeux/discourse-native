import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_module.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_data.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_links.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_tables.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/prometheus_alert_receiver_module.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/prometheus_alert_receiver_plugin.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/alert_fixtures.dart';
import 'support/fakes.dart';
import 'support/media_pipeline.dart';
import 'support/shell_test_harness.dart' show renderedText;

const _site = 'https://meta.discourse.org';

InstalledPlugins _plugins({bool localDates = false}) {
  final environment = LocalDateEnvironment.forTesting(
    detectDeviceTimezone: () async => 'Europe/Paris',
  )..setDeviceTimezone('Europe/Paris');
  addTearDown(environment.dispose);
  final plugins = PluginInstaller.install(
    PluginManifest([
      prometheusAlertReceiverModule,
      if (localDates) LocalDatesModule(environment: environment),
    ]),
  );
  addTearDown(plugins.close);
  return plugins;
}

void main() {
  setUp(() {
    installTestMediaPipeline(
      client: MockClient((_) async => http.Response('', 404)),
    );
  });

  test(
    'the module owns topic alerts and site settings without enabling core-only models',
    () {
      final plugins = _plugins();
      final json = alertTopicJson([alertJson()]);
      expect(
        plugins.models
            .topic(json, _site)
            .detail
            .plugins
            .get(alertDataKey)!
            .alerts
            .single
            .identifier,
        'myalert',
      );
      expect(
        const DiscourseModelCodec.core()
            .topic(json, _site)
            .detail
            .plugins
            .get(alertDataKey),
        isNull,
      );
      final config = plugins.models.siteConfig({
        'prometheus_alert_receiver_grafana_regex': r'/d/',
      }, _site);
      expect(config.plugins.get(alertLinkSettingsKey)!.grafana, r'/d/');
      final stored = plugins.registry.writeStoredSiteSettings(config.plugins);
      expect(
        plugins.registry
            .readStoredSiteSettings({'plugins': stored})
            .get(alertLinkSettingsKey),
        config.plugins.get(alertLinkSettingsKey),
      );
    },
  );

  testWidgets(
    'topic tables use site emoji and the installed Local Dates renderer',
    (tester) async {
      final plugins = _plugins(localDates: true);
      final api = FakeDiscourseApi(
        models: plugins.models,
        siteConfigs: const {_site: SiteConfig(emojiSet: 'apple')},
        topics: {
          7: plugins.models.topic(
            alertTopicJson([alertJson(), alertJson(status: 'suppressed')]),
            _site,
          ),
        },
      );
      await _open(tester, plugins, api);
      final emoji = tester.widgetList<EmojiImage>(
        find.descendant(
          of: find.byType(AlertTables),
          matching: find.byType(EmojiImage),
        ),
      );
      expect(emoji.map((image) => image.url), [
        '$_site/images/emoji/apple/fire.png',
        '$_site/images/emoji/apple/shushing_face.png',
      ]);
      // Unavailable artwork still leaves a visible status emoji.
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('🤫'), findsOneWidget);
      expect(find.byType(LocalDateInline), findsNWidgets(2));
      await tester.tap(find.bySemanticsLabel(RegExp('Paris:')).first);
      await tester.pumpAndSettle();
      expect(find.text('Paris'), findsOneWidget);
      expect(find.textContaining('Device'), findsOneWidget);
    },
  );

  testWidgets(
    'topic alert data renders only after the opening post and updates through the topic bus',
    (tester) async {
      final plugins = _plugins();
      final api = FakeDiscourseApi(
        models: plugins.models,
        topics: {
          7: plugins.models.topic(alertTopicJson([alertJson()]), _site),
        },
      );
      final shell = await _open(tester, plugins, api);
      expect(find.byType(AlertTables), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Firing')).dy,
        greaterThan(tester.getTopLeft(renderedText('Database runbook')).dy),
      );
      expect(renderedText('Investigating'), findsOneWidget);
      expect(find.text('Firing'), findsOneWidget);

      api.topics[7] = plugins.models.topic(
        alertTopicJson([alertJson(status: 'resolved')]),
        _site,
      );
      FakeSiteTracker.built.single.deliverTopicMessage('/topic/7', {
        'type': 'revised',
        'id': 10,
        'reload_topic': true,
      });
      await tester.pumpAndSettle();
      expect(find.text('Firing'), findsNothing);
      expect(find.text('History'), findsOneWidget);
      expect(
        shell.currentTopic!.plugins.get(alertDataKey)!.alerts.single.status,
        AlertStatus.resolved,
      );

      api.topics[7] = plugins.models.topic(alertTopicJson([]), _site);
      FakeSiteTracker.built.single.deliverTopicMessage('/topic/7', {
        'type': 'revised',
        'reload_topic': true,
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertTables), findsNothing);
      expect(renderedText('Database runbook'), findsOneWidget);
    },
  );

  testWidgets(
    'quoting an alert opens a reply and preserves an existing composer draft',
    (tester) async {
      final plugins = _plugins();
      final api = FakeDiscourseApi(
        models: plugins.models,
        topics: {
          7: plugins.models.topic(
            alertTopicJson([alertJson(description: 'High latency')]),
            _site,
          ),
        },
      );
      final shell = await _open(tester, plugins, api);
      final quoteButton = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Quote Alert',
      );
      await tester.ensureVisible(quoteButton);
      await tester.tap(quoteButton);
      await tester.pumpAndSettle();
      final composer = shell.visibleComposer!;
      expect(composer.target.topicId, 7);
      expect(composer.raw, contains('[quote="system, post:1, topic:7"]'));
      expect(composer.raw, contains('**myalert** - sjc1 - [date=2020-07-27'));
      expect(composer.raw, contains('High latency'));
      composer.insertText('Investigating now');
      await tester.tap(quoteButton);
      await tester.pumpAndSettle();
      expect(shell.visibleComposer, same(composer));
      expect(composer.raw, contains('Investigating now'));
      expect('[quote='.allMatches(composer.raw), hasLength(2));
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'quote host rejects another site, posts outside the topic, and revoked reply permission',
    (tester) async {
      final plugins = _plugins();
      final api = FakeDiscourseApi(
        models: plugins.models,
        topics: {
          7: plugins.models.topic(alertTopicJson([alertJson()]), _site),
        },
      );
      final shell = await _open(tester, plugins, api);
      final host = shell.pluginSession.require(alertQuoteService);
      await host.open('https://other.example', 10, 'Other site');
      shell.store.put<Post>(
        _site,
        const Post(
          id: 99,
          postNumber: 1,
          username: 'sam',
          cooked: 'Other post',
        ),
      );
      await host.open(_site, 99, 'Other topic');
      expect(shell.visibleComposer, isNull);
      final revoked = alertTopicJson([alertJson()])
        ..['details'] = {'can_create_post': false};
      api.topics[7] = plugins.models.topic(revoked, _site);
      FakeSiteTracker.built.single.deliverTopicMessage('/topic/7', {
        'type': 'revised',
        'reload_topic': true,
      });
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Quote Alert',
        ),
        findsNothing,
      );
      await host.open(_site, 10, 'Permission revoked');
      expect(shell.visibleComposer, isNull);
    },
  );
}

Future<ShellController> _open(
  WidgetTester tester,
  InstalledPlugins plugins,
  FakeDiscourseApi api,
) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final shell = ShellController(
    plugins: plugins,
    api: api,
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() async {
    shell.dispose();
    await shell.pluginTeardown;
  });
  await shell.load();
  shell.pushContent(
    ContentRoute.topic(
      topicId: 7,
      slug: 'database-alerts',
      title: 'Database alerts',
    ),
  );
  await shell.loadTopic(7, 'database-alerts');
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: PluginScope(
        session: shell.pluginSession,
        registry: plugins.registry,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: TopicView()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}
