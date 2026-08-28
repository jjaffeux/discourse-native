import 'dart:async';

import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../diagnostics/diagnostics_controller.dart';
import '../models/content_route.dart';
import '../models/discourse_user.dart';
import '../models/forum_workspace.dart';
import '../models/post.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../models/user_card.dart';
import '../shell/composer_controller.dart';
import '../shell/post_action.dart';
import 'chat_preview.dart';
import 'plugin_scope.dart';
import 'site_plugin_api.dart';

/// Immutable dispatch table produced by installing a complete manifest.
@immutable
final class PluginRegistry implements PluginDataDecoder {
  const PluginRegistry(this.plugins);

  static const PluginRegistry empty = PluginRegistry([]);

  factory PluginRegistry.validated(Iterable<SitePlugin> plugins) {
    final registry = PluginRegistry(List.unmodifiable(plugins));
    registry._validateRecordOwners();
    registry._validateComposerTargetOwners();
    registry._validateTopicRecommendationSources();
    registry._validateNotificationFeeds();
    return registry;
  }

  void _validateComposerTargetOwners() {
    final owners = <ComposerTargetKind, String>{};
    for (final plugin in plugins.whereType<ComposerTargetPlugin>()) {
      final pluginName = (plugin as SitePlugin).name;
      final kind = plugin.composerTargetKind;
      if (kind.owner != PluginId(pluginName) ||
          kind.name.trim().isEmpty ||
          kind.name.contains('/')) {
        throw ArgumentError(
          'Composer target $kind must be namespaced to $pluginName.',
        );
      }
      final previous = owners[kind];
      if (previous != null) {
        throw ArgumentError(
          'Composer target $kind is claimed by both $previous and $pluginName.',
        );
      }
      owners[kind] = pluginName;
    }
  }

  final List<SitePlugin> plugins;

  static PluginId _owner(Object plugin) =>
      PluginId((plugin as SitePlugin).name);

  static BuildContext _uiContext(BuildContext context, Object plugin) =>
      PluginUiScope.contextFor(context, _owner(plugin));

  static Widget _owned(Object plugin, Widget child) {
    final owner = _owner(plugin);
    // HtmlWidget detects this marker before building it. Wrapping the marker
    // itself would turn an inline contribution into a block; keep the marker
    // outermost and scope only the widget it carries.
    if (child is InlineCustomWidget) {
      return InlineCustomWidget(
        key: child.key,
        alignment: child.alignment,
        baseline: child.baseline,
        child: PluginUiScope.own(owner, child.child),
      );
    }
    return PluginUiScope.own(owner, child);
  }

  static List<Widget> _ownedAll(Object plugin, Iterable<Widget> children) => [
    for (final child in children) _owned(plugin, child),
  ];

  static SidebarDestination _ownedDestination(
    Object plugin,
    SidebarDestination destination,
  ) => SidebarDestination(
    id: destination.id,
    label: destination.label,
    icon: destination.icon,
    color: destination.color,
    parentColor: destination.parentColor,
    emoji: destination.emoji,
    avatarUrl: destination.avatarUrl,
    avatarUserId: destination.avatarUserId,
    userStatus: destination.userStatus,
    iconColor: destination.iconColor,
    routeColor: destination.routeColor,
    prefixBadgeIcon: destination.prefixBadgeIcon,
    badge: destination.badge,
    onTap: destination.onTap,
    children: [
      for (final child in destination.children)
        _ownedDestination(plugin, child),
    ],
    trailingLabel: destination.trailingLabel,
    indent: destination.indent,
    enabled: destination.enabled,
    trailingIcon: destination.trailingIcon,
    onSecondaryTap: destination.onSecondaryTap,
    hoverActionBuilder: destination.hoverActionBuilder != null
        ? (context) => _owned(
            plugin,
            destination.hoverActionBuilder!(_uiContext(context, plugin)),
          )
        : null,
    onLongPress: destination.onLongPress != null
        ? (context) => destination.onLongPress!(_uiContext(context, plugin))
        : null,
    url: destination.url,
    feedPath: destination.feedPath,
  );

  static SidebarSection _ownedSection(Object plugin, SidebarSection section) =>
      SidebarSection(
        id: section.id,
        title: section.title,
        destinations: [
          for (final destination in section.destinations)
            _ownedDestination(plugin, destination),
        ],
        showHeader: section.showHeader,
        collapsible: section.collapsible,
        actionIcon: section.actionIcon,
        actionLabel: section.actionLabel,
        onAction: section.onAction,
      );

