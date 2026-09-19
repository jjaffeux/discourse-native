import 'dart:convert';
import 'generated_modules.dart';
export 'generated_modules.dart'
    show cookingBundleRevision, cookingEngineRevision;

/// A data-only parser dialect. Null lists retain upstream defaults.
final class CookingProfile {
  const CookingProfile._(
    this.name,
    this.features,
    this.rules,
    this.settings,
    this.forceQuoteLink,
  );
  factory CookingProfile({
    required String name,
    List<String>? features,
    List<String>? rules,
    Map<String, Object?> settings = const {},
    bool forceQuoteLink = false,
  }) {
    if ((features?.length ?? 0) + (rules?.length ?? 0) > 255) {
      throw ArgumentError('Profile exceeds limits');
    }
    _boundedNames([name, ...?features, ...?rules]);
    if (settings.length > 128 ||
        settings.keys.any((k) => k.length > 128) ||
        settings.values.any((v) => v is String && v.length > 4096)) {
      throw ArgumentError('Profile exceeds limits');
    }
    if (settings.entries.fold<int>(
          0,
          (n, e) =>
              n +
              e.key.length +
              (e.value is String ? (e.value! as String).length : 8),
        ) >
        16384) {
      throw ArgumentError('Profile settings exceed byte budget');
    }
    return CookingProfile._(
      name,
      features == null ? null : List.unmodifiable(features),
      rules == null ? null : List.unmodifiable(rules),
      Map.unmodifiable(
        Map.fromEntries(
          (settings.keys.toList()..sort()).map((k) {
            final v = settings[k];
            if ((v is num && !v.isFinite) ||
                (v != null && v is! String && v is! bool && v is! num)) {
              throw ArgumentError('Profile settings must be scalar JSON');
            }
            return MapEntry(k, v);
          }),
        ),
      ),
      forceQuoteLink,
    );
  }
  static const post = CookingProfile._('post', null, null, {}, false);
  static const chat = CookingProfile._(
    'chat',
    [
      'anchor',
      'bbcode-block',
      'bbcode-inline',
      'code',
      'category-hashtag',
      'censored',
      'chat-transcript',
      'discourse-local-dates',
      'emoji',
      'inlineEmoji',
      'html-img',
      'hashtag-autocomplete',
      'mentions',
      'unicodeUsernames',
      'onebox',
      'quotes',
      'spoiler-alert',
      'table',
      'text-post-process',
      'upload-protocol',
      'watched-words',
      'chat-html-inline',
      'offline-missing-uploads',
    ],
    [
      'autolink',
      'list',
      'backticks',
      'newline',
      'code',
      'fence',
      'image',
      'table',
      'linkify',
      'link',
      'strikethrough',
      'blockquote',
      'emphasis',
      'replacements',
      'escape',
      'entity',
    ],
    {},
    true,
  );
  static const values = [post, chat];
  final String name;
  final List<String>? features, rules;
  final Map<String, Object?> settings;
  final bool forceQuoteLink;
  Map<String, Object?> toJson() => {
    'name': name,
    'features': features,
    'rules': rules,
    'settings': settings,
    'forceQuoteLink': forceQuoteLink,
  };
  factory CookingProfile.fromJson(Object? value) {
    if (value is String) return values.firstWhere((p) => p.name == value);
    final json = (value! as Map).cast<String, Object?>();
    return CookingProfile(
      name: json['name']! as String,
      features: (json['features'] as List?)?.cast<String>(),
      rules: (json['rules'] as List?)?.cast<String>(),
      settings: (json['settings'] as Map?)?.cast<String, Object?>() ?? {},
      forceQuoteLink: json['forceQuoteLink'] as bool? ?? false,
    );
  }
}

/// Selects trusted code compiled into the application; never carries JS source.
final class CookingModule {
  factory CookingModule({
    required String id,
    required String owner,
    required String version,
    List<String> dependencies = const [],
    int order = 0,
    String? enabledSetting,
    List<String> profiles = const [],
  }) {
    if (dependencies.length + profiles.length > 251) {
      throw ArgumentError('Module exceeds limits');
    }
    _boundedNames([
      id,
      owner,
      version,
      ...dependencies,
      ...profiles,
      ?enabledSetting,
    ]);
    return CookingModule._(
      id: id,
      owner: owner,
      version: version,
      dependencies: List.unmodifiable(dependencies),
      order: order,
      enabledSetting: enabledSetting,
      profiles: List.unmodifiable(profiles),
    );
  }
  const CookingModule._({
    required this.id,
    required this.owner,
    required this.version,
    this.dependencies = const [],
    this.order = 0,
    this.enabledSetting,
    this.profiles = const [],
  });
  static const spoiler = CookingModule._(
    id: 'spoiler-alert',
    owner: 'cooking',
    version: '1',
  );
  static const missingUploads = CookingModule._(
    id: 'offline-missing-uploads',
    owner: 'cooking',
    version: '1',
    order: 10,
  );
  final String id, owner, version;
  final List<String> dependencies;
  final int order;
  final String? enabledSetting;
  final List<String> profiles;
  Map<String, Object?> toJson() => {
    'id': id,
    'owner': owner,
    'version': version,
    'dependencies': List<String>.of(dependencies),
    'order': order,
    'enabledSetting': enabledSetting,
    'profiles': List<String>.of(profiles),
  };
  factory CookingModule.fromJson(Map<String, Object?> json) => CookingModule(
    id: json['id']! as String,
    owner: json['owner']! as String,
    version: json['version']! as String,
    dependencies: (json['dependencies'] as List? ?? []).cast<String>(),
    order: json['order'] as int? ?? 0,
    enabledSetting: json['enabledSetting'] as String?,
    profiles: (json['profiles'] as List? ?? []).cast<String>(),
  );
}

