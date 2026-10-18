import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../data/site_preference_keys.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../models/content_route.dart';
import '../models/discourse_user.dart';
import '../models/forum_workspace.dart';
import '../models/notification.dart';
import '../models/post.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../models/user_card.dart';
import '../models/user_draft.dart';
import '../models/user_preferences.dart';
import '../shell/composer/controller.dart';
import '../shell/post_action.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'global_search.dart';
import 'plugin_manifest.dart';
import 'plugin_scope.dart';
import 'site_plugin_api.dart';

final RegExp _notificationWireNamePattern = RegExp(
  r'^[a-z0-9]+(?:_[a-z0-9]+)*$',
);

typedef _OwnedNotificationFeedDeclaration = ({
  String owner,
  PluginNotificationFeedSource source,
});

final class _OwnedComposerComponentRegistrar
    implements ComposerComponentRegistrar {
  _OwnedComposerComponentRegistrar({
    required this.pluginName,
    required this.kind,
    required this.registrar,
  });

  final String pluginName;
  final ComposerSyntaxKind kind;
  final ComposerComponentRegistrar registrar;

  void Function()? _forward;
  bool _invalid = false;
  bool _sealed = false;

  @override
  void add<T extends Object>(ComposerComponent<T> component) {
    if (_sealed || _forward != null) {
      _invalid = true;
      throw StateError(
        '$pluginName must register exactly one composer component for $kind.',
      );
    }
    if (component.kind != kind) {
      _invalid = true;
      throw StateError(
        '$pluginName returned composer component ${component.kind} for $kind.',
      );
    }
    _forward = () => registrar.add<T>(component);
  }

  void seal() {
    _sealed = true;
    if (_invalid || _forward == null) {
      throw StateError(
        '$pluginName must register exactly one composer component for $kind.',
      );
    }
  }

  void forward() => _forward!();
}

PluginNotificationFeedSource _freezeNotificationFeedSource(
  PluginNotificationFeedSource source,
) {
  final dismissal = source.dismissal;
  return PluginNotificationFeedSource(
    id: source.id,
    filterByTypes: List.unmodifiable(source.filterByTypes),
    reconnectMessage: source.reconnectMessage,
    failureMessage: source.failureMessage,
    emptyMessage: source.emptyMessage,
    compare: source.compare,
    dismissal: dismissal == null
        ? null
        : PluginNotificationFeedDismissal(
            notificationTypes: List.unmodifiable(dismissal.notificationTypes),
            buttonLabel: dismissal.buttonLabel,
            buttonTooltip: dismissal.buttonTooltip,
            confirmationMessage: dismissal.confirmationMessage,
          ),
  );
}

