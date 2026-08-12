import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../diagnostics/diagnostics_controller.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../shell/composer_controller.dart';
import '../shell/post_action.dart';
import 'assign/assign_plugin.dart';
import 'chat/chat_plugin.dart';
import 'chat/chat_preview.dart';
import 'gifs/gifs_plugin.dart';
import 'local_dates/local_dates_plugin.dart';
import 'poll/poll_plugin.dart';
import 'reactions/reactions_plugin.dart';
import 'resenha/resenha_plugin.dart';
import 'site_plugin_api.dart';

export 'site_plugin_api.dart';

/// Every optional feature this build knows about, in the order they are asked.
///
/// A `const` list rather than something with a `register` method: every
/// implementation is reachable from go-to-definition, the order is written
/// down, and nothing can be added from somewhere surprising. These are modules
/// in this repo, not third-party bundles — there is nothing to discover.
const List<SitePlugin> sitePlugins = <SitePlugin>[
  ReactionsPlugin(),
  LocalDatesPlugin(),
  PollPlugin(),
  GifsPlugin(),
  AssignPlugin(),
  ChatPlugin(),
  ResenhaPlugin(),
];

/// The single dispatch boundary for app-owned optional features.
///
/// It preserves [sitePlugins] order for both fallthrough and additive hooks.
/// Capability checks live here instead of being repeated across shell widgets,
/// which keeps each feature's surface narrow and makes the dispatch policy
/// independently testable.
const PluginRegistry pluginRegistry = PluginRegistry(sitePlugins);

@immutable
final class PluginRegistry {
  const PluginRegistry(this.plugins);

  final List<SitePlugin> plugins;

  /// A projector configured from this build's static plugin capabilities.
  ///
  /// Duplicate or invalid feature ids are intentionally left for
  /// [ChatPreviewEngine] to reject as a whole-source fallback. Silently picking
  /// one plugin here would make rendering order an accidental syntax contract.
  ChatPreviewEngine get chatPreviewEngine =>
      ChatPreviewEngine(plugins: plugins.whereType<ChatMessagePreviewPlugin>());

  /// Draws one already-inspected plugin node, or null for a stale/ambiguous
  /// owner so the caller can show the node's exact source fallback.
  Widget? buildChatPreviewNode(BuildContext context, PluginPreviewNode node) {
    ChatMessagePreviewPlugin? owner;
    for (final plugin in plugins.whereType<ChatMessagePreviewPlugin>()) {
      if (plugin.previewFeatureId != node.featureId) continue;
      if (owner != null) return null;
      owner = plugin;
    }
    if (owner == null) return null;
    try {
      return owner.buildPreviewNode(context, node);
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'chat.previewPlugin.render',
        source: 'chat',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
      return null;
    }
  }

  PluginData readPost(Map<String, dynamic> json, String siteUrl) {
    Map<Type, Object>? values;
    for (final plugin in plugins.whereType<PostRecordPlugin<Object>>()) {
      final value = plugin.readPost(json, siteUrl);
      if (value == null) continue;
      (values ??= <Type, Object>{})[plugin.record] = value;
    }
    return values == null ? PluginData.none : PluginData._(values);
  }

  PluginData readTopic(Map<String, dynamic> json, String siteUrl) {
    Map<Type, Object>? values;
    for (final plugin in plugins.whereType<TopicRecordPlugin<Object>>()) {
      final value = plugin.readTopic(json, siteUrl);
      if (value == null) continue;
      (values ??= <Type, Object>{})[plugin.record] = value;
    }
    return values == null ? PluginData.none : PluginData._(values);
  }

  PluginData mergeAfterPostEdit({
    required PluginData held,
    required PluginData incoming,
  }) {
    var merged = incoming;
    for (final plugin in plugins.whereType<PostRecordPlugin<Object>>()) {
      final value = plugin.mergeAfterPostEdit(
        held._values[plugin.record],
        merged._values[plugin.record],
      );
      merged = merged._withValueFor(plugin.record, value);
    }
    return merged;
  }

  Widget? postBodyElement(String siteUrl, Post post, dom.Element element) {
    for (final plugin in plugins.whereType<PostBodyPlugin>()) {
      final widget = plugin.postBodyElement(siteUrl, post, element);
      if (widget != null) return widget;
    }
    return null;
  }

  Widget? postFooter(String siteUrl, Post post) {
    for (final plugin in plugins.whereType<PostFooterPlugin>()) {
      final footer = plugin.postFooter(siteUrl, post);
      if (footer != null) return footer;
    }
    return null;
  }

  List<Widget> postDecorations(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) => [
    for (final plugin in plugins.whereType<PostDecorationPlugin>())
      ...plugin.postDecorations(context, siteUrl, topic, post),
  ];

  PluginSmallAction? smallAction(Post post) {
    for (final plugin in plugins.whereType<PostSmallActionPlugin>()) {
      final contribution = plugin.smallAction(post);
      if (contribution != null) return contribution;
    }
    return null;
  }

  bool isSmallAction(Post post) => smallAction(post) != null;

