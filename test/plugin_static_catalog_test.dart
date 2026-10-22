import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _record = PluginDataKey<String>(owner: 'catalog', name: 'record');
const _group = PluginDataKey<String>(owner: 'catalog', name: 'group');
const _settings = PluginDataKey<String>(owner: 'catalog', name: 'settings');
const _user = PluginDataKey<String>(owner: 'catalog', name: 'user');
const _target = ComposerTargetKind(owner: PluginId('composer'), name: 'target');
const _syntax = ComposerSyntaxKind(owner: PluginId('composer'), name: 'syntax');
const _component = ComposerSyntaxKind(
  owner: PluginId('composer'),
  name: 'component',
);
const _syntaxContext = ComposerSyntaxPolicyContext(
  siteUrl: _site,
  isPluginTarget: false,
  isEdit: false,
  initialState: ComposerPluginState(),
  readState: _emptyState,
);
ComposerPluginState _emptyState() => const ComposerPluginState();

void main() {
  test(
    'record identities stay installed while read and merge hooks stay live',
    () {
      final plugin = _MutableDeclarations();
      final registry = PluginRegistry.validated([plugin]);
      plugin.recordKey = const PluginDataKey(owner: 'foreign', name: 'changed');
      plugin.groupKey = plugin.recordKey;
      plugin.live = 'latest';
      plugin.owner = 'changed';

      expect(registry.readPost({}, _site).get(_record), 'latest');
      expect(registry.readTopic({}, _site).get(_record), 'latest');
      expect(registry.readUserCard({}, _site).get(_record), 'latest');
      expect(registry.readGroup({}, _site).get(_group), 'latest');
      expect(registry.readCurrentUser({}, _site).get(_user), 'latest');
      expect(registry.readSiteSettings({}, _site).get(_settings), 'latest');
      expect(
        registry
            .mergeAfterPostEdit(
              held: PluginData.none.withValueFor(_record, 'held'),
              incoming: PluginData.none.withValueFor(_record, 'incoming'),
            )
            .get(_record),
        'latest:held:incoming',
      );
      expect(
        registry.postBodyRecords(PluginData.none.withValueFor(_record, 'body')),
        ['body'],
      );
      expect(registry.siteFeatureEnabled('catalog', PluginData.none), isTrue);
      expect(
        registry.currentUserFeatureEnabled('catalog', PluginData.none),
        isTrue,
      );
      plugin.live = '';
      expect(registry.siteFeatureEnabled('catalog', PluginData.none), isFalse);
      expect(plugin.reads, _expectedReads);
    },
  );

  test('persistence freezes keys and retains custom stored decoding', () {
    final plugin = _MutableDeclarations();
    final registry = PluginRegistry.validated([plugin]);
    plugin.settingsCodec.storedKey = const PluginDataKey(
      owner: 'foreign',
      name: 'settings',
    );
    plugin.userCodec.storedKey = const PluginDataKey(
      owner: 'foreign',
      name: 'user',
    );
    plugin.settingsCodec.live = 'updated';
    plugin.userCodec.live = 'updated';
    final stored = <String, dynamic>{
      'plugins': {
        _settings.id: 'settings',
        _user.id: 'user',
        'unknown/data': {'opaque': 1},
      },
    };
    final settings = registry.readStoredSiteSettings(stored);
    final user = registry.readStoredCurrentUser(stored);
    expect(settings.get(_settings), 'updated:custom:settings');
    expect(user.get(_user), 'updated:custom:user');
    expect(registry.writeStoredSiteSettings(settings), {
      _user.id: 'user',
      'unknown/data': {'opaque': 1},
      _settings.id: 'updated:updated:custom:settings',
    });
    expect(
      registry.writeStoredCurrentUser(user)[_user.id],
      'updated:updated:custom:user',
    );
    expect(plugin.settingsCodec.keyReads, 1);
    expect(plugin.userCodec.keyReads, 1);
    expect(plugin.reads, _expectedReads);
  });

  test('nested icon and recommendation metadata are immutable snapshots', () {
    final plugin = _MutableDeclarations();
    final registry = PluginRegistry.validated([plugin]);
    plugin.icons.clear();
    plugin.recommendations.clear();
    plugin.recommendation.aliases.clear();
    plugin.recommendation.source = const TopicRecommendationSourceDefinition(
      id: TopicRecommendationSourceId('foreign/changed'),
      label: 'Changed',
    );
    plugin.recommendation.live = 12;

    expect(registry.findIconNamed('catalog-icon'), DIcons.link);
    expect(registry.findIconNamed('missing-icon'), isNull);
    expect(registry.findIconNamed('link'), DIcons.link);
    expect(
      registry.topicRecommendationSources.single.id.value,
      'catalog/nearby',
    );
    expect(registry.topicRecommendationSources.single.label, 'Nearby');
    expect(
      registry.migrateLegacyStoredId('nearby'),
      const TopicRecommendationSourceId('catalog/nearby'),
    );
    expect(registry.migrateLegacyStoredId('unknown'), isNull);
    expect(registry.readTopicRecommendationSources({}), isEmpty);
    final payload = registry.readTopicRecommendationSources({
      'rows': true,
    }).single;
    expect(payload.definition.id.value, 'catalog/nearby');
    expect(payload.topicRows, [
      {'id': 12},
    ]);
    expect(
      () => registry.iconCatalogs.single.entries.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => registry.topicRecommendationSources.clear(),
      throwsUnsupportedError,
    );
    expect(plugin.recommendation.definitionReads, 1);
    expect(plugin.recommendation.aliasReads, 1);
    expect(plugin.reads, _expectedReads);
  });

  test('preference key identity survives mutation', () {
    final plugin = _MutableDeclarations();
    final key = plugin.preferences.single;
    final registry = PluginRegistry.validated([plugin]);

    plugin.preferences.clear();

    expect(registry.sitePreferenceKeys.single, same(key));
    expect(() => registry.sitePreferenceKeys.clear(), throwsUnsupportedError);
    expect(plugin.reads, _expectedReads);
  });

  test(
    'homepages freeze identities, retain first-owner order and call live availability',
    () {
      final first = _MutableHomepage('first');
      final second = _MutableHomepage('second');
      final registry = PluginRegistry.validated([first, second]);
      first.id = 'changed';
      second.id = 'changed';
      expect(registry.homepage('shared'), same(first));
      expect(registry.homepage('changed'), isNull);
      expect(registry.homepage('missing'), isNull);
      final config = SiteConfig.fromJson(const {});
      expect(registry.homepage('shared')!.homepage(config, null), isNull);
      first.available = true;
      expect(
        registry.homepage('shared')!.homepage(config, null)!.isNewTab,
        isTrue,
      );
      expect(first.idReads, 1);
      expect(second.idReads, 1);
    },
  );

  test('equal capability objects retain distinct installed declarations', () {
    const first = _EqualHashtag('first');
    const second = _EqualHashtag('second');
    expect(first, second);
    final registry = PluginRegistry.validated(const [first, second]);
    expect(registry.pluginHashtagWireTypes, ['first', 'second']);
  });

  test('record and group declarations reject foreign ownership', () {
    for (final group in [false, true]) {
      final plugin = _MutableDeclarations();
      const foreign = PluginDataKey<String>(owner: 'foreign', name: 'value');
      if (group) {
        plugin.groupKey = foreign;
      } else {
        plugin.recordKey = foreign;
      }
      expect(() => PluginRegistry.validated([plugin]), throwsArgumentError);
    }
  });

  test('composer dispatch and result checks use captured kinds', () {
    final plugin = _MutableComposer();
    final registry = PluginRegistry.validated([plugin]);
    plugin.target = const ComposerTargetKind(
      owner: PluginId('foreign'),
      name: 'changed',
    );
    plugin.syntax = const ComposerSyntaxKind(
      owner: PluginId('foreign'),
      name: 'changed',
    );
    plugin.component = plugin.syntax;
    plugin.draft = 'latest-draft';
    expect(
      registry
          .composerTarget(
            const ComposerTargetRequest(
              kind: _target,
              siteUrl: _site,
              title: '',
            ),
            const ComposerTargetContext(
              siteSettings: PluginData.none,
              currentUser: PluginData.none,
            ),
          )!
          .draftKey,
      'latest-draft',
    );
    expect(
      registry.composerSyntaxPolicies(_syntaxContext).single.kind,
      _syntax,
    );
    final registrar = _Registrar();
    registry.registerComposerComponents(_syntaxContext, registrar);
    expect(registrar.kinds, [_component]);
    plugin.returnWrongKinds = true;
    expect(
      () => registry.composerSyntaxPolicies(_syntaxContext),
      throwsStateError,
    );
    expect(
      () => registry.registerComposerComponents(_syntaxContext, registrar),
      throwsStateError,
    );
    expect(registrar.kinds, [_component]);
    expect(plugin.reads, {'target': 1, 'syntax': 1, 'component': 1});
  });
}