  @override
  List<TopicRecommendationSourceDefinition> get topicRecommendationSources =>
      List.unmodifiable([
        for (final plugin
            in plugins.whereType<TopicRecommendationSourcePlugin>())
          ...plugin.topicRecommendationSources,
      ]);

  List<PluginNotificationFeedSource> get notificationFeeds =>
      List.unmodifiable([
        for (final plugin in plugins.whereType<NotificationFeedPlugin>())
          ...plugin.notificationFeeds,
      ]);

  PluginNotificationFeedSource? notificationFeed(PluginNotificationFeedId id) =>
      notificationFeeds.where((source) => source.id == id).firstOrNull;

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

  void _validateTopicRecommendationSources() {
    final idOwners = <TopicRecommendationSourceId, String>{
      coreSuggestedTopicRecommendationSource.id: 'core',
    };
    final payloadOwners = <String, String>{
      coreSuggestedTopicRecommendationSource.payloadKey: 'core',
    };
    for (final plugin in plugins.whereType<TopicRecommendationSourcePlugin>()) {
      final pluginName = (plugin as SitePlugin).name;
      for (final source in plugin.topicRecommendationSources) {
        if (!source.id.isNamespaced || source.id.namespace != pluginName) {
          throw ArgumentError(
            'Topic recommendation source ${source.id} must be namespaced to '
            '$pluginName.',
          );
        }
        if (source.payloadKey.trim().isEmpty || source.label.trim().isEmpty) {
          throw ArgumentError(
            'Topic recommendation source ${source.id} must declare a payload '
            'key and label.',
          );
        }
        final previousIdOwner = idOwners[source.id];
        if (previousIdOwner != null) {
          throw ArgumentError(
            'Topic recommendation source ${source.id} is claimed by both '
            '$previousIdOwner and $pluginName.',
          );
        }
        final previousPayloadOwner = payloadOwners[source.payloadKey];
        if (previousPayloadOwner != null) {
          throw ArgumentError(
            'Topic recommendation payload ${source.payloadKey} is claimed by '
            'both $previousPayloadOwner and $pluginName.',
          );
        }
        idOwners[source.id] = pluginName;
        payloadOwners[source.payloadKey] = pluginName;
      }
    }
  }

