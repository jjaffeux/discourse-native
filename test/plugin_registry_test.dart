import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/site_plugin.dart';
import 'package:discourse_native/src/shell/post_action.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _post = Post(id: 1, postNumber: 1, username: 'sam', cooked: '');
const _topic = TopicDetail(id: 42, title: 'A topic', stream: [1]);

void main() {
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

    expect(held.get<_Record>()?.value, 'held');
    expect(topic.get<_Record>()?.value, 'topic');
    expect(
      registry
          .mergeAfterPostEdit(held: held, incoming: incoming)
          .get<_Record>()
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
}

class _NamedPlugin implements SitePlugin {
  const _NamedPlugin(this.name);

  @override
  final String name;
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

final class _RecordPlugin extends _NamedPlugin
    implements PostRecordPlugin<_Record>, TopicRecordPlugin<_Record> {
  const _RecordPlugin() : super('record');

  @override
  Type get record => _Record;

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
