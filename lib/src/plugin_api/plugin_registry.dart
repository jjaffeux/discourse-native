import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../diagnostics/diagnostics_controller.dart';
import '../models/content_route.dart';
import '../models/forum_workspace.dart';
import '../models/post.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../models/user_card.dart';
import '../shell/composer_controller.dart';
import '../shell/post_action.dart';
import 'chat_preview.dart';
import 'site_plugin_api.dart';

/// Immutable dispatch table produced by installing a complete manifest.
@immutable
final class PluginRegistry implements PluginDataDecoder {
  const PluginRegistry(this.plugins);

  static const PluginRegistry empty = PluginRegistry([]);

  factory PluginRegistry.validated(Iterable<SitePlugin> plugins) {
    final registry = PluginRegistry(List.unmodifiable(plugins));
    registry._validateRecordOwners();
    return registry;
  }

  final List<SitePlugin> plugins;

  void _validateRecordOwners() {
    final owners = <PluginDataKey<Object>, String>{};
    for (final plugin in plugins) {
      if (plugin is PluginRecord<Object>) {
        final capability = plugin as PluginRecord<Object>;
        _claimRecordOwner(owners, capability.record, plugin.name);
      }
      if (plugin is SiteSettingsPlugin<Object>) {
        final capability = plugin as SiteSettingsPlugin<Object>;
        _validateCodecOwner(capability.siteSettingsCodec, plugin.name);
        _claimRecordOwner(
          owners,
          capability.siteSettingsCodec.key,
          plugin.name,
        );
      }
      if (plugin is CurrentUserPlugin<Object>) {
        final capability = plugin as CurrentUserPlugin<Object>;
        _validateCodecOwner(capability.currentUserCodec, plugin.name);
        _claimRecordOwner(owners, capability.currentUserCodec.key, plugin.name);
      }
    }
  }

  static void _validateCodecOwner(
    PluginDataPersistenceCodec<Object> codec,
    String owner,
  ) {
    if (codec.key.owner != owner) {
      throw ArgumentError(
        'Plugin data key ${codec.key.id} is registered by $owner.',
      );
    }
  }

  static void _claimRecordOwner(
    Map<PluginDataKey<Object>, String> owners,
    PluginDataKey<Object> key,
    String owner,
  ) {
    final previous = owners[key];
    if (previous != null) {
      throw ArgumentError(
        'Plugin data key ${key.id} is claimed by both $previous and $owner.',
      );
    }
    owners[key] = owner;
  }

  /// Installed preview contributions in deterministic manifest order.
  ///
  /// Projection belongs to Chat; core only carries these stable adapters to
  /// the Chat session factory.
  List<ChatPreviewPluginAdapter> get chatPreviewPlugins =>
      List.unmodifiable(plugins.whereType<ChatMessagePreviewPlugin>());

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
  PluginData readCurrentUser(Map<String, dynamic> json, String siteUrl) {
    var values = PluginData.none;
    for (final plugin in plugins.whereType<CurrentUserPlugin<Object>>()) {
      final value = plugin.readCurrentUser(json, siteUrl);
      if (value != null) {
        values = values.withValueFor(plugin.currentUserCodec.key, value);
      }
    }
    return values;
  }

  @override
  PluginData readSiteSettings(Map<String, dynamic> json, String siteUrl) {
    var values = PluginData.none;
    for (final plugin in plugins.whereType<SiteSettingsPlugin<Object>>()) {
      final value = plugin.readSiteSettings(json, siteUrl);
      if (value != null) {
        values = values.withValueFor(plugin.siteSettingsCodec.key, value);
      }
    }
    return values;
  }

  @override
  PluginData readStoredCurrentUser(Map<String, dynamic> json) => _readStored(
    json,
    plugins.whereType<CurrentUserPlugin<Object>>().map(
      (plugin) => plugin.currentUserCodec,
    ),
  );

  @override
  PluginData readStoredSiteSettings(Map<String, dynamic> json) => _readStored(
    json,
    plugins.whereType<SiteSettingsPlugin<Object>>().map(
      (plugin) => plugin.siteSettingsCodec,
    ),
  );

  static PluginData _readStored(
    Map<String, dynamic> json,
    Iterable<PluginDataPersistenceCodec<Object>> codecs,
  ) {
    var values = PluginData.preserveNamespaces(json['plugins']);
    for (final codec in codecs) {
      final namespaces = values.preservedNamespaces;
      final hasNamespacedValue = namespaces.containsKey(codec.key.id);
      final stored = namespaces[codec.key.id];
      values = values.withoutPreservedNamespace(codec.key.id);
      try {
        final value = hasNamespacedValue
            ? codec.decode(stored)
            : codec.decodeLegacy(json);
        if (value != null) values = values.withValueFor(codec.key, value);
      } catch (_) {
        // One stale plugin payload must not make the core instance unreadable.
      }
    }
    return values;
  }

  @override
  Map<String, Object?> writeStoredCurrentUser(PluginData data) => _writeStored(
    data,
    plugins.whereType<CurrentUserPlugin<Object>>().map(
      (plugin) => plugin.currentUserCodec,
    ),
  );

