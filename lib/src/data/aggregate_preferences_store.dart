import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/discourse_instance.dart';
import 'coalescing_snapshot_writer.dart';
import 'store_diagnostics.dart';

abstract interface class AggregatePreferencesPersistence {
  Future<String?> read();

  Future<bool> write(String value);
}

final class AggregatePreferences {
  AggregatePreferences({
    List<AggregateTabPreferences>? tabs,
    String? activeTabId,
    Set<String>? excludedForums,
    Map<String, String>? queries,
  }) : tabs = List.unmodifiable(
         (tabs == null || tabs.isEmpty)
             ? [
                 AggregateTabPreferences(
                   id: AggregatePreferencesStore.defaultTabId,
                   excludedForums: excludedForums,
                   queries: queries,
                 ),
               ]
             : tabs,
       ),
       activeTabId =
           activeTabId ??
           ((tabs?.isNotEmpty ?? false)
               ? tabs!.first.id
               : AggregatePreferencesStore.defaultTabId);

  final List<AggregateTabPreferences> tabs;
  final String activeTabId;

  AggregateTabPreferences get activeTab =>
      tabs.firstWhere((tab) => tab.id == activeTabId, orElse: () => tabs.first);

  /// Compatibility accessors for the pre-tab preferences document.
  Set<String> get excludedForums => activeTab.excludedForums;
  Map<String, String> get queries => activeTab.queries;
}

final class AggregateTabPreferences {
  AggregateTabPreferences({
    required this.id,
    String? name,
    Set<String>? excludedForums,
    Map<String, String>? queries,
  }) : name = AggregatePreferencesStore.normalizeTabName(name),
       excludedForums = Set.unmodifiable(excludedForums ?? const {}),
       queries = Map.unmodifiable(queries ?? const {});

  final String id;
  final String? name;
  final Set<String> excludedForums;
  final Map<String, String> queries;

  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'excluded_forums': excludedForums.toList()..sort(),
    'queries': Map.fromEntries(
      [
        for (final MapEntry(:key, :value) in queries.entries)
          if (AggregatePreferencesStore._isOrigin(key) &&
              AggregatePreferencesStore._normalizeQuery(value).isNotEmpty)
            MapEntry(key, AggregatePreferencesStore._normalizeQuery(value)),
      ]..sort((left, right) => left.key.compareTo(right.key)),
    ),
  };

  static AggregateTabPreferences? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    if (id is! String || id.isEmpty || id.length > 128) return null;
    final excluded = value['excluded_forums'];
    final queries = value['queries'];
    return AggregateTabPreferences(
      id: id,
      name: value['name'] is String ? value['name'] as String : null,
      excludedForums: {
        if (excluded is List)
          for (final siteUrl in excluded)
            if (siteUrl is String &&
                AggregatePreferencesStore._isOrigin(siteUrl))
              siteUrl,
      },
      queries: {
        if (queries is Map)
          for (final MapEntry(key: siteUrl, value: query) in queries.entries)
            if (siteUrl is String &&
                query is String &&
                AggregatePreferencesStore._isOrigin(siteUrl) &&
                AggregatePreferencesStore._normalizeQuery(query).isNotEmpty)
              siteUrl: AggregatePreferencesStore._normalizeQuery(query),
      },
    );
  }
}

final class SharedPreferencesAggregatePreferencesPersistence
    implements AggregatePreferencesPersistence {
  const SharedPreferencesAggregatePreferencesPersistence();

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance())
      .getString(AggregatePreferencesStore.storageKey);

  @override
  Future<bool> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(
        AggregatePreferencesStore.storageKey,
        value,
      );
}

final class MemoryAggregatePreferencesPersistence
    implements AggregatePreferencesPersistence {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<bool> write(String value) async {
    this.value = value;
    return true;
  }
}

/// Versioned app-wide configuration for cross-forum Aggregate feed tabs.
///
/// Exclusions are persisted instead of inclusions so a newly connected forum
/// participates by default. A query is stored only when it is non-empty; an
/// included forum without one asks Discourse for its default topic filter.
/// Origins are already owned by [DiscourseInstance], and malformed or stale
/// entries are pruned by the controller when it next saves.
final class AggregatePreferencesStore {
  AggregatePreferencesStore({AggregatePreferencesPersistence? persistence})
    : _persistence =
          persistence ??
          const SharedPreferencesAggregatePreferencesPersistence();

