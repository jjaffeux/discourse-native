import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugins/site_plugin.dart';
import 'package:discourse_native/src/shell/post_action.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _post = Post(id: 1, postNumber: 1, username: 'sam', cooked: '');

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

    expect(held.get<_Record>()?.value, 'held');
    expect(
      registry
          .mergeAfterPostEdit(held: held, incoming: incoming)
          .get<_Record>()
          ?.value,
      'held',
    );
  });
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

final class _TopicPlugin extends _NamedPlugin implements TopicLivePlugin {
  const _TopicPlugin(super.name, {required this.staleId});

  final int staleId;

  @override
  List<int> stalePosts(String channel, Object? data) => [staleId];

  @override
  List<String> topicChannels(int topicId) => ['/topic/$topicId/$name'];
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
    implements PostRecordPlugin<_Record> {
  const _RecordPlugin() : super('record');

  @override
  Type get record => _Record;

  @override
  _Record? readPost(Map<String, dynamic> json, String siteUrl) {
    final value = json['value'];
    return value is String ? _Record(value) : null;
  }

  @override
  _Record? mergeAfterPostEdit(_Record? held, _Record? incoming) =>
      held ?? incoming;
}

void _noop() {}
