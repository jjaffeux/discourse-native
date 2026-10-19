import 'dart:async';

import '../models/discourse_instance.dart';
import '../models/sidebar.dart';
import 'account_request_session.dart';
import 'api_credentials.dart';
import 'discourse_api_contracts.dart';
import 'site_lifecycle.dart';

final class CustomSidebarSections {
  CustomSidebarSections({
    required this._api,
    required this._credentials,
    required this._lifecycle,
    required this._instanceFor,
    required this._selectedSite,
    required this._onChanged,
    required this._reportFailure,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ShellSiteApi _api;
  final ApiCredentialReader _credentials;
  final SiteLifecycle _lifecycle;
  final DiscourseInstance? Function(String) _instanceFor;
  final String? Function() _selectedSite;
  final void Function() _onChanged;
  final void Function(Object, StackTrace) _reportFailure;
  final DateTime Function() _clock;
  final Map<String, _AccountSidebar> _accounts = {};
  bool _disposed = false;

  static const _retryInterval = Duration(minutes: 5);

  bool _current(_AccountSidebar account) =>
      !_disposed &&
      account.lease.isCurrent &&
      identical(_accounts[account.siteUrl], account);

  _AccountSidebar? _account(String siteUrl, {SiteLease? expected}) {
    if (_disposed ||
        _instanceFor(siteUrl) == null ||
        expected?.isCurrent == false) {
      return null;
    }
    final lease = _lifecycle.capture(siteUrl);
    if (expected != null && !identical(expected.session, lease.session)) {
      return null;
    }
    final held = _accounts[siteUrl];
    if (held != null && _current(held)) return held;
    forget(siteUrl);
    final account = _AccountSidebar(siteUrl, lease);
    _accounts[siteUrl] = account;
    account.detach = lease.onRetire(() {
      if (identical(_accounts[siteUrl], account)) forget(siteUrl);
    });
    return account;
  }

  List<SidebarSection> customFor(String siteUrl) {
    final account = _accounts[siteUrl];
    return account != null && _current(account) ? account.sections : const [];
  }

  List<SidebarSection> sectionsFor(DiscourseInstance instance) {
    final account = _account(instance.url);
    final custom = account?.sections ?? const <SidebarSection>[];
    final cached = account?.composed;
    if (cached != null &&
        identical(cached.instance, instance) &&
        identical(cached.custom, custom)) {
      return cached.sections;
    }
    final sections = List<SidebarSection>.unmodifiable(
      instance.sectionsWithCustomSections(custom),
    );
    account?.composed = (
      instance: instance,
      custom: custom,
      sections: sections,
    );
    return sections;
  }

  bool canEdit(String siteUrl, SidebarSection section) {
    final instance = _instanceFor(siteUrl);
    return !_disposed &&
        instance?.isConnected == true &&
        section.remoteId != null &&
        (!section.public || instance?.user?.admin == true);
  }

  bool canReorder(String siteUrl, SidebarSection section) =>
      canEdit(siteUrl, section) && section.destinations.length > 1;

  bool _canReorder(
    String siteUrl,
    SidebarSection section,
    int oldIndex,
    int newIndex,
  ) =>
      canReorder(siteUrl, section) &&
      customFor(siteUrl).contains(section) &&
      oldIndex >= 0 &&
      oldIndex < section.destinations.length &&
      newIndex >= 0 &&
      newIndex <= section.destinations.length &&
      newIndex != oldIndex &&
      newIndex != oldIndex + 1;

  bool canMove({
    required String siteUrl,
    required SidebarSection source,
    required SidebarSection target,
    required int oldIndex,
    required int newIndex,
  }) =>
      source != target &&
      canEdit(siteUrl, source) &&
      canEdit(siteUrl, target) &&
      customFor(siteUrl).contains(source) &&
      customFor(siteUrl).contains(target) &&
      oldIndex >= 0 &&
      oldIndex < source.destinations.length &&
      newIndex >= 0 &&
      newIndex <= target.destinations.length &&
      target.destinations.length < SidebarSection.maximumCustomLinks;

  /// Requests an admissible read. A read deferred by a local write completes
  /// here; publication follows when the last write releases its sections.
  Future<void> ensure(String siteUrl, {SiteLease? account}) {
    final instance = _instanceFor(siteUrl);
    if (_disposed ||
        _selectedSite() != siteUrl ||
        instance == null ||
        (instance.loginRequired && !instance.isConnected)) {
      return Future.value();
    }
    final state = _account(siteUrl, expected: account);
    if (state == null || state.loaded) return Future.value();
    final active = state.load;
    if (active != null) return active;
    final attemptedAt = state.attemptedAt;
    if (attemptedAt != null &&
        _clock().difference(attemptedAt) < _retryInterval) {
      return Future.value();
    }
    if (state.writing.isNotEmpty) {
      state.reloadAfterWrites = true;
      return Future.value();
    }
    late final Future<void> request;
    request = _load(state, state.readVersion).whenComplete(() {
      if (identical(state.load, request)) state.load = null;
    });
    state.load = request;
    return request;
  }

  Future<void> _load(_AccountSidebar account, int version) async {
    try {
      final session = AccountRequestSession(account.siteUrl, account.lease);
      final connected = _instanceFor(account.siteUrl)?.isConnected == true;
      final credential = connected
          ? await session.credentials(_credentials)
          : session.anonymousCredentials();
      if (!_current(account) ||
          account.readVersion != version ||
          _selectedSite() != account.siteUrl ||
          (connected && credential.apiKey == null)) {
        return;
      }
      account.attemptedAt = _clock();
      final sections = await credential.run(
        () => _api.customSidebarSections(
          siteUrl: account.siteUrl,
          apiKey: credential.apiKey,
          clientId: connected ? credential.clientId : null,
        ),
      );
      if (!_current(account) || account.readVersion != version) return;
      account.sections = _freeze(sections);
      account.loaded = true;
      _onChanged();
    } catch (error, stackTrace) {
      if (_current(account) && account.readVersion == version) {
        _reportFailure(error, stackTrace);
      }
    }
  }

  void invalidate(String siteUrl, {required SiteLease account}) {
    final state = _account(siteUrl, expected: account);
    if (state == null) return;
    state.readVersion++;
    state.liveVersion++;
    state.loaded = false;
    state.attemptedAt = null;
    state.load = null;
    if (state.writing.isNotEmpty) {
      state.reloadAfterWrites = true;
    } else {
      unawaited(ensure(siteUrl, account: state.lease));
    }
  }

  bool _reserve(_AccountSidebar account, Set<int> sections) {
    if (sections.any(account.writing.contains)) return false;
    account.writing.addAll(sections);
    account.readVersion++;
    if (account.load != null) {
      account.load = null;
      account.loaded = false;
      account.attemptedAt = null;
      account.reloadAfterWrites = true;
    }
    return true;
  }

  void _release(_AccountSidebar account, Set<int> sections) {
    account.writing.removeAll(sections);
    if (!_current(account) ||
        account.writing.isNotEmpty ||
        !account.reloadAfterWrites) {
      return;
    }
    account.reloadAfterWrites = false;
    unawaited(ensure(account.siteUrl, account: account.lease));
  }

  void _publishEdit(
    _AccountSidebar account,
    int liveVersion,
    List<SidebarSection> updated,
  ) {
    if (!_current(account) || account.liveVersion != liveVersion) return;
    final replacements = {
      for (final section in _freeze(updated)) section.remoteId: section,
    };
    account.sections = List.unmodifiable([
      for (final existing in account.sections)
        replacements[existing.remoteId] ?? existing,
    ]);
    _onChanged();
  }

  /// [newIndex] is an insertion gap in the original list.
  Future<void> reorder({
    required String siteUrl,
    required SidebarSection section,
    required int oldIndex,
    required int newIndex,
  }) async {
    bool allowed() => _canReorder(siteUrl, section, oldIndex, newIndex);
    if (!allowed()) return;
    final account = _account(siteUrl);
    final sections = {section.remoteId!};
    if (account == null || !_reserve(account, sections)) return;
    final liveVersion = account.liveVersion;
    try {
      final credential = await AccountRequestSession(
        siteUrl,
        account.lease,
      ).credentials(_credentials);
      if (!_current(account) ||
          account.liveVersion != liveVersion ||
          !allowed()) {
        return;
      }
      if (credential.apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final ids = section.destinations.map((link) => link.linkId!).toList();
      final moved = ids.removeAt(oldIndex);
      ids.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, moved);
      final updated = await credential.run(
        () => _api.reorderSidebarLinks(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          clientId: credential.clientId,
          sectionId: section.remoteId!,
          linksOrder: ids,
        ),
      );
      _publishEdit(account, liveVersion, [updated]);
    } on AccountRequestRetiredException {
      return;
    } finally {
      _release(account, sections);
    }
  }

  Future<void> move({
    required String siteUrl,
    required SidebarSection source,
    required SidebarSection target,
    required int oldIndex,
    required int newIndex,
  }) async {
    bool allowed() => canMove(
      siteUrl: siteUrl,
      source: source,
      target: target,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    if (!allowed()) return;
    final account = _account(siteUrl);
    final sections = {source.remoteId!, target.remoteId!};
    if (account == null || !_reserve(account, sections)) return;
    final liveVersion = account.liveVersion;
    try {
      final credential = await AccountRequestSession(
        siteUrl,
        account.lease,
      ).credentials(_credentials);
      if (!_current(account) ||
          account.liveVersion != liveVersion ||
          !allowed()) {
        return;
      }
      if (credential.apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final updated = await credential.run(
        () => _api.moveSidebarLink(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          clientId: credential.clientId,
          sourceSectionId: source.remoteId!,
          targetSectionId: target.remoteId!,
          linkId: source.destinations[oldIndex].linkId!,
          position: newIndex,
        ),
      );
      _publishEdit(account, liveVersion, updated);
    } on AccountRequestRetiredException {
      return;
    } finally {
      _release(account, sections);
    }
  }

  void forget(String siteUrl) {
    final account = _accounts.remove(siteUrl);
    account?.detach?.call();
  }

  void dispose() {
    _disposed = true;
    for (final siteUrl in _accounts.keys.toList()) {
      forget(siteUrl);
    }
  }

  static List<SidebarSection> _freeze(Iterable<SidebarSection> sections) =>
      List.unmodifiable([
        for (final section in sections)
          SidebarSection(
            id: section.id,
            title: section.title,
            destinations: List.unmodifiable(section.destinations),
            moreDestinations: List.unmodifiable(section.moreDestinations),
            showHeader: section.showHeader,
            collapsible: section.collapsible,
            actionIcon: section.actionIcon,
            actionLabel: section.actionLabel,
            actionShortcut: section.actionShortcut,
            onAction: section.onAction,
            actionAboveHeader: section.actionAboveHeader,
            headerActionsBuilder: section.headerActionsBuilder,
            pinnedHeaderBuilder: section.pinnedHeaderBuilder,
            bodyBuilder: section.bodyBuilder,
            unreadCount: section.unreadCount,
            loading: section.loading,
            remoteId: section.remoteId,
            public: section.public,
          ),
      ]);
}

final class _AccountSidebar {
  _AccountSidebar(this.siteUrl, this.lease);

  final String siteUrl;
  final SiteLease lease;
  void Function()? detach;
  List<SidebarSection> sections = const [];
  bool loaded = false;
  DateTime? attemptedAt;
  Future<void>? load;
  int readVersion = 0;
  int liveVersion = 0;
  final Set<int> writing = {};
  bool reloadAfterWrites = false;
  ({
    DiscourseInstance instance,
    List<SidebarSection> custom,
    List<SidebarSection> sections,
  })?
  composed;
}