  void _validateNotificationFeeds() {
    final owners = <PluginNotificationFeedId, String>{};
    for (final plugin in plugins.whereType<NotificationFeedPlugin>()) {
      final pluginName = (plugin as SitePlugin).name;
      for (final source in plugin.notificationFeeds) {
        if (source.id.owner != PluginId(pluginName) ||
            source.id.name.trim().isEmpty ||
            source.id.name.contains('/')) {
          throw ArgumentError(
            'Notification feed ${source.id.id} must be namespaced to '
            '$pluginName.',
          );
        }
        if (source.reconnectMessage.trim().isEmpty ||
            source.failureMessage.trim().isEmpty ||
            source.emptyMessage.trim().isEmpty) {
          throw ArgumentError(
            'Notification feed ${source.id.id} must declare its messages.',
          );
        }
        final previous = owners[source.id];
        if (previous != null) {
          throw ArgumentError(
            'Notification feed ${source.id.id} is claimed by both '
            '$previous and $pluginName.',
          );
        }
        owners[source.id] = pluginName;
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
      final widget = owner.buildPreviewNode(_uiContext(context, owner), node);
      return widget == null ? null : _owned(owner, widget);
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

  Widget? postBodyElement(
    BuildContext context,
    String siteUrl,
    Post post,
    dom.Element element, {
    PluginContainingTopic? topic,
  }) {
    for (final plugin in plugins.whereType<PostBodyPlugin>()) {
      final widget = plugin.postBodyElement(
        PluginPostBodyContext(
          buildContext: _uiContext(context, plugin),
          siteUrl: siteUrl,
          post: post,
          topic: topic,
        ),
        element,
      );
      if (widget != null) return _owned(plugin, widget);
    }
    return null;
  }

  Widget? cookedElement(String? siteUrl, dom.Element element) {
    for (final plugin in plugins.whereType<CookedElementPlugin>()) {
      final widget = plugin.cookedElement(siteUrl, element);
      if (widget != null) return _owned(plugin, widget);
    }
    return null;
  }

  CookedInlinePrefix? cookedInlinePrefix(dom.Element element) {
    for (final plugin in plugins.whereType<CookedInlinePlugin>()) {
      final prefix = plugin.cookedInlinePrefix(element);
      if (prefix != null) {
        return CookedInlinePrefix(
          child: _owned(plugin, prefix.child),
          alignment: prefix.alignment,
          excludeLinkSemantics: prefix.excludeLinkSemantics,
        );
      }
    }
    return null;
  }

  Widget? postFooter(String siteUrl, Post post) {
    for (final plugin in plugins.whereType<PostFooterPlugin>()) {
      final footer = plugin.postFooter(siteUrl, post);
      if (footer != null) return _owned(plugin, footer);
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
      ..._ownedAll(
        plugin,
        plugin.postDecorations(
          _uiContext(context, plugin),
          siteUrl,
          topic,
          post,
        ),
      ),
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
      ..._ownedAll(
        plugin,
        plugin.topicListMetadata(_uiContext(context, plugin), siteUrl, topic),
      ),
  ];

  List<Widget> topicHeader(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => [
    for (final plugin in plugins.whereType<TopicHeaderPlugin>())
      ..._ownedAll(
        plugin,
        plugin.topicHeader(_uiContext(context, plugin), siteUrl, topic),
      ),
  ];

  Listenable? topicHeaderRebuildOn(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final listenables = plugins
        .whereType<TopicHeaderRebuildPlugin>()
        .map(
          (plugin) => plugin.topicHeaderRebuildOn(
            _uiContext(context, plugin),
            siteUrl,
            topic,
          ),
        )
        .whereType<Listenable>()
        .toList(growable: false);
    return switch (listenables) {
      [] => null,
      [final listenable] => listenable,
      _ => Listenable.merge(listenables),
    };
  }

  List<Widget> topicMapActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => [
    for (final plugin in plugins.whereType<TopicMapActionPlugin>())
      ..._ownedAll(
        plugin,
        plugin.topicMapActions(_uiContext(context, plugin), siteUrl, topic),
      ),
  ];

  PostMenuContribution postMenu(
    BuildContext context,
    String siteUrl,
    Post post, {
    required TopicDetail? topic,
    required DiscourseUser? currentUser,
  }) {
    final entries = <PostAction>[];
    final rebuildListenables = <Listenable>[];
    var replacesLike = false;
    for (final plugin in plugins.whereType<PostMenuPlugin>()) {
      final contribution = plugin.postMenu(
        PostMenuContext(
          buildContext: _uiContext(context, plugin),
          siteUrl: siteUrl,
          post: post,
          topic: topic,
          currentUser: currentUser,
        ),
      );
      entries.addAll(contribution.entries);
      replacesLike |= contribution.replacesLike;
      if (contribution.rebuildOn case final listenable?) {
        rebuildListenables.add(listenable);
      }
    }
    if (entries.isEmpty && !replacesLike && rebuildListenables.isEmpty) {
      return PostMenuContribution.none;
    }
    return PostMenuContribution(
      entries: entries,
      replacesLike: replacesLike,
      rebuildOn: switch (rebuildListenables) {
        [] => null,
        [final listenable] => listenable,
        _ => Listenable.merge(rebuildListenables),
      },
    );
  }

  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerController composer,
  ) => [
    for (final plugin in plugins.whereType<ComposerToolbarPlugin>())
      ...plugin.composerToolbar(_uiContext(context, plugin), composer),
  ];

  /// Resolves the one capability which owns [request.kind].
  ///
  /// Null is the plugin-absent answer. A caller must not silently construct a
  /// generic target because doing so would use the wrong draft/upload policy.
  ComposerTargetPolicy? composerTarget(
    ComposerTargetRequest request,
    ComposerTargetContext context,
  ) {
    for (final plugin in plugins.whereType<ComposerTargetPlugin>()) {
      if (plugin.composerTargetKind != request.kind) continue;
      final policy = plugin.createComposerTarget(request, context);
      final pluginName = (plugin as SitePlugin).name;
      if (policy.kind != request.kind) {
        throw StateError(
          '$pluginName returned policy ${policy.kind} '
          'for ${request.kind}.',
        );
      }
      final emojiContext = policy.emojiUsageContext;
      if (emojiContext.owner != PluginId(pluginName) ||
          emojiContext.name.trim().isEmpty ||
          emojiContext.name.contains('/')) {
        throw StateError(
          '$pluginName returned emoji usage context $emojiContext for '
          '${request.kind}; it must be namespaced to $pluginName.',
        );
      }
      if (policy.draftKey.trim().isEmpty) {
        throw StateError(
          '$pluginName returned an empty draft key for ${request.kind}.',
        );
      }
      return policy;
    }
    return null;
  }

  List<ComposerSyntaxPlugin> get composerSyntaxPlugins => List.unmodifiable([
    for (final plugin in plugins.whereType<ComposerSyntaxPlugin>())
      _OwnedComposerSyntaxPlugin(_owner(plugin), plugin),
  ]);

  Map<ShortcutActivator, VoidCallback> composerShortcuts(
    BuildContext context,
    ComposerController composer,
  ) => {
    for (final plugin in plugins.whereType<ComposerShortcutPlugin>())
      ...plugin.composerShortcuts(_uiContext(context, plugin), composer),
  };

  List<Widget> userCardActions(
    BuildContext context,
    String siteUrl,
    UserCard user,
    VoidCallback close,
  ) => [
    for (final plugin in plugins.whereType<UserCardActionPlugin>())
      ..._ownedAll(
        plugin,
        plugin.userCardActions(
          _uiContext(context, plugin),
          siteUrl,
          user,
          close,
        ),
      ),
  ];

  List<PluginUserMenuSection> userMenuSections(PluginUserMenuContext context) {
    final sections = <PluginUserMenuSection>[];
    final owners = <PluginUserMenuSectionId>{};
    for (final plugin in plugins.whereType<UserMenuSectionPlugin>()) {
      final pluginName = (plugin as SitePlugin).name;
      for (final section in plugin.userMenuSections(context)) {
        if (section.id.owner != PluginId(pluginName) ||
            section.id.name.trim().isEmpty ||
            section.id.name.contains('/')) {
          throw StateError(
            'User-menu section ${section.id.id} must be namespaced to '
            '$pluginName.',
          );
        }
        if (!owners.add(section.id)) {
          throw StateError('Duplicate user-menu section ${section.id.id}.');
        }
        final owner = PluginId(pluginName);
        sections.add(
          PluginUserMenuSection(
            id: section.id,
            icon: section.icon,
            label: section.label,
            badge: section.badge,
            builder: (buildContext, actions) => PluginUiScope.own(
              owner,
              section.builder(
                PluginUiScope.contextFor(buildContext, owner),
                actions,
              ),
            ),
          ),
        );
      }
    }
    return List.unmodifiable(sections);
  }

  List<SidebarSection> sidebarSections(BuildContext context) => [
    for (final plugin in plugins.whereType<SidebarPlugin>())
      ...plugin
          .sidebarSections(_uiContext(context, plugin))
          .map((section) => _ownedSection(plugin, section)),
  ];

  List<Listenable> sidebarListenables(BuildContext context) {
    final listenables = <Listenable>[];
    for (final plugin in plugins.whereType<SidebarPlugin>()) {
      final listenable = plugin.sidebarListenable(_uiContext(context, plugin));
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
      final destination = plugin.forumTabDestination(
        _uiContext(context, plugin),
        siteUrl,
        tab,
      );
      if (destination != null) return _ownedDestination(plugin, destination);
    }
    return null;
  }

  List<Listenable> forumTabListenables(BuildContext context, String siteUrl) {
    final listenables = <Listenable>[];
    for (final plugin in plugins.whereType<ForumTabPlugin>()) {
      final listenable = plugin.forumTabListenable(
        _uiContext(context, plugin),
        siteUrl,
      );
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
        _uiContext(context, plugin),
        siteUrl: siteUrl,
        userId: userId,
        url: url,
        size: size,
        fallback: fallback,
      );
      if (avatar != null) return _owned(plugin, avatar);
    }
    return null;
  }

  Widget? content(BuildContext context, ContentRoute route) {
    for (final plugin in plugins.whereType<ContentPlugin>()) {
      final content = plugin.content(_uiContext(context, plugin), route);
      if (content != null) return _owned(plugin, content);
    }
    return null;
  }

  bool ownsContentChrome(BuildContext context, ContentRoute route) =>
      plugins.whereType<ContentChromePlugin>().any(
        (plugin) =>
            plugin.ownsContentChrome(_uiContext(context, plugin), route),
      );

  List<Widget> contentHeaderActions(BuildContext context, ContentRoute route) =>
      [
        for (final plugin in plugins.whereType<ContentHeaderPlugin>())
          ..._ownedAll(
            plugin,
            plugin.contentHeaderActions(_uiContext(context, plugin), route),
          ),
      ];

  Widget? contentHeaderLeading(BuildContext context, ContentRoute route) {
    for (final plugin in plugins.whereType<ContentHeaderLeadingPlugin>()) {
      final leading = plugin.contentHeaderLeading(
        _uiContext(context, plugin),
        route,
      );
      if (leading != null) return _owned(plugin, leading);
    }
    return null;
  }

  VoidCallback? contentHeaderTitleAction(
    BuildContext context,
    ContentRoute route,
  ) {
    for (final plugin in plugins.whereType<ContentHeaderTitlePlugin>()) {
      final action = plugin.contentHeaderTitleAction(
        _uiContext(context, plugin),
        route,
      );
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
      ..._ownedAll(
        plugin,
        plugin.shellHeaderActions(
          _uiContext(context, plugin),
          surface: surface,
          compact: compact,
          ringColor: ringColor,
        ),
      ),
  ];

  List<Widget> shellOverlays(BuildContext context) => [
    for (final plugin in plugins.whereType<ShellOverlayPlugin>())
      ..._ownedAll(plugin, plugin.shellOverlays(_uiContext(context, plugin))),
  ];

  List<DiagnosticsPlugin> get diagnosticsPlugins => List.unmodifiable([
    for (final plugin in plugins.whereType<DiagnosticsPlugin>())
      _OwnedDiagnosticsPlugin(_owner(plugin), plugin),
  ]);

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

final class _OwnedComposerSyntaxPlugin implements ComposerSyntaxPlugin {
  const _OwnedComposerSyntaxPlugin(this.owner, this.delegate);

  final PluginId owner;
  final ComposerSyntaxPlugin delegate;

  @override
  String get syntaxId => delegate.syntaxId;

  @override
  List<Object> parseComposerSyntax(String source) =>
      delegate.parseComposerSyntax(source);

  @override
  int startOf(Object value) => delegate.startOf(value);

  @override
  int endOf(Object value) => delegate.endOf(value);

  @override
  String sourceOf(Object value) => delegate.sourceOf(value);

  @override
  bool needsRawSource(
    Object value,
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) => delegate.needsRawSource(
    value,
    document,
    suppressCollapsedCaret: suppressCollapsedCaret,
  );

  @override
  int caretAfter(Object value, String document) =>
      delegate.caretAfter(value, document);

  @override
  TextEditingValue moveCaretAfter(Object value, TextEditingValue document) =>
      delegate.moveCaretAfter(value, document);

  @override
  bool get supportsHover => delegate.supportsHover;

  @override
  bool get protectsAdjacentDelete => delegate.protectsAdjacentDelete;

  @override
  bool get hidesCursorWhenSelected => delegate.hidesCursorWhenSelected;

  @override
  List<InlineSpan> buildCollapsedSpans({
    required Object value,
    required TextStyle baseStyle,
    required Locale locale,
    required String? accountTimezone,
    required int maximumOptions,
    required GlobalKey pillKey,
    required bool highlighted,
    required bool hovered,
    required bool followedByLineBreak,
  }) => delegate.buildCollapsedSpans(
    value: value,
    baseStyle: baseStyle,
    locale: locale,
    accountTimezone: accountTimezone,
    maximumOptions: maximumOptions,
    pillKey: pillKey,
    highlighted: highlighted,
    hovered: hovered,
    followedByLineBreak: followedByLineBreak,
  );

  @override
  FutureOr<void> editComposerSyntax(
    BuildContext context,
    ComposerController composer,
    Object value,
  ) => delegate.editComposerSyntax(
    PluginUiScope.contextFor(context, owner),
    composer,
    value,
  );

  @override
  FutureOr<void> removeComposerSyntax(
    BuildContext context,
    ComposerController composer,
    Object value,
  ) => delegate.removeComposerSyntax(
    PluginUiScope.contextFor(context, owner),
    composer,
    value,
  );

  @override
  TextInputFormatter? get inputFormatter => delegate.inputFormatter;
}

final class _OwnedDiagnosticsPlugin implements DiagnosticsPlugin {
  const _OwnedDiagnosticsPlugin(this.owner, this.delegate);

  final PluginId owner;
  final DiagnosticsPlugin delegate;

  @override
  String get diagnosticsId => delegate.diagnosticsId;

  @override
  String get diagnosticsLabel => delegate.diagnosticsLabel;

  @override
  Listenable get diagnosticsStatusListenable =>
      delegate.diagnosticsStatusListenable;

  @override
  bool get isDiagnosticsRecording => delegate.isDiagnosticsRecording;

  @override
  String? get diagnosticsRecordingLabel => delegate.diagnosticsRecordingLabel;

  @override
  Widget buildDiagnostics(
    BuildContext context,
    DiagnosticsController diagnostics,
  ) => PluginUiScope.own(
    owner,
    delegate.buildDiagnostics(
      PluginUiScope.contextFor(context, owner),
      diagnostics,
    ),
  );

  @override
  void recordAppLifecycle(String state, {required bool foreground}) =>
      delegate.recordAppLifecycle(state, foreground: foreground);

  @override
  Future<void> flushDiagnostics() => delegate.flushDiagnostics();
}