@immutable
final class PluginRegistry
    implements
        PluginDataDecoder,
        IconNameDecoder,
        TopicRecommendationSourceDecoder,
        TopicRecommendationSourceMigrationRegistry,
        PluginNotificationCounterCodec {
  const PluginRegistry(this.plugins) : _installed = null;

  const PluginRegistry._validated(this.plugins, this._installed);

  static const PluginRegistry empty = PluginRegistry([]);

  /// Captures installation metadata once while retaining live plugin hooks.
  /// [modules] ties host registration claims to those same captured identities.
  factory PluginRegistry.validated(
    Iterable<SitePlugin> plugins, {
    Map<PluginDescriptor, List<PluginCapability>> modules = const {},
  }) {
    final installed = List<SitePlugin>.unmodifiable(plugins);
    final registry = PluginRegistry._validated(
      installed,
      _InstalledDeclarations(installed),
    );
    registry._validateModuleDeclarations(modules);
    registry._validateRecordOwners();
    registry._validateComposerTargetOwners();
    registry._validateHashtagKinds();
    registry._validateComposerSyntaxOwners();
    registry._validateComposerComponentOwners();
    registry._validateTopicRecommendationSources();
    registry._validateIconCatalogs();
    registry._validateNotificationTypes();
    registry._validateNotificationFeeds();
    registry._validateNotificationCounters();
    registry._validateCapabilityCardinality();
    return registry;
  }

  void _validateModuleDeclarations(
    Map<PluginDescriptor, List<PluginCapability>> modules,
  ) {
    for (final entry in modules.entries) {
      final descriptor = entry.key;
      for (final capability in entry.value) {
        if (capability is SitePlugin &&
            !_installed!.owners.containsKey(capability)) {
          throw ArgumentError(
            '${descriptor.id} refers to an uninstalled capability.',
          );
        }
        final owner = capability is SitePlugin
            ? _ownerOf(capability)
            : capability.name;
        if (owner != descriptor.id.value) {
          throw ArgumentError('${descriptor.id} registered capability $owner.');
        }
        if (capability is! SitePlugin && capability is PluginRecord<Object>) {
          final key = (capability as PluginRecord<Object>).record;
          if (key.owner != descriptor.id.value) {
            throw ArgumentError(
              '${descriptor.id} registered record ${key.id}, which is owned by ${key.owner}.',
            );
          }
        }
      }
      final legacy = <String>{};
      final components = <String>{};
      for (final plugin in entry.value.whereType<ComposerSyntaxPlugin>()) {
        final id = _syntaxKindFor(plugin).id;
        if (!legacy.add(id)) {
          throw ArgumentError(
            '${descriptor.id} registered duplicate composer syntax id $id.',
          );
        }
      }
      for (final plugin in entry.value.whereType<ComposerComponentPlugin>()) {
        final id = _componentKindFor(plugin).id;
        if (!components.add(id)) {
          throw ArgumentError(
            '${descriptor.id} registered duplicate composer component syntax id $id.',
          );
        }
      }
      final registered = {...legacy, ...components};
      if (descriptor.syntaxIds.length != registered.length ||
          !descriptor.syntaxIds.containsAll(registered)) {
        final declaredIds = descriptor.syntaxIds.toList()..sort();
        final registeredIds = registered.toList()..sort();
        throw ArgumentError(
          '${descriptor.id} declared composer syntax ids '
          '{${declaredIds.join(', ')}} but registered {${registeredIds.join(', ')}}.',
        );
      }
    }
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
      (plugin) => _diagnosticsIdFor(plugin),
    );
    _validateUniqueKeys<GroupTabPlugin>(
      'group tab owner',
      (plugin) => _ownerOf(plugin),
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

  String _ownerOf(Object capability) =>
      _installed?.owners[capability] ?? (capability as SitePlugin).name;

  void _validateComposerTargetOwners() {
    final owners = <ComposerTargetKind, String>{};
    for (final plugin in plugins.whereType<ComposerTargetPlugin>()) {
      final pluginName = _ownerOf(plugin);
      final kind = _targetKindFor(plugin);
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
      final pluginName = _ownerOf(plugin);
      for (final kind in _hashtagKindsFor(plugin)) {
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
      final pluginName = _ownerOf(plugin);
      final kind = _syntaxKindFor(plugin);
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

  void _validateComposerComponentOwners() {
    final owners = <ComposerSyntaxKind, String>{};
    for (final plugin in plugins.whereType<ComposerComponentPlugin>()) {
      final pluginName = _ownerOf(plugin);
      final kind = _componentKindFor(plugin);
      if (kind.owner != PluginId(pluginName) ||
          kind.name.trim().isEmpty ||
          kind.name.contains('/')) {
        throw ArgumentError(
          'Composer component $kind must be namespaced to $pluginName.',
        );
      }
      final previous = owners[kind];
      if (previous != null) {
        throw ArgumentError(
          'Composer component $kind is claimed by both $previous and '
          '$pluginName.',
        );
      }
      owners[kind] = pluginName;
    }
  }

  final List<SitePlugin> plugins;
  final _InstalledDeclarations? _installed;

  PluginDataKey<Object> _recordKeyFor(PluginRecord<Object> plugin) =>
      _installed?.recordKeys[plugin] ?? plugin.record;

  PluginDataKey<Object> _groupRecordKeyFor(GroupRecordPlugin<Object> plugin) =>
      _installed?.groupRecordKeys[plugin] ?? plugin.groupRecord;

  PluginDataPersistenceCodec<Object> _siteSettingsCodecFor(
    SiteSettingsPlugin<Object> plugin,
  ) => _installed?.siteSettingsCodecs[plugin] ?? plugin.siteSettingsCodec;

  PluginDataPersistenceCodec<Object> _currentUserCodecFor(
    CurrentUserPlugin<Object> plugin,
  ) => _installed?.currentUserCodecs[plugin] ?? plugin.currentUserCodec;

  ComposerTargetKind _targetKindFor(ComposerTargetPlugin plugin) =>
      _installed?.targetKinds[plugin] ?? plugin.composerTargetKind;

  ComposerSyntaxKind _syntaxKindFor(ComposerSyntaxPlugin plugin) =>
      _installed?.syntaxKinds[plugin] ?? plugin.composerSyntaxKind;

  ComposerSyntaxKind _componentKindFor(ComposerComponentPlugin plugin) =>
      _installed?.componentKinds[plugin] ?? plugin.composerComponentKind;

  List<PluginHashtagKind> _hashtagKindsFor(HashtagKindPlugin plugin) =>
      _installed?.hashtagKinds[plugin] ?? plugin.hashtagKinds;

  List<TopicRecommendationSourceCodec> _recommendationCodecsFor(
    TopicRecommendationSourcePlugin plugin,
  ) =>
      _installed?.recommendationCodecs[plugin] ??
      plugin.topicRecommendationSourceCodecs;

  PluginIconCatalog _iconCatalogFor(IconCatalogPlugin plugin) =>
      _installed?.iconCatalogs[plugin] ?? plugin.iconCatalog;

  List<PluginNotificationType> _notificationTypesFor(
    NotificationTypePlugin plugin,
  ) => _installed?.notificationTypes[plugin] ?? plugin.notificationTypes;

  List<PluginNotificationFeedSource> _notificationFeedsFor(
    NotificationFeedPlugin plugin,
  ) => _installed?.notificationFeeds[plugin] ?? plugin.notificationFeeds;

  List<PluginNotificationCounter> _notificationCountersFor(
    NotificationCounterPlugin plugin,
  ) => _installed?.notificationCounters[plugin] ?? plugin.notificationCounters;

  List<SitePreferenceKey> _sitePreferenceKeysFor(
    SitePreferencesPlugin plugin,
  ) => _installed?.sitePreferenceKeys[plugin] ?? plugin.sitePreferenceKeys;

  String _diagnosticsIdFor(DiagnosticsPlugin plugin) =>
      _installed?.diagnosticsIds[plugin] ?? plugin.diagnosticsId;

  List<UserPreferenceCodec> _preferenceCodecsFor(
    UserPreferencesPlugin plugin,
  ) => _installed?.preferenceCodecs[plugin] ?? plugin.userPreferenceCodecs;

  List<GlobalSearchContribution> _searchContributionsFor(
    GlobalSearchPlugin plugin,
  ) => _installed?.searchContributions[plugin] ?? plugin.searchContributions;

  /// Every preference plugins keep per forum; see [SitePreferencesPlugin].
  List<SitePreferenceKey> get sitePreferenceKeys => List.unmodifiable([
    for (final plugin in plugins.whereType<SitePreferencesPlugin>())
      ..._sitePreferenceKeysFor(plugin),
  ]);

  List<PluginIconCatalog> get iconCatalogs => List.unmodifiable([
    for (final plugin in plugins.whereType<IconCatalogPlugin>())
      _iconCatalogFor(plugin),
  ]);

  @override
  DIconData iconNamed(String? name, {required DIconData fallback}) =>
      findIconNamed(name) ?? fallback;

  DIconData? findIconNamed(String? name) {
    final core = name == null ? null : DIcons.byName[name];
    if (core != null) return core;
    if (_installed != null) return _installed.iconsByName[name];
    for (final catalog in iconCatalogs) {
      final icon = catalog.iconNamed(name);
      if (icon != null) return icon;
    }
    return null;
  }

  PluginId _owner(Object plugin) => PluginId(_ownerOf(plugin));

  BuildContext _uiContext(BuildContext context, Object plugin) =>
      PluginUiScope.contextFor(context, _owner(plugin));

  Widget _owned(Object plugin, Widget child) {
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

  List<Widget> _ownedAll(Object plugin, Iterable<Widget> children) => [
    for (final child in children) _owned(plugin, child),
  ];

  SidebarDestination _ownedDestination(
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
    mobileNavigationLabel: destination.mobileNavigationLabel,
    iconColor: destination.iconColor,
    routeColor: destination.routeColor,
    prefixBadgeIcon: destination.prefixBadgeIcon,
    badge: destination.badge,
    unreadCount: destination.unreadCount,
    preview: destination.preview,
    lastActivityAt: destination.lastActivityAt,
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
    contextMenuBuilder: destination.contextMenuBuilder != null
        ? (context, child) => _owned(
            plugin,
            destination.contextMenuBuilder!(_uiContext(context, plugin), child),
          )
        : null,
    url: destination.url,
    feedPath: destination.feedPath,
  );

  SidebarSection _ownedSection(Object plugin, SidebarSection section) =>
      SidebarSection(
        id: section.id,
        title: section.title,
        unreadCount: section.unreadCount,
        loading: section.loading,
        destinations: [
          for (final destination in section.destinations)
            _ownedDestination(plugin, destination),
        ],
        showHeader: section.showHeader,
        collapsible: section.collapsible,
        actionIcon: section.actionIcon,
        actionLabel: section.actionLabel,
        actionShortcut: section.actionShortcut,
        onAction: section.onAction,
        actionAboveHeader: section.actionAboveHeader,
        headerActionsBuilder: section.headerActionsBuilder == null
            ? null
            : (context) => _owned(
                plugin,
                section.headerActionsBuilder!(_uiContext(context, plugin)),
              ),
        pinnedHeaderBuilder: section.pinnedHeaderBuilder == null
            ? null
            : (context) => _owned(
                plugin,
                section.pinnedHeaderBuilder!(_uiContext(context, plugin)),
              ),
        bodyBuilder: section.bodyBuilder == null
            ? null
            : (context) => _owned(
                plugin,
                section.bodyBuilder!(_uiContext(context, plugin)),
              ),
      );

  List<OwnedPluginGroupTab> ownedGroupTabs(PluginGroupContext group) =>
      List.unmodifiable([
        for (final plugin in plugins.whereType<GroupTabPlugin>())
          if (plugin.groupTab(group) case final tab?)
            OwnedPluginGroupTab(
              owner: _owner(plugin),
              tab: _validateGroupTab(plugin, tab),
            ),
      ]);

  Widget? groupContent(BuildContext context, PluginGroupContext group) {
    if (!group.route.isPlugin) return null;
    for (final plugin in plugins.whereType<GroupTabPlugin>()) {
      if (_ownerOf(plugin) != group.route.pluginOwner) continue;
      final content = plugin.groupContent(_uiContext(context, plugin), group);
      return content == null ? null : _owned(plugin, content);
    }
    return null;
  }

  Listenable? groupListenable(BuildContext context, PluginGroupContext group) {
    if (!group.route.isPlugin) return null;
    for (final plugin in plugins.whereType<GroupTabPlugin>()) {
      if (_ownerOf(plugin) != group.route.pluginOwner) continue;
      return plugin.groupListenable(_uiContext(context, plugin), group);
    }
    return null;
  }

  PluginGroupTab _validateGroupTab(GroupTabPlugin plugin, PluginGroupTab tab) {
    final section = tab.section;
    if (section.isEmpty ||
        section.trim() != section ||
        section.contains('/') ||
        section.contains('\\')) {
      throw StateError(
        '${_ownerOf(plugin)} returned invalid group tab $section.',
      );
    }
    if (tab.label.trim().isEmpty || (tab.count != null && tab.count! < 0)) {
      throw StateError(
        '${_ownerOf(plugin)} returned invalid group tab metadata.',
      );
    }
    return tab;
  }

  @override
  List<TopicRecommendationSourceDefinition> get topicRecommendationSources =>
      List.unmodifiable([
        for (final plugin
            in plugins.whereType<TopicRecommendationSourcePlugin>())
          for (final codec in _recommendationCodecsFor(plugin))
            codec.definition,
      ]);

  @override
  List<TopicRecommendationSourcePayload> readTopicRecommendationSources(
    Map<String, dynamic> json,
  ) => List.unmodifiable([
    for (final plugin in plugins.whereType<TopicRecommendationSourcePlugin>())
      for (final codec in _recommendationCodecsFor(plugin))
        if (codec.decodeTopicRows(json) case final rows?)
          TopicRecommendationSourcePayload(
            definition: codec.definition,
            topicRows: rows,
          ),
  ]);

  @override
  TopicRecommendationSourceId? migrateLegacyStoredId(String storedId) {
    if (_installed != null) {
      return _installed.recommendationIdsByLegacyId[storedId];
    }
    for (final plugin in plugins.whereType<TopicRecommendationSourcePlugin>()) {
      for (final codec in _recommendationCodecsFor(plugin)) {
        if (codec.legacyStoredIds.contains(storedId)) {
          return codec.definition.id;
        }
      }
    }
    return null;
  }

  List<_OwnedNotificationFeedDeclaration> get _notificationFeedDeclarations => [
    for (final plugin in plugins.whereType<NotificationFeedPlugin>())
      for (final source in _notificationFeedsFor(plugin))
        (owner: _ownerOf(plugin), source: source),
  ];

  List<PluginNotificationFeedSource> get notificationFeeds =>
      List.unmodifiable([
        for (final plugin in plugins.whereType<NotificationFeedPlugin>())
          ..._notificationFeedsFor(plugin),
      ]);

  PluginNotificationFeedSource? notificationFeed(PluginNotificationFeedId id) =>
      _installed != null
      ? _installed.feedsById[id]
      : notificationFeeds.where((source) => source.id == id).firstOrNull;

  List<PluginNotificationType> get notificationTypes => List.unmodifiable([
    for (final plugin in plugins.whereType<NotificationTypePlugin>())
      ..._notificationTypesFor(plugin),
  ]);

  PluginNotificationType? notificationType(NotificationTypeId id) =>
      _installed != null
      ? _installed.typesById[id]
      : notificationTypes
            .where((definition) => definition.wireType.wireId == id.value)
            .firstOrNull;

  /// [notification] as it reads on [siteUrl], the forum it came from.
  ResolvedNotification resolveNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) {
    final definition = notificationType(notification.typeId);
    if (definition == null) {
      return resolveCoreNotification(siteUrl, notification);
    }
    try {
      return definition.decode(siteUrl, notification) ??
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
          ..._notificationCountersFor(plugin),
      ]);

  PluginNotificationCounter? notificationCounter(
    PluginNotificationCounterId id,
  ) => _installed != null
      ? _installed.countersById[id]
      : notificationCounters.where((counter) => counter.id == id).firstOrNull;

  bool compactEmojiAncestor(dom.Element element) => plugins
      .whereType<CompactEmojiPlugin>()
      .any((plugin) => plugin.compactEmojiAncestor(element));

  PluginDraftPresentation? draftPresentation(UserDraft draft) {
    final matches = [
      for (final plugin in plugins.whereType<DraftPresentationPlugin>())
        ?plugin.draftPresentation(draft),
    ];
    if (matches.length > 1) {
      throw StateError('Multiple plugins claim draft ${draft.key}');
    }
    return matches.firstOrNull;
  }

  List<NotificationTypeName> get likeNotificationTypes => List.unmodifiable({
    ...userMenuLikeNotificationTypes,
    for (final type in notificationTypes)
      if (type.coreMenuSection == CoreNotificationMenuSection.likes)
        NotificationTypeName(type.wireType.wireName),
  });

  List<({String owner, UserPreferenceCodec codec})> get _preferences => [
    for (final plugin in plugins.whereType<UserPreferencesPlugin>())
      for (final codec in _preferenceCodecsFor(plugin))
        (owner: _ownerOf(plugin), codec: codec),
  ];

  List<({String owner, GlobalSearchContribution contribution})> get _search => [
    for (final plugin in plugins.whereType<GlobalSearchPlugin>())
      for (final contribution in _searchContributionsFor(plugin))
        (owner: _ownerOf(plugin), contribution: contribution),
  ];

  List<GlobalSearchContribution> get searchContributions =>
      List.unmodifiable([for (final entry in _search) entry.contribution]);

  @override
  Set<String> get userPreferenceFields => Set.unmodifiable({
    for (final entry in _preferences) ...entry.codec.fields,
  });

  @override
  Map<String, UserPreferenceValues> readUserPreferences(
    Map<String, dynamic> json,
    UserPreferences fallback,
  ) => Map.unmodifiable({
    for (final entry in _preferences)
      entry.codec.section.id: entry.codec.decode(
        json,
        fallback.pluginValues[entry.codec.section.id],
      ),
  });

  void _validateRecordOwners() {
    final searchOwners = <String>{};
    final searchScopes = <GlobalSearchScope>{...GlobalSearchScope.values};
    final searchFilters = <String>{for (final f in globalSearchFilters) f.id};
    for (final entry in _search) {
      final contribution = entry.contribution;
      final owner = entry.owner;
      if (contribution.owner != owner ||
          !searchOwners.add(contribution.owner)) {
        throw ArgumentError('Invalid search contributor ${contribution.owner}');
      }
      for (final scope in contribution.scopes) {
        if (scope.owner != owner ||
            scope.isCore ||
            scope.name.trim().isEmpty ||
            scope.label.trim().isEmpty ||
            !searchScopes.add(scope)) {
          throw ArgumentError('Invalid search scope ${scope.name}');
        }
      }
      for (final filter in contribution.filters) {
        if (filter.id.trim().isEmpty ||
            (filter.scope.isCore &&
                !GlobalSearchScope.values.contains(filter.scope)) ||
            (!filter.scope.isCore &&
                !contribution.scopes.contains(filter.scope)) ||
            !searchFilters.add(filter.id)) {
          throw ArgumentError('Invalid search filter ${filter.id}');
        }
      }
    }
    final preferenceSections = <PreferenceSection>{};
    final preferenceFields = <String>{...UserPreferences.coreWireFields};
    for (final entry in _preferences) {
      final codec = entry.codec;
      final owner = entry.owner;
      if (codec.section.owner != owner ||
          codec.section.owner == 'core' ||
          codec.section.name.trim().isEmpty ||
          !preferenceSections.add(codec.section)) {
        throw ArgumentError(
          'Invalid or duplicate preference section ${codec.section.id} for $owner',
        );
      }
      for (final field in codec.fields) {
        if (field.trim().isEmpty || !preferenceFields.add(field)) {
          throw ArgumentError('Invalid or duplicate preference field $field');
        }
      }
    }

    final owners = <PluginDataKey<Object>, String>{};
    for (final plugin in plugins) {
      if (plugin is PluginRecord<Object>) {
        final capability = plugin as PluginRecord<Object>;
        _claimRecordOwner(owners, _recordKeyFor(capability), _ownerOf(plugin));
      }
      if (plugin is GroupRecordPlugin<Object>) {
        final capability = plugin as GroupRecordPlugin<Object>;
        _claimRecordOwner(
          owners,
          _groupRecordKeyFor(capability),
          _ownerOf(plugin),
        );
      }
      if (plugin is SiteSettingsPlugin<Object>) {
        final capability = plugin as SiteSettingsPlugin<Object>;
        _validateCodecOwner(
          _siteSettingsCodecFor(capability),
          _ownerOf(plugin),
        );
        _claimRecordOwner(
          owners,
          _siteSettingsCodecFor(capability).key,
          _ownerOf(plugin),
        );
      }
      if (plugin is CurrentUserPlugin<Object>) {
        final capability = plugin as CurrentUserPlugin<Object>;
        _validateCodecOwner(_currentUserCodecFor(capability), _ownerOf(plugin));
        _claimRecordOwner(
          owners,
          _currentUserCodecFor(capability).key,
          _ownerOf(plugin),
        );
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
      final pluginName = _ownerOf(plugin);
      for (final codec in _recommendationCodecsFor(plugin)) {
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
      final pluginName = _ownerOf(plugin);
      final catalog = _iconCatalogFor(plugin);
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
    final declaredTypes = <NotificationTypeName, NotificationWireType>{
      for (final plugin in plugins.whereType<NotificationTypePlugin>())
        for (final type in _notificationTypesFor(plugin))
          NotificationTypeName(type.wireType.wireName): type.wireType,
    };
    final typeOwners = <NotificationTypeName, String>{
      for (final plugin in plugins.whereType<NotificationTypePlugin>())
        for (final type in _notificationTypesFor(plugin))
          NotificationTypeName(type.wireType.wireName): _ownerOf(plugin),
    };
    final declarations = _notificationFeedDeclarations;
    for (final declaration in declarations) {
      final pluginName = declaration.owner;
      final source = declaration.source;
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
      final dismissal = source.dismissal;
      if (dismissal != null &&
          (dismissal.buttonLabel.trim().isEmpty ||
              dismissal.buttonTooltip.trim().isEmpty)) {
        throw ArgumentError(
          'Notification feed ${source.id.id} must declare its dismissal '
          'button label and tooltip.',
        );
      }
      if (dismissal != null) {
        final dismissedNames = [
          for (final type in dismissal.notificationTypes)
            NotificationTypeName(type.wireName),
        ];
        final matchesFilter =
            dismissedNames.length == source.filterByTypes.length &&
            dismissedNames.toSet().containsAll(source.filterByTypes) &&
            source.filterByTypes.toSet().containsAll(dismissedNames);
        final matchesDeclarations = dismissal.notificationTypes.every((type) {
          final declared = declaredTypes[NotificationTypeName(type.wireName)];
          return declared?.wireId == type.wireId &&
              declared?.wireName == type.wireName;
        });
        if (!matchesFilter || !matchesDeclarations) {
          throw ArgumentError(
            'Notification feed ${source.id.id} may dismiss only its '
            'declared filter notification types.',
          );
        }
      }
      if (source.filterByTypes.isEmpty ||
          source.filterByTypes.any((type) => typeOwners[type] != pluginName)) {
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
      final pluginName = _ownerOf(plugin);
      for (final definition in _notificationTypesFor(plugin)) {
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
      final pluginName = _ownerOf(plugin);
      for (final counter in _notificationCountersFor(plugin)) {
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
    if (key.owner != owner) {
      throw ArgumentError('Plugin data key ${key.id} is registered by $owner.');
    }
    final previous = owners[key];
    if (previous != null) {
      throw ArgumentError(
        'Plugin data key ${key.id} is claimed by both $previous and $owner.',
      );
    }
    owners[key] = owner;
  }

  @override
  PluginData readGroup(Map<String, dynamic> json, String siteUrl) {
    var values = PluginData.none;
    for (final plugin in plugins.whereType<GroupRecordPlugin<Object>>()) {
      final value = plugin.readGroup(json, siteUrl);
      if (value != null) {
        values = values.withValueFor(_groupRecordKeyFor(plugin), value);
      }
    }
    return values;
  }

  @override
  PluginData readPost(Map<String, dynamic> json, String siteUrl) {
    var values = PluginData.none;
    for (final plugin in plugins.whereType<PostRecordPlugin<Object>>()) {
      final value = plugin.readPost(json, siteUrl);
      if (value != null) {
        values = values.withValueFor(_recordKeyFor(plugin), value);
      }
    }
    return values;
  }

  @override
  PluginData readTopic(Map<String, dynamic> json, String siteUrl) {
    var values = PluginData.none;
    for (final plugin in plugins.whereType<TopicRecordPlugin<Object>>()) {
      final value = plugin.readTopic(json, siteUrl);
      if (value != null) {
        values = values.withValueFor(_recordKeyFor(plugin), value);
      }
    }
    return values;
  }

  @override
  PluginData readUserCard(Map<String, dynamic> json, String siteUrl) {
    var values = PluginData.none;
    for (final plugin in plugins.whereType<UserCardRecordPlugin<Object>>()) {
      final value = plugin.readUserCard(json, siteUrl);
      if (value != null) {
        values = values.withValueFor(_recordKeyFor(plugin), value);
      }
    }
    return values;
  }

  @override
  PluginData readCurrentUser(Map<String, dynamic> json, String siteUrl) {
    var values = PluginData.none;
    for (final plugin in plugins.whereType<CurrentUserPlugin<Object>>()) {
      final value = plugin.readCurrentUser(json, siteUrl);
      if (value != null) {
        values = values.withValueFor(_currentUserCodecFor(plugin).key, value);
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
        values = values.withValueFor(_siteSettingsCodecFor(plugin).key, value);
      }
    }
    return values;
  }

  @override
  PluginData readStoredCurrentUser(Map<String, dynamic> json) => _readStored(
    json,
    plugins.whereType<CurrentUserPlugin<Object>>().map(
      (plugin) => _currentUserCodecFor(plugin),
    ),
  );

  @override
  PluginData readStoredSiteSettings(Map<String, dynamic> json) => _readStored(
    json,
    plugins.whereType<SiteSettingsPlugin<Object>>().map(
      (plugin) => _siteSettingsCodecFor(plugin),
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
      (plugin) => _currentUserCodecFor(plugin),
    ),
  );

  @override
  Map<String, Object?> writeStoredSiteSettings(PluginData data) => _writeStored(
    data,
    plugins.whereType<SiteSettingsPlugin<Object>>().map(
      (plugin) => _siteSettingsCodecFor(plugin),
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
      if (_ownerOf(plugin) == pluginId && plugin is PluginSiteFeature) {
        return (plugin as PluginSiteFeature).siteFeatureEnabled(siteSettings);
      }
    }
    return false;
  }

  bool currentUserFeatureEnabled(String pluginId, PluginData currentUser) {
    for (final plugin in plugins) {
      if (_ownerOf(plugin) == pluginId && plugin is PluginCurrentUserFeature) {
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
        held.get(_recordKeyFor(plugin)),
        merged.get(_recordKeyFor(plugin)),
      );
      merged = merged.withValueFor(_recordKeyFor(plugin), value);
    }
    return merged;
  }

  Widget transformPostBody(
    BuildContext context,
    String siteUrl,
    Post post, {
    PluginContainingTopic? topic,
    required PluginPostBodyBuilder builder,
  }) {
    final transforms = plugins.whereType<PostBodyTransformPlugin>().toList();
    Widget next(int index, BuildContext context, String cooked) {
      if (index == transforms.length) return builder(context, cooked);
      final plugin = transforms[index];
      final result = plugin.transformPostBody(
        PluginPostBodyContext(
          buildContext: _uiContext(context, plugin),
          siteUrl: siteUrl,
          post: post,
          topic: topic,
        ),
        cooked,
        (innerContext, displayedCooked) =>
            next(index + 1, innerContext, displayedCooked),
      );
      return result == null
          ? next(index + 1, context, cooked)
          : _owned(plugin, result);
    }

    return next(0, context, post.cooked);
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

  /// The post records [postBodyElement] can draw, in registry order. A body
  /// plugin is handed the whole post but reads only the records its plugin
  /// owns, so a record owned by any other plugin, such as a reaction, never
  /// changes what a post's body shows.
  List<Object?> postBodyRecords(PluginData records) {
    final owners = {
      for (final plugin in plugins)
        if (plugin is PostBodyPlugin) _ownerOf(plugin),
    };
    if (owners.isEmpty) return const [];
    return [
      for (final plugin in plugins.whereType<PostRecordPlugin<Object>>())
        if (owners.contains(_recordKeyFor(plugin).owner))
          records.get(_recordKeyFor(plugin)),
    ];
  }

  Widget? cookedElement(String? siteUrl, dom.Element element) {
    for (final plugin in plugins.whereType<CookedElementPlugin>()) {
      final widget = plugin.cookedElement(siteUrl, element);
      if (widget != null) return _owned(plugin, widget);
    }
    return null;
  }

  HashtagPresentation? pluginHashtagPresentation(
    HashtagPresentationRequest request,
  ) {
    final installed = _installed;
    if (installed != null) {
      final entry = installed.hashtagsByWireType[request.type];
      return entry == null
          ? null
          : _presentHashtag(() => entry.owner, entry.kind, request);
    }
    for (final plugin in plugins.whereType<HashtagKindPlugin>()) {
      for (final kind in _hashtagKindsFor(plugin)) {
        if (kind.wireType == request.type) {
          return _presentHashtag(() => _ownerOf(plugin), kind, request);
        }
      }
    }
    return null;
  }

  static HashtagPresentation? _presentHashtag(
    String Function() readOwner,
    PluginHashtagKind kind,
    HashtagPresentationRequest request,
  ) {
    try {
      final presentation = kind.present(request);
      return presentation.type == request.type ? presentation : null;
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'hashtag.kind.present',
        source: readOwner(),
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
      return null;
    }
  }

  List<String> get pluginHashtagWireTypes => List.unmodifiable([
    for (final plugin in plugins.whereType<HashtagKindPlugin>())
      for (final kind in _hashtagKindsFor(plugin)) kind.wireType,
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

  List<Widget> postHeaders(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) => [
    for (final plugin in plugins.whereType<PostHeaderPlugin>())
      ..._ownedAll(
        plugin,
        plugin.postHeaders(_uiContext(context, plugin), siteUrl, topic, post),
      ),
  ];

  Color? postCardTone(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) {
    for (final plugin in plugins.whereType<PostCardTonePlugin>()) {
      final tone = plugin.postCardTone(
        _uiContext(context, plugin),
        siteUrl,
        topic,
        post,
      );
      if (tone != null) return tone;
    }
    return null;
  }

  PluginSmallAction? smallAction(Post post) {
    for (final plugin in plugins.whereType<PostSmallActionPlugin>()) {
      final contribution = plugin.smallAction(post);
      if (contribution != null) return contribution;
    }
    return null;
  }

  bool isSmallAction(Post post) => smallAction(post) != null;

  Widget decorateTopicListTitle(
    BuildContext context,
    String siteUrl,
    Topic topic,
    Widget title,
  ) {
    var result = title;
    for (final plugin in plugins.whereType<TopicListTitlePlugin>()) {
      final decoration = plugin.decorateTopicListTitle(
        _uiContext(context, plugin),
        siteUrl,
        topic,
        result,
      );
      if (decoration != null) result = _owned(plugin, decoration);
    }
    return result;
  }

  List<Widget> topicListMetadata(
    BuildContext context,
    String siteUrl,
    Topic topic, {
    bool compact = false,
  }) => [
    for (final plugin in plugins.whereType<TopicListMetadataPlugin>())
      if (!compact || plugin is! CompactTopicListMetadataPlugin)
        ..._ownedAll(
          plugin,
          plugin.topicListMetadata(_uiContext(context, plugin), siteUrl, topic),
        ),
  ];

  List<Widget> compactTopicListMetadata(
    BuildContext context,
    String siteUrl,
    Topic topic,
    void Function({String? property}) onOpen,
  ) => [
    for (final plugin in plugins.whereType<CompactTopicListMetadataPlugin>())
      ..._ownedAll(
        plugin,
        plugin.compactTopicListMetadata(
          _uiContext(context, plugin),
          siteUrl,
          topic,
          onOpen,
        ),
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
          header: section.header == null
              ? null
              : (context, showDetails) => _owned(
                  plugin,
                  section.header!(_uiContext(context, plugin), showDetails),
                ),
          compactHeader: section.compactHeader == null
              ? null
              : (context, showDetails) => _owned(
                  plugin,
                  section.compactHeader!(
                    _uiContext(context, plugin),
                    showDetails,
                  ),
                ),
          values: _ownedAll(plugin, section.values),
          layout: section.layout,
          showHeader: section.showHeader,
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

  TopicMapActionContribution topicMapActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final actions = <Widget>[];
    var replacesSummary = false;
    for (final plugin in plugins.whereType<TopicMapActionPlugin>()) {
      final contribution = plugin.topicMapActions(
        _uiContext(context, plugin),
        siteUrl,
        topic,
      );
      actions.addAll(_ownedAll(plugin, contribution.actions));
      replacesSummary |= contribution.replacesSummary;
    }
    if (actions.isEmpty && !replacesSummary) {
      return TopicMapActionContribution.none;
    }
    return TopicMapActionContribution(
      actions: actions,
      replacesSummary: replacesSummary,
    );
  }

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
    Future<String?> Function()? quickReaction;
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
      quickReaction ??= contribution.quickReaction;
      if (contribution.rebuildOn case final listenable?) {
        rebuildListenables.add(listenable);
      }
    }
    if (entries.isEmpty &&
        !replacesLike &&
        rebuildListenables.isEmpty &&
        quickReaction == null) {
      return PostMenuContribution.none;
    }
    return PostMenuContribution(
      entries: entries,
      replacesLike: replacesLike,
      quickReaction: quickReaction,
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

  List<Widget> composerOptions(
    BuildContext context,
    ComposerEditorHost editor,
  ) => [
    for (final plugin in plugins.whereType<ComposerOptionsPlugin>())
      ..._ownedAll(
        plugin,
        plugin.composerOptions(_uiContext(context, plugin), editor),
      ),
  ];

  List<Widget> composerHeader(
    BuildContext context,
    ComposerEditorHost editor,
  ) => [
    for (final plugin in plugins.whereType<ComposerHeaderPlugin>())
      ..._ownedAll(
        plugin,
        plugin.composerHeader(_uiContext(context, plugin), editor),
      ),
  ];

  List<Widget> composerFooter(
    BuildContext context,
    ComposerEditorHost editor,
  ) => [
    for (final plugin in plugins.whereType<ComposerFooterPlugin>())
      ..._ownedAll(
        plugin,
        plugin.composerFooter(_uiContext(context, plugin), editor),
      ),
  ];

  ComposerTargetPolicy? composerTarget(
    ComposerTargetRequest request,
    ComposerTargetContext context,
  ) {
    final candidates = _installed == null
        ? plugins.whereType<ComposerTargetPlugin>()
        : [?_installed.targetsByKind[request.kind]];
    for (final plugin in candidates) {
      if (_targetKindFor(plugin) != request.kind) continue;
      final policy = plugin.createComposerTarget(request, context);
      final pluginName = _ownerOf(plugin);
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

  void registerComposerComponents(
    ComposerSyntaxPolicyContext context,
    ComposerComponentRegistrar registrar,
  ) {
    final registrations = <_OwnedComposerComponentRegistrar>[];
    for (final plugin in plugins.whereType<ComposerComponentPlugin>()) {
      final owned = _OwnedComposerComponentRegistrar(
        pluginName: _ownerOf(plugin),
        kind: _componentKindFor(plugin),
        registrar: registrar,
      );
      plugin.registerComposerComponent(context, owned);
      owned.seal();
      registrations.add(owned);
    }
    for (final registration in registrations) {
      registration.forward();
    }
  }

  ComposerSyntaxPolicy _composerSyntaxPolicy(
    ComposerSyntaxPlugin plugin,
    ComposerSyntaxPolicyContext context,
  ) {
    final policy = plugin.createComposerSyntaxPolicy(context);
    if (policy.kind != _syntaxKindFor(plugin)) {
      throw StateError(
        '${_ownerOf(plugin)} returned syntax policy ${policy.kind} '
        'for ${_syntaxKindFor(plugin)}.',
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
      final pluginName = _ownerOf(plugin);
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
        final linkWhenActive = section.linkWhenActive;
        if (linkWhenActive != null &&
            (!_isRelativeForumPath(linkWhenActive) ||
                linkWhenActive.contains('\\'))) {
          throw StateError(
            'User-menu section ${section.id.id} active link must be a '
            'relative forum path.',
          );
        }
        final owner = PluginId(pluginName);
        sections.add(
          PluginUserMenuSection(
            id: section.id,
            icon: section.icon,
            label: section.label,
            badge: section.badge,
            linkWhenActive: linkWhenActive,
            notificationTypes: List.unmodifiable(section.notificationTypes),
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

  List<OwnedSidebarPanel> sidebarPanels(BuildContext context) {
    final groups = <String, List<OwnedSidebarPanel>>{};
    for (final plugin in plugins.whereType<SidebarPanelPlugin>()) {
      final panel = plugin.sidebarPanel(_uiContext(context, plugin));
      if (panel == null) continue;
      final owner = _owner(plugin);
      (groups[panel.groupId ?? owner.value] ??= []).add(
        OwnedSidebarPanel(owner: owner, panel: panel),
      );
    }
    return [
      for (final entry in groups.entries)
        _sidebarPanelGroup(entry.key, entry.value),
    ];
  }

  OwnedSidebarPanel _sidebarPanelGroup(
    String groupId,
    List<OwnedSidebarPanel> contributions,
  ) {
    final primary =
        contributions
            .where((entry) => entry.owner.value == groupId)
            .firstOrNull ??
        contributions.first;
    final panel = primary.panel;
    return OwnedSidebarPanel(
      owner: PluginId(groupId),
      sectionOwners: [for (final entry in contributions) entry.owner],
      panel: SidebarPanelContribution(
        label: panel.label,
        icon: panel.icon,
        active: contributions.any((entry) => entry.panel.active),
        separateWhenActive: panel.separateWhenActive,
        includeSectionsWhenInactive: panel.includeSectionsWhenInactive,
        showSwitch: panel.showSwitch,
        onOpen: panel.onOpen,
        onClose: panel.onClose,
        badge: panel.badge,
        mobileBadge: panel.mobileBadge,
        selectedDestinationId: panel.selectedDestinationId,
        // Auxiliary sections must not replace the primary owner's mobile root.
        mobileBuilder: panel.mobileBuilder,
        mobileAction: panel.mobileAction,
        footerBuilder: panel.footerBuilder,
      ),
    );
  }

  List<Listenable> sidebarPanelListenables(BuildContext context) => [
    for (final plugin in plugins.whereType<SidebarPanelListenablePlugin>())
      ?plugin.sidebarPanelListenable(_uiContext(context, plugin)),
  ];

  List<PluginUserPreferenceSection> userPreferenceSections(
    BuildContext context,
    PluginUserPreferenceContext preferences,
  ) {
    final sections = <PluginUserPreferenceSection>[];
    final owners = <PreferenceSection, String>{};
    for (final plugin in plugins.whereType<UserPreferenceSectionPlugin>()) {
      final section = plugin.userPreferenceSection(
        _uiContext(context, plugin),
        PluginUserPreferenceContext(
          siteUrl: preferences.siteUrl,
          preferences: preferences.preferences,
          siteSettings: preferences.siteSettings,
          currentUserData: preferences.currentUserData,
          currentUserIsAdmin: preferences.currentUserIsAdmin,
          editable: preferences.editable,
          onEdit: (section, change) {
            if (section.owner != _ownerOf(plugin) || section.owner == 'core') {
              throw StateError(
                'Cannot edit foreign preference section ${section.id}',
              );
            }
            final codec = _preferences
                .where((entry) => entry.codec.section == section)
                .firstOrNull
                ?.codec;
            if (codec == null) {
              throw StateError('Unregistered preference section ${section.id}');
            }
            preferences.onEdit(section, (current) {
              final next = change(current);
              final value = next.pluginValues[section.id];
              if (value != null) _validatePreferenceValue(codec, value);
              return current.withSectionFrom(section, next);
            });
          },
        ),
      );
      if (section == null) continue;
      final owner = _ownerOf(plugin);
      if (section.section.owner != owner || section.section.owner == 'core') {
        throw StateError(
          '$owner cannot replace core preference section '
          '${section.section.name}.',
        );
      }
      if (!_preferences.any(
        (entry) => entry.codec.section == section.section,
      )) {
        throw StateError(
          'Unregistered preference section ${section.section.id}',
        );
      }
      if (section.title.trim().isEmpty) {
        throw StateError('$owner returned an empty preference section title.');
      }
      final previous = owners[section.section];
      if (previous != null) {
        throw StateError(
          'Preference section ${section.section.name} is provided by both '
          '$previous and $owner.',
        );
      }
      owners[section.section] = owner;
      sections.add(
        PluginUserPreferenceSection(
          section: section.section,
          title: section.title,
          icon: section.icon,
          content: _owned(plugin, section.content),
        ),
      );
    }
    return List.unmodifiable(sections);
  }

  List<SidebarDestination> communitySidebarDestinations(
    BuildContext context, {
    bool Function(PluginId owner)? includeOwner,
  }) => [
    for (final plugin in plugins.whereType<CommunitySidebarPlugin>())
      if (includeOwner?.call(_owner(plugin)) ?? true)
        for (final destination in plugin.communitySidebarDestinations(
          _uiContext(context, plugin),
        ))
          _ownedDestination(plugin, destination),
  ];

  List<Listenable> communitySidebarListenables(
    BuildContext context, {
    bool Function(PluginId owner)? includeOwner,
  }) => [
    for (final plugin in plugins.whereType<CommunitySidebarPlugin>())
      if (includeOwner?.call(_owner(plugin)) ?? true)
        ?plugin.communitySidebarListenable(_uiContext(context, plugin)),
  ];

  List<StartPageSection> startPageSections(BuildContext context) => [
    for (final plugin in plugins.whereType<StartPagePlugin>())
      for (final section in plugin.startPageSections(
        _uiContext(context, plugin),
      ))
        StartPageSection(
          destination: _ownedDestination(plugin, section.destination),
          entries: [
            for (final entry in section.entries)
              _ownedDestination(plugin, entry),
          ],
        ),
  ];

  List<Listenable> startPageListenables(BuildContext context) => [
    for (final plugin in plugins.whereType<StartPagePlugin>())
      ?plugin.startPageListenable(_uiContext(context, plugin)),
  ];

  List<SidebarSection> sidebarSections(
    BuildContext context, {
    bool Function(PluginId owner)? includeOwner,
  }) => [
    for (final plugin in plugins.whereType<SidebarPlugin>())
      if (includeOwner?.call(_owner(plugin)) ?? true)
        ...plugin
            .sidebarSections(_uiContext(context, plugin))
            .map((section) => _ownedSection(plugin, section)),
  ];

  List<Listenable> sidebarListenables(
    BuildContext context, {
    bool Function(PluginId owner)? includeOwner,
  }) {
    final listenables = <Listenable>[];
    for (final plugin in plugins.whereType<SidebarPlugin>()) {
      if (!(includeOwner?.call(_owner(plugin)) ?? true)) continue;
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
    if (tab.currentContent.destination is! ExtensionDestination) return null;
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
    if (route.destination is! ExtensionDestination) return null;
    for (final plugin in plugins.whereType<ContentPlugin>()) {
      final content = plugin.content(_uiContext(context, plugin), route);
      if (content != null) return _owned(plugin, content);
    }
    return null;
  }

  GlobalSearchContext? contentSearchContext(BuildContext context) {
    for (final plugin in plugins.whereType<ContentSearchPlugin>()) {
      final pluginContext = _uiContext(context, plugin);
      final searchContext = plugin.contentSearchContext(pluginContext);
      if (searchContext != null) return searchContext;
    }
    return null;
  }

  bool ownsContentChrome(BuildContext context, ContentRoute route) =>
      route.destination is ExtensionDestination &&
      plugins.whereType<ContentChromePlugin>().any(
        (plugin) =>
            plugin.ownsContentChrome(_uiContext(context, plugin), route),
      );

  bool usesMobilePageSheet(BuildContext context, ContentRoute route) =>
      route.destination is ExtensionDestination &&
      plugins.whereType<ContentMobilePageSheetPlugin>().any(
        (plugin) =>
            plugin.usesMobilePageSheet(_uiContext(context, plugin), route),
      );

  bool keepsMobileDockVisible(BuildContext context, ContentRoute route) =>
      route.destination is ExtensionDestination &&
      plugins.whereType<ContentMobileDockPlugin>().any(
        (plugin) =>
            plugin.keepsMobileDockVisible(_uiContext(context, plugin), route),
      );

  bool ownsContentPageTitle(BuildContext context, ContentRoute route) =>
      route.destination is ExtensionDestination &&
      plugins.whereType<ContentPageTitlePlugin>().any(
        (plugin) =>
            plugin.ownsContentPageTitle(_uiContext(context, plugin), route),
      );

  List<Widget> contentHeaderActions(BuildContext context, ContentRoute route) =>
      [
        if (route.destination is ExtensionDestination)
          for (final plugin in plugins.whereType<ContentHeaderPlugin>())
            ..._ownedAll(
              plugin,
              plugin.contentHeaderActions(_uiContext(context, plugin), route),
            ),
      ];

  Widget? contentHeaderLeading(BuildContext context, ContentRoute route) {
    if (route.destination is! ExtensionDestination) return null;
    for (final plugin in plugins.whereType<ContentHeaderLeadingPlugin>()) {
      final leading = plugin.contentHeaderLeading(
        _uiContext(context, plugin),
        route,
      );
      if (leading != null) return _owned(plugin, leading);
    }
    return null;
  }

  Widget? contentHeaderTitleTrailing(BuildContext context, ContentRoute route) {
    if (route.destination is! ExtensionDestination) return null;
    for (final plugin
        in plugins.whereType<ContentHeaderTitleTrailingPlugin>()) {
      final trailing = plugin.contentHeaderTitleTrailing(
        _uiContext(context, plugin),
        route,
      );
      if (trailing != null) return _owned(plugin, trailing);
    }
    return null;
  }

  VoidCallback? contentHeaderTitleAction(
    BuildContext context,
    ContentRoute route,
  ) {
    if (route.destination is! ExtensionDestination) return null;
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

  HomepagePlugin? homepage(String id) {
    if (_installed != null) return _installed.homepagesById[id];
    return plugins
        .whereType<HomepagePlugin>()
        .where((plugin) => plugin.homepageId == id)
        .firstOrNull;
  }

  List<DiagnosticsPlugin> get diagnosticsPlugins => List.unmodifiable([
    for (final plugin in plugins.whereType<DiagnosticsPlugin>())
      _OwnedDiagnosticsPlugin(
        _owner(plugin),
        plugin,
        _installed?.diagnosticsIds[plugin],
      ),
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
  const _OwnedDiagnosticsPlugin(this.owner, this.delegate, this._diagnosticsId);

  final PluginId owner;
  final DiagnosticsPlugin delegate;

  final String? _diagnosticsId;

  @override
  String get diagnosticsId => _diagnosticsId ?? delegate.diagnosticsId;

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

bool _isRelativeForumPath(String value) {
  if (value.isEmpty ||
      value.trim() != value ||
      !value.startsWith('/') ||
      value.startsWith('//')) {
    return false;
  }
  final uri = Uri.tryParse(value);
  return uri != null && !uri.hasScheme && !uri.hasAuthority;
}

void _validatePreferenceValue(
  UserPreferenceCodec codec,
  UserPreferenceValues value,
) {
  if (value.payload.keys.any((key) => !codec.fields.contains(key))) {
    throw StateError(
      'Preference section ${codec.section.id} returned undeclared fields',
    );
  }
}

final class _InstalledPreferenceCodec implements UserPreferenceCodec {
  _InstalledPreferenceCodec(UserPreferenceCodec source)
    : section = source.section,
      fields = Set.unmodifiable(source.fields),
      _decode = source.decode;
  @override
  final PreferenceSection section;
  @override
  final Set<String> fields;
  final UserPreferenceValues Function(
    Map<String, dynamic>,
    UserPreferenceValues?,
  )
  _decode;
  @override
  UserPreferenceValues decode(
    Map<String, dynamic> json,
    UserPreferenceValues? fallback,
  ) {
    final value = _decode(json, fallback);
    _validatePreferenceValue(this, value);
    return value;
  }
}

Map<P, V> _captureDeclarations<P extends Object, V>(
  List<SitePlugin> plugins,
  V Function(P plugin) read,
) {
  final values = Map<P, V>.identity();
  for (final plugin in plugins.whereType<P>()) {
    values.putIfAbsent(plugin, () => read(plugin));
  }
  return UnmodifiableMapView(values);
}

PluginIconCatalog _freezeIconCatalog(PluginIconCatalog source) =>
    PluginIconCatalog(
      owner: source.owner,
      entries: Map.unmodifiable(source.entries),
    );

final class _InstalledDeclarations {
  _InstalledDeclarations(List<SitePlugin> plugins)
    : owners = _captureDeclarations<SitePlugin, String>(
        plugins,
        (plugin) => plugin.name,
      ),
      recordKeys =
          _captureDeclarations<PluginRecord<Object>, PluginDataKey<Object>>(
            plugins,
            (plugin) => plugin.record,
          ),
      groupRecordKeys =
          _captureDeclarations<
            GroupRecordPlugin<Object>,
            PluginDataKey<Object>
          >(plugins, (plugin) => plugin.groupRecord),
      siteSettingsCodecs =
          _captureDeclarations<
            SiteSettingsPlugin<Object>,
            PluginDataPersistenceCodec<Object>
          >(
            plugins,
            (plugin) => _InstalledPersistenceCodec(plugin.siteSettingsCodec),
          ),
      currentUserCodecs =
          _captureDeclarations<
            CurrentUserPlugin<Object>,
            PluginDataPersistenceCodec<Object>
          >(
            plugins,
            (plugin) => _InstalledPersistenceCodec(plugin.currentUserCodec),
          ),
      targetKinds =
          _captureDeclarations<ComposerTargetPlugin, ComposerTargetKind>(
            plugins,
            (plugin) => plugin.composerTargetKind,
          ),
      syntaxKinds =
          _captureDeclarations<ComposerSyntaxPlugin, ComposerSyntaxKind>(
            plugins,
            (plugin) => plugin.composerSyntaxKind,
          ),
      componentKinds =
          _captureDeclarations<ComposerComponentPlugin, ComposerSyntaxKind>(
            plugins,
            (plugin) => plugin.composerComponentKind,
          ),
      hashtagKinds =
          _captureDeclarations<HashtagKindPlugin, List<PluginHashtagKind>>(
            plugins,
            (plugin) => List.unmodifiable(plugin.hashtagKinds),
          ),
      recommendationCodecs =
          _captureDeclarations<
            TopicRecommendationSourcePlugin,
            List<TopicRecommendationSourceCodec>
          >(
            plugins,
            (plugin) => List.unmodifiable(
              plugin.topicRecommendationSourceCodecs.map(
                _InstalledRecommendationCodec.new,
              ),
            ),
          ),
      iconCatalogs = _captureDeclarations<IconCatalogPlugin, PluginIconCatalog>(
        plugins,
        (plugin) => _freezeIconCatalog(plugin.iconCatalog),
      ),
      notificationTypes =
          _captureDeclarations<
            NotificationTypePlugin,
            List<PluginNotificationType>
          >(plugins, (plugin) => List.unmodifiable(plugin.notificationTypes)),
      notificationFeeds =
          _captureDeclarations<
            NotificationFeedPlugin,
            List<PluginNotificationFeedSource>
          >(
            plugins,
            (plugin) => List.unmodifiable(
              plugin.notificationFeeds.map(_freezeNotificationFeedSource),
            ),
          ),
      notificationCounters =
          _captureDeclarations<
            NotificationCounterPlugin,
            List<PluginNotificationCounter>
          >(
            plugins,
            (plugin) => List.unmodifiable(plugin.notificationCounters),
          ),
      sitePreferenceKeys =
          _captureDeclarations<SitePreferencesPlugin, List<SitePreferenceKey>>(
            plugins,
            (plugin) => List.unmodifiable(plugin.sitePreferenceKeys),
          ),
      homepageIds = _captureDeclarations<HomepagePlugin, String>(
        plugins,
        (plugin) => plugin.homepageId,
      ),
      diagnosticsIds = _captureDeclarations<DiagnosticsPlugin, String>(
        plugins,
        (plugin) => plugin.diagnosticsId,
      ),
      preferenceCodecs =
          _captureDeclarations<
            UserPreferencesPlugin,
            List<UserPreferenceCodec>
          >(
            plugins,
            (plugin) => List.unmodifiable(
              plugin.userPreferenceCodecs.map(_InstalledPreferenceCodec.new),
            ),
          ),
      searchContributions =
          _captureDeclarations<
            GlobalSearchPlugin,
            List<GlobalSearchContribution>
          >(
            plugins,
            (plugin) => List.unmodifiable(
              plugin.searchContributions.map(
                InstalledGlobalSearchContribution.new,
              ),
            ),
          );

  final Map<SitePlugin, String> owners;
  final Map<PluginRecord<Object>, PluginDataKey<Object>> recordKeys;
  final Map<GroupRecordPlugin<Object>, PluginDataKey<Object>> groupRecordKeys;
  final Map<SiteSettingsPlugin<Object>, PluginDataPersistenceCodec<Object>>
  siteSettingsCodecs;
  final Map<CurrentUserPlugin<Object>, PluginDataPersistenceCodec<Object>>
  currentUserCodecs;
  final Map<ComposerTargetPlugin, ComposerTargetKind> targetKinds;
  final Map<ComposerSyntaxPlugin, ComposerSyntaxKind> syntaxKinds;
  final Map<ComposerComponentPlugin, ComposerSyntaxKind> componentKinds;
  final Map<HashtagKindPlugin, List<PluginHashtagKind>> hashtagKinds;
  final Map<
    TopicRecommendationSourcePlugin,
    List<TopicRecommendationSourceCodec>
  >
  recommendationCodecs;
  final Map<IconCatalogPlugin, PluginIconCatalog> iconCatalogs;
  final Map<NotificationTypePlugin, List<PluginNotificationType>>
  notificationTypes;
  final Map<NotificationFeedPlugin, List<PluginNotificationFeedSource>>
  notificationFeeds;
  final Map<NotificationCounterPlugin, List<PluginNotificationCounter>>
  notificationCounters;
  final Map<SitePreferencesPlugin, List<SitePreferenceKey>> sitePreferenceKeys;
  final Map<HomepagePlugin, String> homepageIds;
  final Map<DiagnosticsPlugin, String> diagnosticsIds;
  final Map<UserPreferencesPlugin, List<UserPreferenceCodec>> preferenceCodecs;
  final Map<GlobalSearchPlugin, List<GlobalSearchContribution>>
  searchContributions;

  late final Map<String, HomepagePlugin> homepagesById = _indexHomepages();

  Map<String, HomepagePlugin> _indexHomepages() {
    final byId = <String, HomepagePlugin>{};
    for (final entry in homepageIds.entries) {
      byId.putIfAbsent(entry.value, () => entry.key);
    }
    return Map.unmodifiable(byId);
  }

  late final Map<NotificationTypeId, PluginNotificationType> typesById =
      Map.unmodifiable({
        for (final types in notificationTypes.values)
          for (final type in types)
            NotificationTypeId(type.wireType.wireId): type,
      });
  late final Map<PluginNotificationFeedId, PluginNotificationFeedSource>
  feedsById = Map.unmodifiable({
    for (final sources in notificationFeeds.values)
      for (final source in sources) source.id: source,
  });
  late final Map<PluginNotificationCounterId, PluginNotificationCounter>
  countersById = Map.unmodifiable({
    for (final counters in notificationCounters.values)
      for (final counter in counters) counter.id: counter,
  });
  late final Map<String, DIconData> iconsByName = Map.unmodifiable({
    for (final catalog in iconCatalogs.values) ...catalog.entries,
  });
  late final Map<String, TopicRecommendationSourceId>
  recommendationIdsByLegacyId = Map.unmodifiable({
    for (final codecs in recommendationCodecs.values)
      for (final codec in codecs)
        for (final alias in codec.legacyStoredIds) alias: codec.definition.id,
  });
  late final Map<ComposerTargetKind, ComposerTargetPlugin> targetsByKind =
      Map.unmodifiable({
        for (final entry in targetKinds.entries) entry.value: entry.key,
      });
  late final Map<String, ({String owner, PluginHashtagKind kind})>
  hashtagsByWireType = Map.unmodifiable({
    for (final entry in hashtagKinds.entries)
      for (final kind in entry.value)
        kind.wireType: (owner: owners[entry.key as SitePlugin]!, kind: kind),
  });
}

final class _InstalledRecommendationCodec
    extends TopicRecommendationSourceCodec {
  _InstalledRecommendationCodec(TopicRecommendationSourceCodec source)
    : definition = source.definition,
      legacyStoredIds = Set.unmodifiable(source.legacyStoredIds),
      _decode = source.decodeTopicRows;

  @override
  final TopicRecommendationSourceDefinition definition;
  @override
  final Set<String> legacyStoredIds;
  final List<Map<String, dynamic>>? Function(Map<String, dynamic>) _decode;

  @override
  List<Map<String, dynamic>>? decodeTopicRows(Map<String, dynamic> json) =>
      _decode(json);
}

final class _InstalledPersistenceCodec
    extends PluginDataPersistenceCodec<Object> {
  _InstalledPersistenceCodec(this._source) : key = _source.key;

  final PluginDataPersistenceCodec<Object> _source;
  @override
  final PluginDataKey<Object> key;

  @override
  Object? decode(Object? value) => _source.decode(value);
  @override
  Object? encode(Object value) => _source.encode(value);
  @override
  Object? decodeLegacy(Map<String, dynamic> json) => _source.decodeLegacy(json);
  @override
  Object? decodeStored({
    required Object? namespacedValue,
    required bool hasNamespacedValue,
    required Map<String, dynamic> record,
  }) => _source.decodeStored(
    namespacedValue: namespacedValue,
    hasNamespacedValue: hasNamespacedValue,
    record: record,
  );
}