  AggregatePreferencesStore.memory()
    : _persistence = MemoryAggregatePreferencesPersistence();

  static const storageKey = 'discourse_native.aggregate_preferences';
  static const formatVersion = 4;
  static const defaultTabId = 'aggregate-default';
  static const maximumTabs = 20;
  static const maximumTabNameLength = 80;
  static const maximumQueryLength = 2048;

  final AggregatePreferencesPersistence _persistence;
  late final CoalescingSnapshotWriter<String> _snapshots =
      CoalescingSnapshotWriter(
        owner: _persistence,
        key: storageKey,
        writeSnapshot: _persist,
      );

  Future<AggregatePreferences> load() async {
    try {
      final raw = await _snapshots.read(_persistence.read);
      if (raw == null || raw.isEmpty) return AggregatePreferences();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return AggregatePreferences();
      final version = decoded['version'];
      if (version != 1 &&
          version != 2 &&
          version != 3 &&
          version != formatVersion) {
        return AggregatePreferences();
      }
      if (version == 3 || version == formatVersion) {
        final rawTabs = decoded['tabs'];
        if (rawTabs is! List) return AggregatePreferences();
        final tabs = <AggregateTabPreferences>[];
        final seen = <String>{};
        for (final rawTab in rawTabs) {
          if (tabs.length >= maximumTabs) break;
          final tab = AggregateTabPreferences.tryFromJson(rawTab);
          if (tab != null && seen.add(tab.id)) tabs.add(tab);
        }
        if (tabs.isEmpty) return AggregatePreferences();
        final requestedActive = decoded['active_tab_id'];
        return AggregatePreferences(
          tabs: tabs,
          activeTabId:
              requestedActive is String && seen.contains(requestedActive)
              ? requestedActive
              : tabs.first.id,
        );
      }
      final excluded = decoded['excluded_forums'];
      final queries = decoded['queries'];
      return AggregatePreferences(
        excludedForums: {
          if (excluded is List)
            for (final value in excluded)
              if (value is String && _isOrigin(value)) value,
        },
        queries: {
          if (version == 2 && queries is Map)
            for (final MapEntry(key: siteUrl, value: query) in queries.entries)
              if (siteUrl is String &&
                  query is String &&
                  _isOrigin(siteUrl) &&
                  _normalizeQuery(query).isNotEmpty)
                siteUrl: _normalizeQuery(query),
        },
      );
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'aggregatePreferences.load');
      return AggregatePreferences();
    }
  }

  Future<void> save({
    Set<String>? excludedForums,
    Map<String, String>? queries,
    Iterable<AggregateTabPreferences>? tabs,
    String? activeTabId,
  }) {
    final savedTabs = List<AggregateTabPreferences>.of(
      tabs ??
          [
            AggregateTabPreferences(
              id: defaultTabId,
              excludedForums: excludedForums,
              queries: queries,
            ),
          ],
    ).take(maximumTabs).toList();
    if (savedTabs.isEmpty) {
      savedTabs.add(AggregateTabPreferences(id: defaultTabId));
    }
    final savedIds = {for (final tab in savedTabs) tab.id};
    final encoded = jsonEncode({
      'version': formatVersion,
      'active_tab_id': savedIds.contains(activeTabId)
          ? activeTabId
          : savedTabs.first.id,
      'tabs': [for (final tab in savedTabs) tab.toJson()],
    });
    return _snapshots.save(encoded);
  }

  Future<void> _persist(String encoded) async {
    try {
      if (!await _persistence.write(encoded)) {
        throw StateError('Could not persist Aggregate forum preferences.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'aggregatePreferences.save');
    }
  }

  static bool _isOrigin(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.hasAuthority &&
        uri.userInfo.isEmpty &&
        (uri.path.isEmpty || uri.path == '/') &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static String _normalizeQuery(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= maximumQueryLength) return trimmed;
    return trimmed.substring(0, maximumQueryLength);
  }

  static String? normalizeTabName(String? value) {
    if (value == null) return null;
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return null;
    if (normalized.length <= maximumTabNameLength) return normalized;
    return normalized.substring(0, maximumTabNameLength);
  }
}
