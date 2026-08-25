import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../diagnostics/diagnostics_controller.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../models/user_card.dart';
import '../shell/composer_controller.dart';
import '../shell/post_action.dart';
import 'chat/chat_preview.dart';
import 'site_plugin_api.dart';

/// Immutable dispatch table produced by installing a complete manifest.
@immutable
final class PluginRegistry implements PluginDataDecoder {
  const PluginRegistry(this.plugins);

  factory PluginRegistry.validated(Iterable<SitePlugin> plugins) {
    final registry = PluginRegistry(List.unmodifiable(plugins));
    registry._validateRecordOwners();
    return registry;
  }

  final List<SitePlugin> plugins;

  void _validateRecordOwners() {
    final owners = <PluginDataKey<Object>, String>{};
    for (final plugin in plugins) {
      if (plugin is! PluginRecord<Object>) continue;
      final recordPlugin = plugin as PluginRecord<Object>;
      final previous = owners[recordPlugin.record];
      if (previous != null) {
        throw ArgumentError(
          'Plugin data key ${recordPlugin.record.id} is claimed by both '
          '$previous and ${plugin.name}.',
        );
      }
      owners[recordPlugin.record] = plugin.name;
    }
  }

  ChatPreviewEngine get chatPreviewEngine =>
      ChatPreviewEngine(plugins: plugins.whereType<ChatMessagePreviewPlugin>());

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

  @override
  PluginData readPost(Map<String, dynamic> json, String siteUrl) {
    var values = PluginData.none;
    for (final plugin in plugins.whereType<PostRecordPlugin<Object>>()) {
      final value = plugin.readPost(json, siteUrl);
      if (value != null) values = values.withValueFor(plugin.record, value);
    }
    return values;
  }

  @override
  PluginData readTopic(Map<String, dynamic> json, String siteUrl) {
    var values = PluginData.none;
    for (final plugin in plugins.whereType<TopicRecordPlugin<Object>>()) {
      final value = plugin.readTopic(json, siteUrl);
      if (value != null) values = values.withValueFor(plugin.record, value);
    }
    return values;
  }

  @override
  PluginData readUserCard(Map<String, dynamic> json, String siteUrl) {
    var values = PluginData.none;
    for (final plugin in plugins.whereType<UserCardRecordPlugin<Object>>()) {
      final value = plugin.readUserCard(json, siteUrl);
      if (value != null) values = values.withValueFor(plugin.record, value);
    }
    return values;
  }

  @override
  PluginData mergeAfterPostEdit({
    required PluginData held,
    required PluginData incoming,
  }) {
    var merged = incoming;
    for (final plugin in plugins.whereType<PostRecordPlugin<Object>>()) {
      final value = plugin.mergeAfterPostEdit(
        held.get(plugin.record),
        merged.get(plugin.record),
      );
      merged = merged.withValueFor(plugin.record, value);
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

  Widget? cookedElement(String? siteUrl, dom.Element element) {
    for (final plugin in plugins.whereType<CookedElementPlugin>()) {
      final widget = plugin.cookedElement(siteUrl, element);
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

  List<Widget> topicMapActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => [
    for (final plugin in plugins.whereType<TopicMapActionPlugin>())
      ...plugin.topicMapActions(context, siteUrl, topic),
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

  List<Widget> userCardActions(
    BuildContext context,
    String siteUrl,
    UserCard user,
    VoidCallback close,
  ) => [
    for (final plugin in plugins.whereType<UserCardActionPlugin>())
      ...plugin.userCardActions(context, siteUrl, user, close),
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

  List<Widget> contentHeaderActions(BuildContext context, ContentRoute route) =>
      [
        for (final plugin in plugins.whereType<ContentHeaderPlugin>())
          ...plugin.contentHeaderActions(context, route),
      ];

  List<Widget> shellHeaderActions(
    BuildContext context, {
    required PluginHeaderSurface surface,
    required bool compact,
    Color? ringColor,
  }) => [
    for (final plugin in plugins.whereType<ShellHeaderPlugin>())
      ...plugin.shellHeaderActions(
        context,
        surface: surface,
        compact: compact,
        ringColor: ringColor,
      ),
  ];

  List<Widget> shellOverlays(BuildContext context) => [
    for (final plugin in plugins.whereType<ShellOverlayPlugin>())
      ...plugin.shellOverlays(context),
  ];

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
