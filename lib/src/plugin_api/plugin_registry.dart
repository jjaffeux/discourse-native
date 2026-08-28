import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../diagnostics/diagnostics_controller.dart';
import '../models/content_route.dart';
import '../models/discourse_user.dart';
import '../models/forum_workspace.dart';
import '../models/notification.dart';
import '../models/post.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../models/user_card.dart';
import '../shell/composer_controller.dart';
import '../shell/post_action.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'plugin_scope.dart';
import 'site_plugin_api.dart';

final RegExp _notificationWireNamePattern = RegExp(
  r'^[a-z0-9]+(?:_[a-z0-9]+)*$',
);

/// Immutable dispatch table produced by installing a complete manifest.
@immutable
final class PluginRegistry
    implements
        PluginDataDecoder,
        IconNameDecoder,
        TopicRecommendationSourceDecoder,
        TopicRecommendationSourceMigrationRegistry,
        PluginNotificationCounterCodec {
  const PluginRegistry(this.plugins);

  static const PluginRegistry empty = PluginRegistry([]);

  factory PluginRegistry.validated(Iterable<SitePlugin> plugins) {
    final registry = PluginRegistry(List.unmodifiable(plugins));
    registry._validateRecordOwners();
    registry._validateComposerTargetOwners();
    registry._validateHashtagKinds();
    registry._validateComposerSyntaxOwners();
    registry._validateTopicRecommendationSources();
    registry._validateIconCatalogs();
    registry._validateNotificationTypes();
    registry._validateNotificationFeeds();
    registry._validateNotificationCounters();
    registry._validateCapabilityCardinality();
    return registry;
  }

  void _validateCapabilityCardinality() {
    _validateUniqueKeys<PluginSiteFeature>(
      'site-feature owner',
      (plugin) => _ownerOf(plugin),
    );
    _validateUniqueKeys<PluginCurrentUserFeature>(
      'current-user feature owner',
      (plugin) => _ownerOf(plugin),
    );
    _validateUniqueKeys<DiagnosticsPlugin>(
      'diagnostics id',
      (plugin) => plugin.diagnosticsId,
    );
  }

  void _validateUniqueKeys<T extends Object>(
    String kind,
    String Function(T capability) readKey,
  ) {
    final owners = <String, String>{};
    for (final capability in plugins.whereType<T>()) {
      final owner = _ownerOf(capability);
      final key = readKey(capability);
      if (key.trim().isEmpty) {
        throw ArgumentError('$kind registered by $owner must not be empty.');
      }
      final previous = owners[key];
      if (previous != null) {
        throw ArgumentError(
          '$kind $key is provided by both $previous and $owner.',
        );
      }
      owners[key] = owner;
    }
  }

  static String _ownerOf(Object capability) => (capability as SitePlugin).name;

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

  void _validateHashtagKinds() {
    final owners = <String, String>{'category': 'core', 'tag': 'core'};
    for (final plugin in plugins.whereType<HashtagKindPlugin>()) {
      final pluginName = (plugin as SitePlugin).name;
      for (final kind in plugin.hashtagKinds) {
        final wireType = kind.wireType;
        if (wireType.isEmpty || wireType.trim() != wireType) {
          throw ArgumentError(
            'Hashtag wire type "$wireType" registered by $pluginName must '
            'be nonempty and already trimmed.',
          );
        }
        final previous = owners[wireType];
        if (previous != null) {
          throw ArgumentError(
            'Hashtag wire type $wireType is claimed by both $previous and '
            '$pluginName.',
          );
        }
        owners[wireType] = pluginName;
      }
    }
    final pluginKindCount = owners.length - 2;
    if (pluginKindCount > maximumPluginHashtagKinds) {
      throw ArgumentError(
        'At most $maximumPluginHashtagKinds plugin hashtag kinds can be '
        'registered; found $pluginKindCount.',
      );
    }
  }

  void _validateComposerSyntaxOwners() {
    final owners = <ComposerSyntaxKind, String>{};
    for (final plugin in plugins.whereType<ComposerSyntaxPlugin>()) {
      final pluginName = (plugin as SitePlugin).name;
      final kind = plugin.composerSyntaxKind;
      if (kind.owner != PluginId(pluginName) ||
          kind.name.trim().isEmpty ||
          kind.name.contains('/')) {
        throw ArgumentError(
          'Composer syntax $kind must be namespaced to $pluginName.',
        );
      }
      final previous = owners[kind];
      if (previous != null) {
        throw ArgumentError(
          'Composer syntax $kind is claimed by both $previous and $pluginName.',
        );
      }
      owners[kind] = pluginName;
    }
  }

  final List<SitePlugin> plugins;

  List<PluginIconCatalog> get iconCatalogs => List.unmodifiable([
    for (final plugin in plugins.whereType<IconCatalogPlugin>())
      plugin.iconCatalog,
  ]);

  /// Resolves a core or installed-plugin icon name.
  ///
  /// Unknown names deliberately answer [fallback], including names owned by a
  /// plugin which is not installed in this composition.
  @override
  DIconData iconNamed(String? name, {required DIconData fallback}) {
    final core = name == null ? null : DIcons.byName[name];
    if (core != null) return core;
    for (final catalog in iconCatalogs) {
      final icon = catalog.iconNamed(name);
      if (icon != null) return icon;
    }
    return fallback;
  }

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
    prefixBuilder: destination.prefixBuilder != null
        ? (context, size) => _owned(
            plugin,
            destination.prefixBuilder!(_uiContext(context, plugin), size),
          )
        : null,
    labelSuffixBuilder: destination.labelSuffixBuilder != null
        ? (context, size) => _owned(
            plugin,
            destination.labelSuffixBuilder!(_uiContext(context, plugin), size),
          )
        : null,
    semanticDescription: destination.semanticDescription,
    iconColor: destination.iconColor,
    routeColor: destination.routeColor,
    prefixBadgeIcon: destination.prefixBadgeIcon,
    badge: destination.badge,
    onTap: destination.onTap,
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
          for (final codec in plugin.topicRecommendationSourceCodecs)
            codec.definition,
      ]);

  @override
  List<TopicRecommendationSourcePayload> readTopicRecommendationSources(
    Map<String, dynamic> json,
  ) => List.unmodifiable([
    for (final plugin in plugins.whereType<TopicRecommendationSourcePlugin>())
      for (final codec in plugin.topicRecommendationSourceCodecs)
        if (codec.decodeTopicRows(json) case final rows?)
          TopicRecommendationSourcePayload(
            definition: codec.definition,
            topicRows: rows,
          ),
  ]);

  @override
  TopicRecommendationSourceId? migrateLegacyStoredId(String storedId) {
    for (final plugin in plugins.whereType<TopicRecommendationSourcePlugin>()) {
      for (final codec in plugin.topicRecommendationSourceCodecs) {
        if (codec.legacyStoredIds.contains(storedId)) {
          return codec.definition.id;
        }
      }
    }
    return null;
  }

  List<PluginNotificationFeedSource> get notificationFeeds =>
      List.unmodifiable([
        for (final plugin in plugins.whereType<NotificationFeedPlugin>())
          ...plugin.notificationFeeds,
      ]);

  PluginNotificationFeedSource? notificationFeed(PluginNotificationFeedId id) =>
      notificationFeeds.where((source) => source.id == id).firstOrNull;

  List<PluginNotificationType> get notificationTypes => List.unmodifiable([
    for (final plugin in plugins.whereType<NotificationTypePlugin>())
      ...plugin.notificationTypes,
  ]);

  PluginNotificationType? notificationType(NotificationTypeId id) =>
      notificationTypes
          .where((definition) => definition.wireType.wireId == id.value)
          .firstOrNull;

  /// Resolves an installed feature's type, a core type, or the generic safe
  /// fallback, in that order. A bad plugin decoder degrades only its own row.
  ResolvedNotification resolveNotification(DiscourseNotification notification) {
    final definition = notificationType(notification.typeId);
    if (definition == null) return resolveCoreNotification(notification);
    try {
      return definition.decode(notification) ??
          fallbackNotification(notification);
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'notifications.decode.${definition.id.id}',
        source: definition.id.owner.value,
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
      return fallbackNotification(notification);
    }
  }

  @override
  List<PluginNotificationCounter> get notificationCounters =>
      List.unmodifiable([
        for (final plugin in plugins.whereType<NotificationCounterPlugin>())
          ...plugin.notificationCounters,
      ]);

  PluginNotificationCounter? notificationCounter(
    PluginNotificationCounterId id,
  ) => notificationCounters.where((counter) => counter.id == id).firstOrNull;

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
    final legacyIdOwners = <String, String>{
      coreSuggestedTopicRecommendationLegacyStoredId: 'core',
    };
    for (final plugin in plugins.whereType<TopicRecommendationSourcePlugin>()) {
      final pluginName = (plugin as SitePlugin).name;
      for (final codec in plugin.topicRecommendationSourceCodecs) {
        final source = codec.definition;
        if (!source.id.isNamespaced || source.id.namespace != pluginName) {
          throw ArgumentError(
            'Topic recommendation source ${source.id} must be namespaced to '
            '$pluginName.',
          );
        }
        if (source.label.trim().isEmpty) {
          throw ArgumentError(
            'Topic recommendation source ${source.id} must declare a label.',
          );
        }
        final previousIdOwner = idOwners[source.id];
        if (previousIdOwner != null) {
          throw ArgumentError(
            'Topic recommendation source ${source.id} is claimed by both '
            '$previousIdOwner and $pluginName.',
          );
        }
        idOwners[source.id] = pluginName;
        for (final legacyId in codec.legacyStoredIds) {
          if (legacyId.trim() != legacyId ||
              legacyId.isEmpty ||
              TopicRecommendationSourceId(legacyId).isNamespaced) {
            throw ArgumentError(
              'Legacy topic recommendation id "$legacyId" registered by '
              '$pluginName must be a trimmed pre-stable value.',
            );
          }
          final previousLegacyOwner = legacyIdOwners[legacyId];
          if (previousLegacyOwner != null) {
            throw ArgumentError(
              'Legacy topic recommendation id "$legacyId" is claimed by '
              'both $previousLegacyOwner and $pluginName.',
            );
          }
          legacyIdOwners[legacyId] = pluginName;
        }
      }
    }
  }

  void _validateIconCatalogs() {
    final owners = <String, String>{
      for (final name in DIcons.byName.keys) name: 'core',
    };
    for (final plugin in plugins.whereType<IconCatalogPlugin>()) {
      final pluginName = (plugin as SitePlugin).name;
      final catalog = plugin.iconCatalog;
      if (catalog.owner != PluginId(pluginName)) {
        throw ArgumentError(
          'Icon catalog ${catalog.owner} is registered by $pluginName.',
        );
      }
      for (final name in catalog.entries.keys) {
        if (name.isEmpty || name.trim() != name) {
          throw ArgumentError(
            'Icon names contributed by $pluginName must not be empty or padded.',
          );
        }
        final previous = owners[name];
        if (previous != null) {
          throw ArgumentError(
            'Icon name $name is claimed by both $previous and $pluginName.',
          );
        }
        owners[name] = pluginName;
      }
    }
  }

  void _validateNotificationFeeds() {
    final owners = <PluginNotificationFeedId, String>{};
    final typeOwners = <NotificationTypeName, String>{
      for (final plugin in plugins.whereType<NotificationTypePlugin>())
        for (final type in plugin.notificationTypes)
          NotificationTypeName(type.wireType.wireName):
              (plugin as SitePlugin).name,
    };
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
        if (source.filterByTypes.isEmpty ||
            source.filterByTypes.any(
              (type) => typeOwners[type] != pluginName,
            )) {
          throw ArgumentError(
            'Notification feed ${source.id.id} must filter only notification '
            'types owned by $pluginName.',
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

  void _validateNotificationTypes() {
    final definitionOwners = <PluginNotificationTypeId, String>{
      for (final definition in coreNotificationTypes) definition.id: 'core',
    };
    final idOwners = <NotificationTypeId, String>{
      for (final definition in coreNotificationTypes)
        NotificationTypeId(definition.wireType.wireId): 'core',
    };
    final nameOwners = <NotificationTypeName, String>{
      for (final definition in coreNotificationTypes)
        NotificationTypeName(definition.wireType.wireName): 'core',
    };
    for (final plugin in plugins.whereType<NotificationTypePlugin>()) {
      final pluginName = (plugin as SitePlugin).name;
      for (final definition in plugin.notificationTypes) {
        if (definition.id.owner != PluginId(pluginName) ||
            definition.id.name.trim().isEmpty ||
            definition.id.name.contains('/')) {
          throw ArgumentError(
            'Notification type ${definition.id.id} must be namespaced to '
            '$pluginName.',
          );
        }
        if (definition.wireType.wireId <= 0 ||
            !_notificationWireNamePattern.hasMatch(
              definition.wireType.wireName,
            )) {
          throw ArgumentError(
            'Notification type ${definition.id.id} must declare a positive '
            'wire id and a snake-case wire name.',
          );
        }
        final previousDefinition = definitionOwners[definition.id];
        if (previousDefinition != null) {
          throw ArgumentError(
            'Notification type ${definition.id.id} is claimed by both '
            '$previousDefinition and $pluginName.',
          );
        }
        final wireId = NotificationTypeId(definition.wireType.wireId);
        final wireName = NotificationTypeName(definition.wireType.wireName);
        final previousId = idOwners[wireId];
        if (previousId != null) {
          throw ArgumentError(
            'Notification wire id ${definition.wireType.wireId} is claimed '
            'by both $previousId and $pluginName.',
          );
        }
        final previousName = nameOwners[wireName];
        if (previousName != null) {
          throw ArgumentError(
            'Notification wire name ${definition.wireType.wireName} is '
            'claimed by both $previousName and $pluginName.',
          );
        }
        definitionOwners[definition.id] = pluginName;
        idOwners[wireId] = pluginName;
        nameOwners[wireName] = pluginName;
      }
    }
  }

  void _validateNotificationCounters() {
    const coreWireNames = {
      'unread_notifications',
      'unread_personal_messages',
      'unseen_reviewables',
      'topic_tracking',
      'username',
    };
    final idOwners = <PluginNotificationCounterId, String>{};
    final wireOwners = <String, String>{
      for (final name in coreWireNames) name: 'core',
    };
    for (final plugin in plugins.whereType<NotificationCounterPlugin>()) {
      final pluginName = (plugin as SitePlugin).name;
      for (final counter in plugin.notificationCounters) {
        if (counter.id.owner != PluginId(pluginName) ||
            counter.id.name.trim().isEmpty ||
            counter.id.name.contains('/')) {
          throw ArgumentError(
            'Notification counter ${counter.id.id} must be namespaced to '
            '$pluginName.',
          );
        }
        if (!_notificationWireNamePattern.hasMatch(counter.wireName)) {
          throw ArgumentError(
            'Notification counter ${counter.id.id} must declare a snake-case '
            'wire name.',
          );
        }
        final previousIdOwner = idOwners[counter.id];
        if (previousIdOwner != null) {
          throw ArgumentError(
            'Notification counter ${counter.id.id} is claimed by both '
            '$previousIdOwner and $pluginName.',
          );
        }
        final previousWireOwner = wireOwners[counter.wireName];
        if (previousWireOwner != null) {
          throw ArgumentError(
            'Notification counter wire name ${counter.wireName} is claimed '
            'by both $previousWireOwner and $pluginName.',
          );
        }
        idOwners[counter.id] = pluginName;
        wireOwners[counter.wireName] = pluginName;
      }
    }
  }

  @override
  PluginNotificationCounters readLiveNotificationCounters(
    Map<String, dynamic> json,
  ) => PluginNotificationCounters.fromLive(notificationCounters, json);

  @override
  PluginNotificationCounters readStoredNotificationCounters(Object? value) =>
      PluginNotificationCounters.fromStored(notificationCounters, value);

  @override
  Map<String, Object?> writeStoredNotificationCounters(
    PluginNotificationCounters counters,
  ) => counters.toStored(notificationCounters);

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
        final value = codec.decodeStored(
          namespacedValue: stored,
          hasNamespacedValue: hasNamespacedValue,
          record: json,
        );
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

  /// Resolves an installed plugin-owned hashtag type.
  ///
  /// Core category/tag behavior and the safe unknown fallback deliberately
  /// remain with the shell, so null means either of those paths should answer.
  HashtagPresentation? pluginHashtagPresentation(
    HashtagPresentationRequest request,
  ) {
    for (final plugin in plugins.whereType<HashtagKindPlugin>()) {
      for (final kind in plugin.hashtagKinds) {
        if (kind.wireType != request.type) continue;
        try {
          final presentation = kind.present(request);
          // A presenter owns appearance, never the server's identity. Treat a
          // broken contribution exactly like an absent one so the shell's
          // neutral fallback can keep the original type readable.
          return presentation.type == request.type ? presentation : null;
        } catch (error, stackTrace) {
          DiagnosticsSink.current.reportError(
            error,
            stackTrace,
            operation: 'hashtag.kind.present',
            source: (plugin as SitePlugin).name,
            severity: DiagnosticSeverity.warning,
            handled: true,
            degraded: true,
          );
          return null;
        }
      }
    }
    return null;
  }

  /// Plugin wire types recognized by composer search and exact-ref lookup.
  ///
  /// Registration is the single source of truth: rendering and recognition
  /// cannot race separate per-site session state or drift apart.
  List<String> get pluginHashtagWireTypes => List.unmodifiable([
    for (final plugin in plugins.whereType<HashtagKindPlugin>())
      for (final kind in plugin.hashtagKinds) kind.wireType,
  ]);

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

  List<TopicPropertySection> topicProperties(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => [
    for (final plugin in plugins.whereType<TopicPropertiesPlugin>())
      for (final section in plugin.topicProperties(
        _uiContext(context, plugin),
        siteUrl,
        topic,
      ))
        TopicPropertySection(
          label: section.label,
          values: _ownedAll(plugin, section.values),
        ),
  ];

  Listenable? topicPropertiesRebuildOn(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final listenables = plugins
        .whereType<TopicPropertiesRebuildPlugin>()
        .map(
          (plugin) => plugin.topicPropertiesRebuildOn(
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
    ComposerEditorHost editor,
  ) => [
    for (final plugin in plugins.whereType<ComposerToolbarPlugin>())
      ...plugin.composerToolbar(_uiContext(context, plugin), editor),
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

  List<ComposerSyntaxPolicy> composerSyntaxPolicies(
    ComposerSyntaxPolicyContext context,
  ) => List.unmodifiable([
    for (final plugin in plugins.whereType<ComposerSyntaxPlugin>())
      _composerSyntaxPolicy(plugin, context),
  ]);

  ComposerSyntaxPolicy _composerSyntaxPolicy(
    ComposerSyntaxPlugin plugin,
    ComposerSyntaxPolicyContext context,
  ) {
    final policy = plugin.createComposerSyntaxPolicy(context);
    if (policy.kind != plugin.composerSyntaxKind) {
      throw StateError(
        '${(plugin as SitePlugin).name} returned syntax policy ${policy.kind} '
        'for ${plugin.composerSyntaxKind}.',
      );
    }
    return policy;
  }

  Map<ShortcutActivator, VoidCallback> composerShortcuts(
    BuildContext context,
    ComposerEditorHost editor,
  ) => {
    for (final plugin in plugins.whereType<ComposerShortcutPlugin>())
      ...plugin.composerShortcuts(_uiContext(context, plugin), editor),
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
    PluginDiagnosticsReadExportHost diagnostics,
  ) => PluginUiScope.own(
    owner,
    delegate.buildDiagnostics(
      PluginUiScope.contextFor(context, owner),
      diagnostics,
    ),
  );
}
