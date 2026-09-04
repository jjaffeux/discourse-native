import 'package:discourse_native/src/models/json.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/post_action.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import 'support/bundled_plugins.dart';

const _post = Post(id: 1, postNumber: 1, username: 'sam', cooked: '');
const _topic = TopicDetail(id: 42, title: 'A topic', stream: [1]);
const _pluginOnlyIcon = DIconData('plugin-only', LucideIcons.circle);

void main() {
  group('capability dispatch and icons', () {
    testWidgets('registry accepts a capability declared against the API seam', (
      tester,
    ) async {
      const registry = PluginRegistry([_ApiFooterPlugin()]);

      final footer = registry.postFooter('https://example.com', _post);
      await tester.pumpWidget(MaterialApp(home: footer));

      expect(find.text('api-only'), findsOneWidget);
    });

    test(
      'icon names resolve through their owner catalog with a core fallback',
      () {
        final registry = PluginRegistry.validated(const [_IconPlugin('owner')]);

        expect(
          registry.iconNamed('plugin.semantic', fallback: DIcons.circle),
          _pluginOnlyIcon,
        );
        expect(
          registry.iconNamed('missing', fallback: DIcons.circle),
          DIcons.circle,
        );
        expect(
          PluginRegistry.empty.iconNamed(
            'plugin.semantic',
            fallback: DIcons.circle,
          ),
          DIcons.circle,
        );
      },
    );

    test('icon catalogs cannot claim core, foreign, or duplicate names', () {
      expect(
        () => PluginRegistry.validated(const [
          _IconPlugin('owner', iconName: 'heart'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => PluginRegistry.validated(const [
          _IconPlugin('owner', catalogOwner: 'someone-else'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => PluginRegistry.validated(const [
          _IconPlugin('first'),
          _IconPlugin('second'),
        ]),
        throwsArgumentError,
      );
    });

    testWidgets(
      'dispatches only implemented capabilities and preserves order',
      (tester) async {
        const registry = PluginRegistry([
          _NamedPlugin('metadata-only'),
          _FooterPlugin('first', claims: false),
          _FooterPlugin('second', claims: true),
          _FooterPlugin('third', claims: true),
          _TopicPlugin('one', staleId: 7),
          _TopicPlugin('two', staleId: 7),
          _TopicPlugin('three', staleId: 9),
        ]);

        final footer = registry.postFooter('https://example.com', _post);
        await tester.pumpWidget(MaterialApp(home: footer));

        expect(find.text('second'), findsOneWidget);
        expect(registry.topicChannels(42), [
          '/topic/42/one',
          '/topic/42/two',
          '/topic/42/three',
        ]);
        expect(registry.stalePosts('/topic/42/one', null), {7, 9});
        expect(registry.staleTopic(42, '/topic/42/two', null), isTrue);
        expect(registry.staleTopic(41, '/topic/42/two', null), isFalse);
      },
    );

    test('every shipped plugin reads only the channels it asked for', () {
      // Every hook sees every topic channel and must reject foreign channels.
      const topicId = 42;
      const payload = {'post_id': 9, 'topic_id': topicId};

      for (final plugin in sitePlugins.whereType<TopicLivePlugin>()) {
        final own = plugin.topicChannels(topicId);
        for (final other in sitePlugins.whereType<TopicLivePlugin>()) {
          for (final channel in other.topicChannels(topicId)) {
            if (own.contains(channel)) continue;
            expect(
              plugin.stalePosts(channel, payload),
              isEmpty,
              reason: '$plugin claimed a post out of $channel',
            );
          }
        }
      }

      final claiming = [
        for (final plugin in sitePlugins.whereType<TopicLivePlugin>())
          for (final channel in plugin.topicChannels(topicId))
            ...plugin.stalePosts(channel, payload),
      ];
      expect(claiming, isNotEmpty);
    });
  });

  group('post model contributions', () {
    testWidgets('aggregate menu entries and replacement policy in order', (
      tester,
    ) async {
      const registry = PluginRegistry([
        _MenuPlugin('first'),
        _NamedPlugin('unrelated'),
        _MenuPlugin('second', replacesLike: true),
      ]);
      PostMenuContribution? contribution;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              contribution = registry.postMenu(
                context,
                'https://example.com',
                _post,
                topic: _topic,
                currentUser: null,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(contribution!.entries.map((entry) => entry.label), [
        'first',
        'second',
      ]);
      expect(contribution!.replacesLike, isTrue);
    });

    testWidgets('aggregates plugin-owned post menu rebuild signals', (
      tester,
    ) async {
      final first = ChangeNotifier();
      final second = ChangeNotifier();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final registry = PluginRegistry([
        _MenuPlugin('first', rebuildOn: first),
        const _NamedPlugin('unrelated'),
        _MenuPlugin('second', rebuildOn: second),
      ]);
      late PostMenuContribution contribution;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              contribution = registry.postMenu(
                context,
                'https://example.com',
                _post,
                topic: _topic,
                currentUser: null,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      var notifications = 0;
      void notified() => notifications++;
      contribution.rebuildOn!.addListener(notified);
      addTearDown(() => contribution.rebuildOn?.removeListener(notified));

      first.notifyListeners();
      second.notifyListeners();

      expect(notifications, 2);
    });

    test('record parsing and edit merge stay behind the registry', () {
      const registry = PluginRegistry([_RecordPlugin()]);
      final held = registry.readPost(const {'value': 'held'}, 'site');
      final incoming = registry.readPost(const {'value': 'new'}, 'site');
      final topic = registry.readTopic(const {'topic_value': 'topic'}, 'site');

      expect(held.get(_recordKey)?.value, 'held');
      expect(topic.get(_recordKey)?.value, 'topic');
      expect(
        registry
            .mergeAfterPostEdit(held: held, incoming: incoming)
            .get(_recordKey)
            ?.value,
        'held',
      );
    });
  });

  group('topic recommendation sources', () {
    test('preserve registry order', () {
      final registry = PluginRegistry.validated(const [
        _RecommendationPlugin(
          'first',
          sourceName: 'nearby',
          payloadKey: 'nearby_topics',
          label: 'Nearby',
        ),
        _NamedPlugin('unrelated'),
        _RecommendationPlugin(
          'second',
          sourceName: 'popular',
          payloadKey: 'popular_topics',
          label: 'Popular',
        ),
      ]);

      final recommendations = TopicRecommendations.fromJson(
        const {
          'suggested_topics': [
            {'id': 1, 'title': 'Suggested', 'slug': 'suggested'},
          ],
          'nearby_topics': [
            {'id': 2, 'title': 'Nearby', 'slug': 'nearby'},
          ],
          'popular_topics': [
            {'id': 3, 'title': 'Popular', 'slug': 'popular'},
          ],
        },
        'https://example.com',
        extensions: registry,
        recommendationSources: registry,
      )!;

      expect(recommendations.sources.map((source) => source.id.value), [
        'core/suggested',
        'first/nearby',
        'second/popular',
      ]);
      expect(recommendations.sources.map((source) => source.label), [
        'Suggested',
        'Nearby',
        'Popular',
      ]);
    });

    test('topic recommendation IDs are namespaced and uniquely owned', () {
      expect(
        () => PluginRegistry.validated(const [
          _RecommendationPlugin(
            'owner',
            sourceName: 'first',
            payloadKey: 'first_topics',
            label: 'First',
            namespace: 'someone-else',
          ),
        ]),
        throwsArgumentError,
      );
      expect(
        () => PluginRegistry.validated(const [
          _RecommendationPlugin(
            'same',
            sourceName: 'shared',
            payloadKey: 'first_topics',
            label: 'First',
          ),
          _RecommendationPlugin(
            'same',
            sourceName: 'shared',
            payloadKey: 'second_topics',
            label: 'Second',
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('topic recommendation codecs exclusively own legacy storage IDs', () {
      final registry = PluginRegistry.validated(const [
        _RecommendationPlugin(
          'first',
          sourceName: 'nearby',
          payloadKey: 'nearby_topics',
          label: 'Nearby',
          legacyStoredIds: {'nearby'},
        ),
        _RecommendationPlugin(
          'second',
          sourceName: 'popular',
          payloadKey: 'popular_topics',
          label: 'Popular',
          legacyStoredIds: {'popular'},
        ),
      ]);

      expect(
        registry.migrateLegacyStoredId('nearby'),
        const TopicRecommendationSourceId('first/nearby'),
      );
      expect(registry.migrateLegacyStoredId('missing'), isNull);
      expect(
        () => PluginRegistry.validated(const [
          _RecommendationPlugin(
            'first',
            sourceName: 'nearby',
            payloadKey: 'nearby_topics',
            label: 'Nearby',
            legacyStoredIds: {'shared'},
          ),
          _RecommendationPlugin(
            'second',
            sourceName: 'popular',
            payloadKey: 'popular_topics',
            label: 'Popular',
            legacyStoredIds: {'shared'},
          ),
        ]),
        throwsArgumentError,
      );
      for (final invalid in const [
        {'suggested'},
        {' first '},
        {'old/nearby'},
      ]) {
        expect(
          () => PluginRegistry.validated([
            _RecommendationPlugin(
              'first',
              sourceName: 'nearby',
              payloadKey: 'nearby_topics',
              label: 'Nearby',
              legacyStoredIds: invalid,
            ),
          ]),
          throwsArgumentError,
        );
      }
    });
  });

  group('notification counters', () {
    test('decode in registered namespaces', () {
      final registry = PluginRegistry.validated(const [
        _CounterPlugin(
          'alerts',
          counters: [
            PluginNotificationCounter(
              id: PluginNotificationCounterId(
                owner: PluginId('alerts'),
                name: 'mentions',
              ),
              wireName: 'alert_mentions',
            ),
          ],
        ),
      ]);

      final counters = registry.readLiveNotificationCounters(const {
        'alert_mentions': 3,
      });

      expect(
        counters.count(
          const PluginNotificationCounterId(
            owner: PluginId('alerts'),
            name: 'mentions',
          ),
        ),
        3,
      );
    });

    test('notification counter IDs and wire names are uniquely owned', () {
      const owned = PluginNotificationCounter(
        id: PluginNotificationCounterId(
          owner: PluginId('alerts'),
          name: 'mentions',
        ),
        wireName: 'alert_mentions',
      );
      expect(
        () => PluginRegistry.validated(const [
          _CounterPlugin('alerts', counters: [owned]),
          _CounterPlugin('alerts', counters: [owned]),
        ]),
        throwsArgumentError,
      );
      expect(
        () => PluginRegistry.validated(const [
          _CounterPlugin('alerts', counters: [owned]),
          _CounterPlugin(
            'other',
            counters: [
              PluginNotificationCounter(
                id: PluginNotificationCounterId(
                  owner: PluginId('other'),
                  name: 'other',
                ),
                wireName: 'alert_mentions',
              ),
            ],
          ),
        ]),
        throwsArgumentError,
      );
      expect(
        () => PluginRegistry.validated(const [
          _CounterPlugin('wrong-owner', counters: [owned]),
        ]),
        throwsArgumentError,
      );
      expect(
        () => PluginRegistry.validated(const [
          _CounterPlugin(
            'alerts',
            counters: [
              PluginNotificationCounter(
                id: PluginNotificationCounterId(
                  owner: PluginId('alerts'),
                  name: 'core-collision',
                ),
                wireName: 'unread_notifications',
              ),
            ],
          ),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('widget surfaces', () {
    testWidgets('aggregate additive topic and post surfaces in order', (
      tester,
    ) async {
      const registry = PluginRegistry([
        _SurfacePlugin('first'),
        _NamedPlugin('unrelated'),
        _SurfacePlugin(
          'second',
          layout: TopicPropertySectionLayout.standalone,
          showHeader: false,
        ),
      ]);
      late List<Widget> decorations;
      late List<Widget> metadata;
      late List<TopicPropertySection> properties;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              decorations = registry.postDecorations(
                context,
                'site',
                _topic,
                _post,
              );
              metadata = registry.topicListMetadata(
                context,
                'site',
                const Topic(id: 42, title: 'A topic', slug: 'a-topic'),
              );
              properties = registry.topicProperties(context, 'site', _topic);
              return Column(
                children: [
                  ...decorations,
                  ...metadata,
                  for (final section in properties) ...section.values,
                ],
              );
            },
          ),
        ),
      );

      for (final label in const [
        'first-post',
        'second-post',
        'first-list',
        'second-list',
        'first-properties',
        'second-properties',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(properties.map((section) => section.layout), [
        TopicPropertySectionLayout.inline,
        TopicPropertySectionLayout.standalone,
      ]);
      expect(properties.map((section) => section.showHeader), [true, false]);
    });

    testWidgets('aggregates topic-property rebuild signals', (tester) async {
      final first = ChangeNotifier();
      final second = ChangeNotifier();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final registry = PluginRegistry([
        _RebuildingHeaderPlugin('first', first),
        const _NamedPlugin('unrelated'),
        _RebuildingHeaderPlugin('second', second),
      ]);
      Listenable? rebuildOn;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              rebuildOn = registry.topicPropertiesRebuildOn(
                context,
                'site',
                _topic,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      var notifications = 0;
      void notified() => notifications++;
      rebuildOn!.addListener(notified);
      addTearDown(() => rebuildOn?.removeListener(notified));

      first.notifyListeners();
      second.notifyListeners();

      expect(notifications, 2);
    });

    test(
      'a plugin contribution both classifies and describes a small action',
      () {
        const registry = PluginRegistry([_SmallActionPlugin()]);
        const claimed = Post(
          id: 2,
          postNumber: 2,
          username: 'sam',
          cooked: '',
          postType: 4,
          actionCode: 'assigned.enabled',
        );
        const ordinary = Post(
          id: 3,
          postNumber: 3,
          username: 'sam',
          cooked: '',
          postType: 4,
          actionCode: 'something.else',
        );

        expect(registry.isSmallAction(claimed), isTrue);
        expect(registry.smallAction(claimed)?.phrase, 'assigned this topic');
        expect(registry.isSmallAction(ordinary), isFalse);
      },
    );
  });
}

final class _ApiFooterPlugin implements SitePlugin, PostFooterPlugin {
  const _ApiFooterPlugin();

  @override
  String get name => 'api-only';

  @override
  Widget? postFooter(String siteUrl, Post post) => const Text('api-only');
}

class _NamedPlugin implements SitePlugin {
  const _NamedPlugin(this.name);

  @override
  final String name;
}

final class _IconPlugin extends _NamedPlugin implements IconCatalogPlugin {
  const _IconPlugin(
    super.name, {
    this.iconName = 'plugin.semantic',
    String? catalogOwner,
  }) : catalogOwner = catalogOwner ?? name;

  final String iconName;
  final String catalogOwner;

  @override
  PluginIconCatalog get iconCatalog => PluginIconCatalog(
    owner: PluginId(catalogOwner),
    entries: {iconName: _pluginOnlyIcon},
  );
}

final class _FooterPlugin extends _NamedPlugin implements PostFooterPlugin {
  const _FooterPlugin(super.name, {required this.claims});

  final bool claims;

  @override
  Widget? postFooter(String siteUrl, Post post) => claims ? Text(name) : null;
}

final class _TopicPlugin extends _NamedPlugin
    implements TopicLivePlugin, TopicLiveReloadPlugin {
  const _TopicPlugin(super.name, {required this.staleId});

  final int staleId;

  @override
  List<int> stalePosts(String channel, Object? data) => [staleId];

  @override
  List<String> topicChannels(int topicId) => ['/topic/$topicId/$name'];

  @override
  bool staleTopic(int topicId, String channel, Object? data) =>
      channel == '/topic/$topicId/$name';
}

final class _SurfacePlugin extends _NamedPlugin
    implements
        PostDecorationPlugin,
        TopicListMetadataPlugin,
        TopicPropertiesPlugin {
  const _SurfacePlugin(
    super.name, {
    this.layout = TopicPropertySectionLayout.inline,
    this.showHeader = true,
  });

  final TopicPropertySectionLayout layout;
  final bool showHeader;

  @override
  List<Widget> postDecorations(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) => [Text('$name-post')];

  @override
  List<Widget> topicListMetadata(
    BuildContext context,
    String siteUrl,
    Topic topic,
  ) => [Text('$name-list')];

  @override
  List<TopicPropertySection> topicProperties(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => [
    TopicPropertySection(
      label: name,
      values: [Text('$name-properties')],
      layout: layout,
      showHeader: showHeader,
    ),
  ];
}

final class _SmallActionPlugin extends _NamedPlugin
    implements PostSmallActionPlugin {
  const _SmallActionPlugin() : super('small-action');

  @override
  PluginSmallAction? smallAction(Post post) =>
      post.postType == 4 && post.actionCode == 'assigned.enabled'
      ? const PluginSmallAction(
          icon: DIcons.userPlus,
          phrase: 'assigned this topic',
        )
      : null;
}

final class _RebuildingHeaderPlugin extends _NamedPlugin
    implements TopicPropertiesRebuildPlugin {
  const _RebuildingHeaderPlugin(super.name, this.rebuildOn);

  final Listenable rebuildOn;

  @override
  Listenable topicPropertiesRebuildOn(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => rebuildOn;
}

final class _MenuPlugin extends _NamedPlugin implements PostMenuPlugin {
  const _MenuPlugin(super.name, {this.replacesLike = false, this.rebuildOn});

  final bool replacesLike;
  final Listenable? rebuildOn;

  @override
  PostMenuContribution postMenu(PostMenuContext context) =>
      PostMenuContribution(
        entries: [
          PostAction(
            icon: DIcons.heart,
            label: name,
            tooltip: name,
            onInvoke: _noop,
          ),
        ],
        replacesLike: replacesLike,
        rebuildOn: rebuildOn,
      );
}

final class _Record {
  const _Record(this.value);

  final String value;
}

const _recordKey = PluginDataKey<_Record>(owner: 'record', name: 'test');

final class _RecordPlugin extends _NamedPlugin
    implements PostRecordPlugin<_Record>, TopicRecordPlugin<_Record> {
  const _RecordPlugin() : super('record');

  @override
  PluginDataKey<_Record> get record => _recordKey;

  @override
  _Record? readPost(Map<String, dynamic> json, String siteUrl) {
    final value = json['value'];
    return value is String ? _Record(value) : null;
  }

  @override
  _Record? readTopic(Map<String, dynamic> json, String siteUrl) {
    final value = json['topic_value'];
    return value is String ? _Record(value) : null;
  }

  @override
  _Record? mergeAfterPostEdit(_Record? held, _Record? incoming) =>
      held ?? incoming;
}

final class _RecommendationPlugin extends _NamedPlugin
    implements TopicRecommendationSourcePlugin {
  const _RecommendationPlugin(
    super.name, {
    required this.sourceName,
    required this.payloadKey,
    required this.label,
    this.namespace,
    this.legacyStoredIds = const {},
  });

  final String sourceName;
  final String payloadKey;
  final String label;
  final String? namespace;
  final Set<String> legacyStoredIds;

  @override
  List<TopicRecommendationSourceCodec> get topicRecommendationSourceCodecs => [
    _RecommendationCodec(
      definition: TopicRecommendationSourceDefinition(
        id: TopicRecommendationSourceId('${namespace ?? name}/$sourceName'),
        label: label,
      ),
      payloadKey: payloadKey,
      legacyStoredIds: legacyStoredIds,
    ),
  ];
}

final class _RecommendationCodec extends TopicRecommendationSourceCodec {
  const _RecommendationCodec({
    required this.definition,
    required this.payloadKey,
    required this.legacyStoredIds,
  });

  @override
  final TopicRecommendationSourceDefinition definition;
  final String payloadKey;
  @override
  final Set<String> legacyStoredIds;

  @override
  List<Map<String, dynamic>>? decodeTopicRows(Map<String, dynamic> json) {
    if (!json.containsKey(payloadKey)) return null;
    return List.unmodifiable(jsonObjects(json[payloadKey]));
  }
}

final class _CounterPlugin extends _NamedPlugin
    implements NotificationCounterPlugin {
  const _CounterPlugin(super.name, {required this.counters});

  final List<PluginNotificationCounter> counters;

  @override
  List<PluginNotificationCounter> get notificationCounters => counters;
}

void _noop() {}
