import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview_body.dart';
import 'package:discourse_native/src/shell/post_action.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';

const _post = Post(id: 1, postNumber: 1, username: 'sam', cooked: '');
const _topic = TopicDetail(id: 42, title: 'A topic', stream: [1]);

void main() {
  test('registry accepts a capability declared against the API seam', () {
    const registry = PluginRegistry([_ApiFooterPlugin()]);

    final footer = registry.postFooter('https://example.com', _post);

    expect((footer as Text).data, 'api-only');
  });

  test('dispatches only implemented capabilities and preserves order', () {
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

    expect((footer as Text).data, 'second');
    expect(registry.topicChannels(42), [
      '/topic/42/one',
      '/topic/42/two',
      '/topic/42/three',
    ]);
    expect(registry.stalePosts('/topic/42/one', null), {7, 9});
    expect(registry.staleTopic(42, '/topic/42/two', null), isTrue);
    expect(registry.staleTopic(41, '/topic/42/two', null), isFalse);
  });

  test('every shipped plugin reads only the channels it asked for', () {
    // `stalePosts` is asked of every plugin for every message on every topic
    // channel, so a hook that reads `post_id` without checking the channel
    // claims other features' payloads. Assign publishes one for a post-level
    // assignment; a poll and a reactions hook that answered it would each buy
    // a `/t/{id}/posts.json` read that neither feature needs, and would be
    // reading a key out of a payload that is none of their business.
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

    // And the ones that do own a channel still read it.
    final claiming = [
      for (final plugin in sitePlugins.whereType<TopicLivePlugin>())
        for (final channel in plugin.topicChannels(topicId))
          ...plugin.stalePosts(channel, payload),
    ];
    expect(claiming, isNotEmpty);
  });

  testWidgets('aggregates menu entries and replacement policy in order', (
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

  testWidgets('aggregates additive topic and post surfaces in order', (
    tester,
  ) async {
    const registry = PluginRegistry([
      _SurfacePlugin('first'),
      _NamedPlugin('unrelated'),
      _SurfacePlugin('second'),
    ]);
    late List<Widget> decorations;
    late List<Widget> metadata;
    late List<Widget> header;

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
            header = registry.topicHeader(context, 'site', _topic);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(decorations.map((widget) => (widget as Text).data), [
      'first-post',
      'second-post',
    ]);
    expect(metadata.map((widget) => (widget as Text).data), [
      'first-list',
      'second-list',
    ]);
    expect(header.map((widget) => (widget as Text).data), [
      'first-header',
      'second-header',
    ]);
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

  test('chat preview capabilities preserve registry order and reject ids', () {
    const registry = PluginRegistry([
      _PreviewPlugin('first', '[one]'),
      _NamedPlugin('unrelated'),
      _PreviewPlugin('second', '[two]'),
    ]);
    const request = ChatPreviewRequest(
      raw: '[one] then [two]',
      siteConfig: SiteConfig.unknown(),
    );

    final result = ChatPreviewEngine(
      plugins: registry.chatPreviewPlugins,
    ).project(request);
    final nodes = (result as ProjectedPreview).document.nodes
        .whereType<PluginPreviewNode>();
    expect(nodes.map((node) => node.featureId), ['first', 'second']);

    const duplicate = PluginRegistry([
      _PreviewPlugin('same', '[one]'),
      _PreviewPlugin('same', '[two]'),
    ]);
    expect(
      ChatPreviewEngine(plugins: duplicate.chatPreviewPlugins).project(request),
      isA<SourceFallback>().having(
        (fallback) => fallback.reason,
        'reason',
        ChatPreviewFallbackReason.duplicatePluginId,
      ),
    );
  });

  testWidgets('chat preview node rendering has an unambiguous safe fallback', (
    tester,
  ) async {
    final diagnostics = await _installDiagnostics('chat-preview-plugin');
    const registry = PluginRegistry([_PreviewPlugin('date', '[date]')]);
    const request = ChatPreviewRequest(
      raw: '[date]',
      siteConfig: SiteConfig.unknown(),
    );
    final projected =
        ChatPreviewEngine(plugins: registry.chatPreviewPlugins).project(request)
            as ProjectedPreview;
    final node = projected.document.nodes.whereType<PluginPreviewNode>().single;
    Widget? built;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            built = registry.buildChatPreviewNode(context, node);
            return built!;
          },
        ),
      ),
    );

    expect((built as Text).data, 'date');

    const duplicate = PluginRegistry([
      _PreviewPlugin('date', '[date]'),
      _PreviewPlugin('date', '[date]'),
    ]);
    const throwing = PluginRegistry([
      _PreviewPlugin('date', '[date]', throwsWhileBuilding: true),
    ]);
    final context = tester.element(find.text('date'));
    expect(duplicate.buildChatPreviewNode(context, node), isNull);
    expect(diagnostics.events.whereType<ErrorDiagnosticEvent>(), isEmpty);
    expect(throwing.buildChatPreviewNode(context, node), isNull);
    expect(
      diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
      isA<ErrorDiagnosticEvent>()
          .having(
            (event) => event.operation,
            'operation',
            'chat.previewPlugin.render',
          )
          .having((event) => event.source, 'source', 'chat')
          .having(
            (event) => event.severity,
            'severity',
            DiagnosticSeverity.warning,
          )
          .having((event) => event.handled, 'handled', isTrue)
          .having((event) => event.degraded, 'degraded', isTrue),
    );
    await diagnostics.close();
  });

  testWidgets('a broken plugin renderer falls back the whole message to raw', (
    tester,
  ) async {
    const raw = '**before** [date] after';
    const registry = PluginRegistry([
      _PreviewPlugin('date', '[date]', throwsWhileBuilding: true),
    ]);
    const request = ChatPreviewRequest(
      raw: raw,
      siteConfig: SiteConfig.unknown(),
    );
    final projected =
        ChatPreviewEngine(plugins: registry.chatPreviewPlugins).project(request)
            as ProjectedPreview;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPreviewBody(
            document: projected.document,
            textStyle: null,
            registry: registry,
          ),
        ),
      ),
    );

    expect(find.text(raw), findsOneWidget);
    expect(find.text('before'), findsNothing);
  });

  testWidgets(
    'a non-bundled manifest preview contribution renders from active scopes',
    (tester) async {
      final installed = PluginInstaller.install(
        const PluginManifest([_PreviewManifestModule()]),
      );
      final session = installed.openSession(const PluginHostBindings.empty());
      addTearDown(() async {
        await session.close();
        await installed.close();
      });

      const request = ChatPreviewRequest(
        raw: '[custom]',
        siteConfig: SiteConfig.unknown(),
      );
      final projected =
          ChatPreviewEngine(
                plugins: installed.registry.chatPreviewPlugins,
              ).project(request)
              as ProjectedPreview;
      Widget previewBody() => Scaffold(
        body: ChatPreviewBody(document: projected.document, textStyle: null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PluginScope(
            session: session,
            registry: installed.registry,
            child: previewBody(),
          ),
        ),
      );
      expect(find.text('custom-preview'), findsOneWidget);
      expect(find.text(request.raw), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: PluginRegistryScope(
            registry: installed.registry,
            child: previewBody(),
          ),
        ),
      );
      expect(find.text('custom-preview'), findsOneWidget);
      expect(find.text(request.raw), findsNothing);
    },
  );
}