  @override
  Map<String, Object?> writeStoredSiteSettings(PluginData data) => _writeStored(
    data,
    plugins.whereType<SiteSettingsPlugin<Object>>().map(
      (plugin) => plugin.siteSettingsCodec,
    ),
  );

  static Map<String, Object?> _writeStored(
    PluginData data,
    Iterable<PluginDataPersistenceCodec<Object>> codecs,
  ) {
    final namespaces = Map<String, Object?>.of(data.preservedNamespaces);
    for (final codec in codecs) {
      final value = data.get(codec.key);
      if (value == null) {
        namespaces.remove(codec.key.id);
      } else {
        namespaces[codec.key.id] = codec.encode(value);
      }
    }
    return Map.unmodifiable(namespaces);
  }

  int composerMaximumOptions(PluginData siteSettings, {int fallback = 20}) {
    for (final plugin in plugins.whereType<ComposerMaximumOptionsPlugin>()) {
      return plugin.composerMaximumOptions(siteSettings);
    }
    return fallback;
  }

  bool allowsComposerUploads(PluginData siteSettings, {required bool isChat}) =>
      plugins.whereType<ComposerUploadPolicyPlugin>().every(
        (plugin) => plugin.allowsComposerUploads(siteSettings, isChat: isChat),
      );

  bool siteFeatureEnabled(String pluginId, PluginData siteSettings) {
    for (final plugin in plugins) {
      if (plugin.name == pluginId && plugin is PluginSiteFeature) {
        return (plugin as PluginSiteFeature).siteFeatureEnabled(siteSettings);
      }
    }
    return false;
  }

  bool currentUserFeatureEnabled(String pluginId, PluginData currentUser) {
    for (final plugin in plugins) {
      if (plugin.name == pluginId && plugin is PluginCurrentUserFeature) {
        return (plugin as PluginCurrentUserFeature).currentUserFeatureEnabled(
          currentUser,
        );
      }
    }
    return false;
  }

  bool allowsPermission(
    String permissionId,
    PluginData currentUser,
    bool? recordPermission,
  ) {
    for (final plugin in plugins.whereType<PluginPermissionPlugin>()) {
      if (plugin.permissionId == permissionId) {
        return plugin.allowsPermission(currentUser, recordPermission);
      }
    }
    return recordPermission ?? false;
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

  CookedInlinePrefix? cookedInlinePrefix(dom.Element element) {
    for (final plugin in plugins.whereType<CookedInlinePlugin>()) {
      final prefix = plugin.cookedInlinePrefix(element);
      if (prefix != null) return prefix;
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

  List<ComposerSyntaxPlugin> get composerSyntaxPlugins =>
      List.unmodifiable(plugins.whereType<ComposerSyntaxPlugin>());

  Map<ShortcutActivator, VoidCallback> composerShortcuts(
    BuildContext context,
    ComposerController composer,
  ) => {
    for (final plugin in plugins.whereType<ComposerShortcutPlugin>())
      ...plugin.composerShortcuts(context, composer),
  };

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

  SidebarDestination? forumTabDestination(
    BuildContext context,
    String siteUrl,
    ForumTab tab,
  ) {
    for (final plugin in plugins.whereType<ForumTabPlugin>()) {
      final destination = plugin.forumTabDestination(context, siteUrl, tab);
      if (destination != null) return destination;
    }
    return null;
  }

  List<Listenable> forumTabListenables(BuildContext context, String siteUrl) {
    final listenables = <Listenable>[];
    for (final plugin in plugins.whereType<ForumTabPlugin>()) {
      final listenable = plugin.forumTabListenable(context, siteUrl);
      if (listenable != null) listenables.add(listenable);
    }
    return listenables;
  }

  Widget? userAvatar(
    BuildContext context, {
    required String siteUrl,
    required int userId,
    required String url,
    required double size,
    required Widget fallback,
  }) {
    for (final plugin in plugins.whereType<UserAvatarPlugin>()) {
      final avatar = plugin.userAvatar(
        context,
        siteUrl: siteUrl,
        userId: userId,
        url: url,
        size: size,
        fallback: fallback,
      );
      if (avatar != null) return avatar;
    }
    return null;
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

  Widget? contentHeaderLeading(BuildContext context, ContentRoute route) {
    for (final plugin in plugins.whereType<ContentHeaderLeadingPlugin>()) {
      final leading = plugin.contentHeaderLeading(context, route);
      if (leading != null) return leading;
    }
    return null;
  }

  VoidCallback? contentHeaderTitleAction(
    BuildContext context,
    ContentRoute route,
  ) {
    for (final plugin in plugins.whereType<ContentHeaderTitlePlugin>()) {
      final action = plugin.contentHeaderTitleAction(context, route);
      if (action != null) return action;
    }
    return null;
  }

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

  List<DiagnosticsPlugin> get diagnosticsPlugins =>
      List.unmodifiable(plugins.whereType<DiagnosticsPlugin>());

  DateTime? futureBookmarkReminder(
    String cooked, {
    required String? accountTimezone,
  }) {
    for (final plugin in plugins.whereType<BookmarkReminderPlugin>()) {
      final reminder = plugin.futureBookmarkReminder(
        cooked,
        accountTimezone: accountTimezone,
      );
      if (reminder != null) return reminder;
    }
    return null;
  }

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