const _expectedReads = {
  'name': 1,
  'record': 1,
  'group': 1,
  'settings': 1,
  'user': 1,
  'icons': 1,
  'recommendations': 1,
  'preferences': 1,
};

final class _MutableDeclarations
    implements
        SitePlugin,
        PostRecordPlugin<String>,
        TopicRecordPlugin<String>,
        UserCardRecordPlugin<String>,
        GroupRecordPlugin<String>,
        SiteSettingsPlugin<String>,
        CurrentUserPlugin<String>,
        PostBodyPlugin,
        IconCatalogPlugin,
        TopicRecommendationSourcePlugin,
        SitePreferencesPlugin,
        PluginSiteFeature,
        PluginCurrentUserFeature {
  _MutableDeclarations() {
    recommendations.add(recommendation);
  }
  String owner = 'catalog';
  String live = '';
  PluginDataKey<String> recordKey = _record;
  PluginDataKey<String> groupKey = _group;
  final settingsCodec = _MutablePersistenceCodec(_settings);
  final userCodec = _MutablePersistenceCodec(_user);
  final recommendation = _MutableRecommendationCodec();
  final icons = <String, DIconData>{'catalog-icon': DIcons.link};
  final recommendations = <TopicRecommendationSourceCodec>[];
  final preferences = <SitePreferenceKey>[
    const SitePreferenceKey('catalog.preference'),
  ];

  final reads = <String, int>{};
  T _read<T>(String key, T value) {
    reads.update(key, (n) => n + 1, ifAbsent: () => 1);
    return value;
  }

  @override
  String get name => _read('name', owner);
  @override
  PluginDataKey<String> get record => _read('record', recordKey);
  @override
  PluginDataKey<String> get groupRecord => _read('group', groupKey);
  @override
  PluginDataPersistenceCodec<String> get siteSettingsCodec =>
      _read('settings', settingsCodec);
  @override
  PluginDataPersistenceCodec<String> get currentUserCodec =>
      _read('user', userCodec);
  @override
  PluginIconCatalog get iconCatalog =>
      _read('icons', PluginIconCatalog(owner: PluginId(owner), entries: icons));
  @override
  List<TopicRecommendationSourceCodec> get topicRecommendationSourceCodecs =>
      _read('recommendations', recommendations);
  @override
  List<SitePreferenceKey> get sitePreferenceKeys =>
      _read('preferences', preferences);

  @override
  bool siteFeatureEnabled(PluginData data) => live.isNotEmpty;
  @override
  bool currentUserFeatureEnabled(PluginData data) => live.isNotEmpty;
  @override
  String? readPost(Map<String, dynamic> json, String siteUrl) => live;
  @override
  String? readTopic(Map<String, dynamic> json, String siteUrl) => live;
  @override
  String? readUserCard(Map<String, dynamic> json, String siteUrl) => live;
  @override
  String? readGroup(Map<String, dynamic> json, String siteUrl) => live;
  @override
  String? readCurrentUser(Map<String, dynamic> json, String siteUrl) => live;
  @override
  String? readSiteSettings(Map<String, dynamic> json, String siteUrl) => live;
  @override
  String? mergeAfterPostEdit(String? held, String? incoming) =>
      '$live:$held:$incoming';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _MutablePersistenceCodec
    extends PluginDataPersistenceCodec<String> {
  _MutablePersistenceCodec(this.storedKey);
  PluginDataKey<String> storedKey;
  String live = '';
  int keyReads = 0;
  @override
  PluginDataKey<String> get key {
    keyReads++;
    return storedKey;
  }

  @override
  String? decode(Object? value) => '$live:$value';
  @override
  Object? encode(String value) => '$live:$value';
  @override
  String? decodeStored({
    required Object? namespacedValue,
    required bool hasNamespacedValue,
    required Map<String, dynamic> record,
  }) => '$live:custom:$namespacedValue';
}

final class _MutableRecommendationCodec extends TopicRecommendationSourceCodec {
  TopicRecommendationSourceDefinition source =
      const TopicRecommendationSourceDefinition(
        id: TopicRecommendationSourceId('catalog/nearby'),
        label: 'Nearby',
      );
  final aliases = <String>{'nearby'};
  int live = 0;
  int definitionReads = 0;
  int aliasReads = 0;
  @override
  TopicRecommendationSourceDefinition get definition {
    definitionReads++;
    return source;
  }

  @override
  Set<String> get legacyStoredIds {
    aliasReads++;
    return aliases;
  }

  @override
  List<Map<String, dynamic>>? decodeTopicRows(Map<String, dynamic> json) =>
      json.containsKey('rows')
      ? List.unmodifiable([
          {'id': live},
        ])
      : null;
}

final class _MutableComposer
    implements
        SitePlugin,
        ComposerTargetPlugin,
        ComposerSyntaxPlugin,
        ComposerComponentPlugin {
  ComposerTargetKind target = _target;
  ComposerSyntaxKind syntax = _syntax;
  ComposerSyntaxKind component = _component;
  String draft = 'draft';
  bool returnWrongKinds = false;
  final reads = <String, int>{};
  T _read<T>(String key, T value) {
    reads.update(key, (n) => n + 1, ifAbsent: () => 1);
    return value;
  }

  @override
  String get name => 'composer';
  @override
  ComposerTargetKind get composerTargetKind => _read('target', target);
  @override
  ComposerSyntaxKind get composerSyntaxKind => _read('syntax', syntax);
  @override
  ComposerSyntaxKind get composerComponentKind => _read('component', component);
  @override
  ComposerTargetPolicy createComposerTarget(
    ComposerTargetRequest request,
    ComposerTargetContext context,
  ) => ComposerTargetPolicy(
    kind: _target,
    draftKey: draft,
    uploadType: ComposerUploadType.composer,
    uploadDisposition: ComposerUploadDisposition.insertMarkdown,
    uploadsEnabled: false,
    supportsEditing: false,
    validate: (_) => true,
    emojiUsageContext: const EmojiUsageContext(
      owner: PluginId('composer'),
      name: 'emoji',
    ),
  );
  @override
  ComposerSyntaxPolicy createComposerSyntaxPolicy(
    ComposerSyntaxPolicyContext context,
  ) => _Policy(returnWrongKinds ? syntax : _syntax);
  @override
  void registerComposerComponent(
    ComposerSyntaxPolicyContext context,
    ComposerComponentRegistrar registrar,
  ) => registrar.add<String>(
    ComposerComponent<String>.inline(
      kind: returnWrongKinds ? component : _component,
      find: (_) => const [],
      builder: (_, _) => const SizedBox.shrink(),
      semanticLabel: (_, _) => draft,
    ),
  );
}

final class _Policy implements ComposerSyntaxPolicy {
  const _Policy(this.kind);
  @override
  final ComposerSyntaxKind kind;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Registrar implements ComposerComponentRegistrar {
  final kinds = <ComposerSyntaxKind>[];
  @override
  void add<T extends Object>(ComposerComponent<T> component) =>
      kinds.add(component.kind);
}

final class _MutableHomepage implements SitePlugin, HomepagePlugin {
  _MutableHomepage(this.name);
  @override
  final String name;
  String id = 'shared';
  int idReads = 0;
  bool available = false;
  @override
  String get homepageId {
    idReads++;
    return id;
  }

  @override
  ContentRoute? homepage(SiteConfig config, DiscourseUser? user) =>
      available ? ContentRoute.newTab() : null;
}

final class _EqualHashtag implements SitePlugin, HashtagKindPlugin {
  const _EqualHashtag(this.name);
  @override
  final String name;
  @override
  List<PluginHashtagKind> get hashtagKinds => [
    PluginHashtagKind(name, (_) => throw StateError('unused')),
  ];
  @override
  bool operator ==(Object other) => other is _EqualHashtag;
  @override
  int get hashCode => 0;
}