final class _ApiFooterPlugin implements SitePlugin, PostFooterPlugin {
  const _ApiFooterPlugin();

  @override
  String get name => 'api-only';

  @override
  Widget? postFooter(String siteUrl, Post post) => const Text('api-only');
}

Future<DiagnosticsController> _installDiagnostics(String sessionId) async {
  final diagnostics = await DiagnosticsController.create(
    persistence: MemoryDiagnosticsPersistence(),
    sessionId: sessionId,
  );
  final binding = DiagnosticsSink.install(diagnostics);
  addTearDown(() async {
    binding.close();
    await diagnostics.close();
  });
  return diagnostics;
}

class _NamedPlugin implements SitePlugin {
  const _NamedPlugin(this.name);

  @override
  final String name;
}

final class _PreviewPlugin implements ChatMessagePreviewPlugin {
  const _PreviewPlugin(
    this.previewFeatureId,
    this.markup, {
    this.throwsWhileBuilding = false,
  });

  @override
  String get name => previewFeatureId;

  @override
  final String previewFeatureId;

  final String markup;
  final bool throwsWhileBuilding;

  @override
  ChatPreviewInspection inspect(ChatPreviewRequest request) {
    final start = request.raw.indexOf(markup);
    if (start < 0) return ChatPreviewInspection();
    final range = SourceRange(start, start + markup.length);
    return ChatPreviewInspection(
      claims: [
        ChatPreviewClaim(
          range: range,
          node: PluginPreviewNode(
            range: range,
            featureId: previewFeatureId,
            kind: 'test',
            fallbackText: markup,
          ),
        ),
      ],
    );
  }

  @override
  Widget? buildPreviewNode(BuildContext context, PluginPreviewNode node) {
    if (throwsWhileBuilding) throw StateError('test renderer failed');
    return Text(previewFeatureId);
  }
}

final class _PreviewManifestModule implements PluginModule {
  const _PreviewManifestModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('custom-preview'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const _PreviewPlugin('custom-preview', '[custom]'));
  }
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
        TopicHeaderPlugin {
  const _SurfacePlugin(super.name);

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
  List<Widget> topicHeader(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => [Text('$name-header')];
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

final class _MenuPlugin extends _NamedPlugin implements PostMenuPlugin {
  const _MenuPlugin(super.name, {this.replacesLike = false});

  final bool replacesLike;

  @override
  PostMenuContribution postMenu(
    BuildContext context,
    String siteUrl,
    Post post,
  ) => PostMenuContribution(
    entries: [
      PostAction(
        icon: DIcons.heart,
        label: name,
        tooltip: name,
        onInvoke: _noop,
      ),
    ],
    replacesLike: replacesLike,
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

void _noop() {}