  List<Widget> topicListMetadata(
    BuildContext context,
    String siteUrl,
    Topic topic,
  ) => [
    for (final plugin in plugins.whereType<TopicListMetadataPlugin>())
      ...plugin.topicListMetadata(context, siteUrl, topic),
  ];

  List<Widget> topicHeader(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => [
    for (final plugin in plugins.whereType<TopicHeaderPlugin>())
      ...plugin.topicHeader(context, siteUrl, topic),
  ];

  PostMenuContribution postMenu(
    BuildContext context,
    String siteUrl,
    Post post,
  ) {
    final entries = <PostAction>[];
    var replacesLike = false;
    for (final plugin in plugins.whereType<PostMenuPlugin>()) {
      final contribution = plugin.postMenu(context, siteUrl, post);
      entries.addAll(contribution.entries);
      replacesLike |= contribution.replacesLike;
    }
    if (entries.isEmpty && !replacesLike) return PostMenuContribution.none;
    return PostMenuContribution(entries: entries, replacesLike: replacesLike);
  }

  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerController composer,
  ) => [
    for (final plugin in plugins.whereType<ComposerToolbarPlugin>())
      ...plugin.composerToolbar(context, composer),
  ];

  List<SidebarSection> sidebarSections(BuildContext context) => [
    for (final plugin in plugins.whereType<SidebarPlugin>())
      ...plugin.sidebarSections(context),
  ];

  List<Listenable> sidebarListenables(BuildContext context) {
    final listenables = <Listenable>[];
    for (final plugin in plugins.whereType<SidebarPlugin>()) {
      final listenable = plugin.sidebarListenable(context);
      if (listenable != null) listenables.add(listenable);
    }
    return listenables;
  }

  Widget? content(BuildContext context, ContentRoute route) {
    for (final plugin in plugins.whereType<ContentPlugin>()) {
      final content = plugin.content(context, route);
      if (content != null) return content;
    }
    return null;
  }

  bool ownsContentChrome(BuildContext context, ContentRoute route) => plugins
      .whereType<ContentChromePlugin>()
      .any((plugin) => plugin.ownsContentChrome(context, route));

  List<String> topicChannels(int topicId) => [
    for (final plugin in plugins.whereType<TopicLivePlugin>())
      ...plugin.topicChannels(topicId),
  ];

  Set<int> stalePosts(String channel, Object? data) => {
    for (final plugin in plugins.whereType<TopicLivePlugin>())
      ...plugin.stalePosts(channel, data),
  };

  bool staleTopic(int topicId, String channel, Object? data) => plugins
      .whereType<TopicLiveReloadPlugin>()
      .any((plugin) => plugin.staleTopic(topicId, channel, data));
}

/// What plugins had to say about one record.
///
/// Parsed once, when the record is, rather than on every build: a post is
/// rebuilt whenever anything about it changes and re-reading JSON each time
/// would be work for an answer that cannot have moved.
///
/// Keyed by the value type each plugin returns, so reading it is
/// `post.plugins.get<Reactions>()` — a compile-time name rather than a string.
@immutable
class PluginData {
  const PluginData._(this._values);

  /// A record no plugin claimed, which is every record on a site that has none
  /// of them. Const, so it costs nothing to be the default.
  static const PluginData none = PluginData._(<Type, Object>{});

  final Map<Type, Object> _values;

  /// This plugin's answer for the record, or null when the site did not mention
  /// the feature. **This is the gate** — see [SitePlugin].
  T? get<T extends Object>() => _values[T] as T?;

  /// Asks every plugin what it makes of a post payload.
  ///
  /// Returns [none] when none of them claimed anything, so the common case —
  /// a site running plain core — allocates nothing per post.
  static PluginData forPost(Map<String, dynamic> json, String siteUrl) =>
      pluginRegistry.readPost(json, siteUrl);

  /// Asks every plugin what it makes of a topic or topic-list payload.
  ///
  /// Just like [forPost], an unclaimed record uses the shared [none] value.
  static PluginData forTopic(Map<String, dynamic> json, String siteUrl) =>
      pluginRegistry.readTopic(json, siteUrl);

  /// The same data with one plugin's answer replaced, or dropped when [value]
  /// is null.
  ///
  /// Both directions are ordinary: taking a reaction back replaces, and a site
  /// that has stopped serving a feature drops.
  PluginData withValue<T extends Object>(T? value) {
    final next = Map<Type, Object>.of(_values);
    if (value == null) {
      next.remove(T);
    } else {
      next[T] = value;
    }
    return next.isEmpty ? none : PluginData._(next);
  }

  /// Merges a post-edit response according to each feature's own serializer
  /// contract, rather than treating every optional record as one indivisible
  /// bag.
  static PluginData afterPostEdit({
    required PluginData held,
    required PluginData incoming,
  }) => pluginRegistry.mergeAfterPostEdit(held: held, incoming: incoming);

  PluginData _withValueFor(Type type, Object? value) {
    final next = Map<Type, Object>.of(_values);
    if (value == null) {
      next.remove(type);
    } else {
      next[type] = value;
    }
    return next.isEmpty ? none : PluginData._(next);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PluginData || other._values.length != _values.length) {
      return false;
    }
    for (final entry in _values.entries) {
      if (other._values[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(_values.values);
}