/// Validated immutable installation, shared by all consumers in a session.
final class CookingConfiguration {
  factory CookingConfiguration({
    List<CookingModule> modules = const [
      CookingModule.spoiler,
      CookingModule.missingUploads,
    ],
    List<CookingProfile> profiles = const [
      CookingProfile.post,
      CookingProfile.chat,
    ],
    Set<String>? installedOwners,
  }) {
    if (modules.length > 64 || profiles.length > 64) {
      throw ArgumentError('Configuration exceeds limits');
    }
    for (final m in modules) {
      _boundedNames([
        m.id,
        m.owner,
        m.version,
        ...m.dependencies,
        ...m.profiles,
        if (m.enabledSetting != null) m.enabledSetting!,
      ]);
    }
    final copied = modules
        .map((m) => CookingModule.fromJson(m.toJson()))
        .toList();
    final byId = <String, CookingModule>{};
    for (final module in copied) {
      if (byId.containsKey(module.id)) {
        throw ArgumentError('Duplicate cooking module: ${module.id}');
      }
      final bundled = bundledCookingModules[module.id];
      if (bundled == null ||
          bundled['owner'] != module.owner ||
          bundled['version'] != module.version) {
        throw ArgumentError(
          'Missing or incompatible bundled module: ${module.id}',
        );
      }
      if (installedOwners != null && !installedOwners.contains(module.owner)) {
        throw ArgumentError('Module owner is not installed: ${module.owner}');
      }
      byId[module.id] = module;
    }
    final ordered = <CookingModule>[],
        visiting = <String>{},
        visited = <String>{};
    void visit(CookingModule module) {
      if (visited.contains(module.id)) return;
      if (!visiting.add(module.id)) {
        throw ArgumentError('Cooking dependency cycle: ${module.id}');
      }
      for (final id in module.dependencies) {
        final dependency = byId[id];
        if (dependency == null) {
          throw ArgumentError('Missing cooking dependency: $id');
        }
        const stages = ['syntax', 'token', 'document'];
        if (stages.indexOf(bundledCookingModules[dependency.id]!['stage']!) >
            stages.indexOf(bundledCookingModules[module.id]!['stage']!)) {
          throw ArgumentError('Dependency requires a later cooking stage: $id');
        }
        visit(dependency);
      }
      visiting.remove(module.id);
      visited.add(module.id);
      ordered.add(module);
    }

    copied.sort(
      (a, b) => a.order != b.order
          ? a.order.compareTo(b.order)
          : a.id.compareTo(b.id),
    );
    for (final module in copied) {
      visit(module);
    }
    final names = <String>{};
    for (final profile in profiles) {
      if (!names.add(profile.name)) {
        throw ArgumentError('Duplicate cooking profile: ${profile.name}');
      }
      jsonEncode(profile.toJson());
    }
    for (final module in ordered) {
      if (module.profiles.any((name) => !names.contains(name))) {
        throw ArgumentError('Module selects unknown profile: ${module.id}');
      }
    }
    final configuration = CookingConfiguration._(
      List.unmodifiable(ordered),
      List.unmodifiable(profiles),
    );
    if (utf8.encode(jsonEncode(configuration.toJson())).length > 65536) {
      throw ArgumentError('Configuration exceeds 65,536 bytes');
    }
    return configuration;
  }
  const CookingConfiguration._(this.modules, this.profiles);
  final List<CookingModule> modules;
  final List<CookingProfile> profiles;
  Map<String, Object?> toJson() => {
    'modules': modules.map((m) => m.toJson()).toList(),
    'profiles': profiles.map((p) => p.toJson()).toList(),
  };
  factory CookingConfiguration.fromJson(Map<String, Object?> json) {
    if ((json['modules']! as List).length > 64 ||
        (json['profiles']! as List).length > 64) {
      throw ArgumentError('Configuration exceeds limits');
    }
    return CookingConfiguration(
      modules: (json['modules']! as List)
          .map(
            (m) => CookingModule.fromJson((m as Map).cast<String, Object?>()),
          )
          .toList(),
      profiles: (json['profiles']! as List)
          .map(CookingProfile.fromJson)
          .toList(),
    );
  }
}

extension CookingProfileLookup on List<CookingProfile> {
  CookingProfile byName(String name) => firstWhere((p) => p.name == name);
}

void _boundedNames(List<String> values) {
  if (values.length > 256 || values.any((v) => v.isEmpty || v.length > 128)) {
    throw ArgumentError('Cooking declaration exceeds limits');
  }
}
