import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'coalescing_snapshot_writer.dart';
import 'store_diagnostics.dart';
import 'stored_forum_base.dart';

abstract interface class AggregatePreferencesPersistence {
  Future<String?> read();

  Future<bool> write(String value);
}

final class AggregatePreferences {
  AggregatePreferences({
    this.filtersCollapsed = true,
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

  final bool filtersCollapsed;
  final List<AggregateTabPreferences> tabs;
  final String activeTabId;

  AggregateTabPreferences get activeTab =>
      tabs.firstWhere((tab) => tab.id == activeTabId, orElse: () => tabs.first);

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
    'excluded_forums': {
      for (final value in excludedForums) ?tryStoredForumBase(value),
    }.toList()..sort(),
    'queries': Map.fromEntries(
      [
        for (final MapEntry(:key, :value) in queries.entries)
          if (tryStoredForumBase(key) case final base?)
            if (AggregatePreferencesStore._normalizeQuery(value).isNotEmpty)
              MapEntry(base, AggregatePreferencesStore._normalizeQuery(value)),
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
          for (final siteUrl in excluded) ?tryStoredForumBase(siteUrl),
      },
      queries: {
        if (queries is Map)
          for (final MapEntry(key: siteUrl, value: query) in queries.entries)
            if (tryStoredForumBase(siteUrl) case final base?)
              if (query is String &&
                  AggregatePreferencesStore._normalizeQuery(query).isNotEmpty)
                base: AggregatePreferencesStore._normalizeQuery(query),
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

/// Tabs, exclusions and queries are presentation state: a storage failure
/// degrades to the default tab and must never stop the Aggregate view from
/// opening. What it must also never do is save that default over the tabs it
/// could not read — see [_unreadable].
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

  /// Distinguishes an intact but unreadable document from an absent one so the
  /// default tab cannot overwrite unknown stored tabs. A successful later
  /// [load] clears it.
  bool _unreadable = false;

  Future<AggregatePreferences> load() async {
    final String? raw;
    try {
      raw = await _snapshots.read(_persistence.read);
      _unreadable = false;
    } catch (error, stackTrace) {
      _unreadable = true;
      reportStorageFailure(error, stackTrace, 'aggregatePreferences.load');
      return AggregatePreferences();
    }

    // Past here the document was read. Whatever it holds is either usable or
    // already lost, so a save over it is the repair rather than the damage.
    try {
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
          filtersCollapsed: decoded['filters_collapsed'] != false,
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
            for (final value in excluded) ?tryStoredForumBase(value),
        },
        queries: {
          if (version == 2 && queries is Map)
            for (final MapEntry(key: siteUrl, value: query) in queries.entries)
              if (tryStoredForumBase(siteUrl) case final base?)
                if (query is String && _normalizeQuery(query).isNotEmpty)
                  base: _normalizeQuery(query),
        },
      );
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'aggregatePreferences.decode');
      return AggregatePreferences();
    }
  }

  Future<void> save({
    Set<String>? excludedForums,
    Map<String, String>? queries,
    Iterable<AggregateTabPreferences>? tabs,
    String? activeTabId,
    bool filtersCollapsed = true,
  }) {
    if (_unreadable) return Future<void>.value();
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
      'filters_collapsed': filtersCollapsed,
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
