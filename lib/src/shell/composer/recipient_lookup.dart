import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/site_lifecycle.dart';
import '../../models/found_group.dart';
import 'composer_identity_directory.dart';
import 'recipient_target.dart';

final class ComposerRecipientLookup extends ChangeNotifier {
  ComposerRecipientLookup({
    required this.composer,
    required ComposerRecipientSearch search,
  }) : _search = search,
       siteUrl = composer.target.siteUrl,
       _lease = search.lease {
    _detachRetirement = _lease.onRetire(_retire);
  }

  final ComposerRecipientTarget composer;
  final ComposerRecipientSearch _search;
  final String siteUrl;
  final SiteLease _lease;
  late final VoidCallback _detachRetirement;
  Timer? _debounce;
  int _generation = 0;
  bool _retired = false;
  bool _rejectedSelection = false;
  bool _mobile = false;
  String _query = '';
  FoundUsersAndGroups _results = const FoundUsersAndGroups();
  final _rosters = <String, Set<String>?>{};
  final _loadingRosters = <String>{};
  final _knownUsers = <String>{};

  int? groupMemberCount(String name) => _rosters[name]?.length;

  int? reach(String? sender) {
    final usernames = <String>{};
    for (final recipient in recipients) {
      if (_knownUsers.contains(recipient)) {
        usernames.add(recipient.toLowerCase());
      } else if (_rosters[recipient] case final roster?) {
        usernames.addAll(roster);
      } else {
        return null;
      }
    }
    usernames.remove(sender?.toLowerCase());
    return usernames.length;
  }

  void loadRecipientCounts() {
    if (!_isCurrent) return;
    final visibleGroups = _results.groups.map((group) => group.name).toSet();
    for (final name in {...visibleGroups, ...recipients}) {
      if (_knownUsers.contains(name) ||
          _rosters.containsKey(name) ||
          !_loadingRosters.add(name)) {
        continue;
      }
      unawaited(_loadRoster(name, knownGroup: visibleGroups.contains(name)));
    }
  }

  Future<void> _loadRoster(String name, {required bool knownGroup}) async {
    final roster = await _search.groupRoster(name);
    if (!_isCurrent) return;
    if (roster == null && !knownGroup && recipients.contains(name)) {
      // Drafts store comma-separated names. An exact user match can resolve
      // a restored entry when there is no group roster for that name.
      final found = await _search.search(name);
      if (!_isCurrent) return;
      if (!found.groups.any((group) => group.name == name) &&
          found.users.any(
            (user) => user.username.toLowerCase() == name.toLowerCase(),
          )) {
        _knownUsers.add(name);
      }
    }
    _loadingRosters.remove(name);
    _rosters[name] = roster;
    notifyListeners();
  }

  String get query => _query;
  FoundUsersAndGroups get results => _results;
  List<String> get recipients => composer.target.targetRecipients!
      .split(',')
      .where((name) => name.isNotEmpty)
      .toList();

  bool matches(
    ComposerRecipientTarget composer,
    ComposerRecipientSearch search,
  ) =>
      !_retired &&
      _lease.isCurrent &&
      identical(this.composer, composer) &&
      identical(_search.sourceIdentity, search.sourceIdentity) &&
      identical(_lease.session, search.lease.session) &&
      siteUrl == search.siteUrl &&
      siteUrl == composer.target.siteUrl;

  bool get _isCurrent =>
      !_retired &&
      _search.isCurrent &&
      composer.isCurrent &&
      siteUrl == composer.target.siteUrl;

  void search(String query, {bool selectionReset = false}) {
    if (!_isCurrent) return;
    final rejectedReset = _rejectedSelection && query.isEmpty && selectionReset;
    _rejectedSelection = false;
    if (rejectedReset) return;
    _cancelPending();
    final generation = _generation;
    _query = query;
    _results = const FoundUsersAndGroups();
    notifyListeners();
    if (!_isCurrent || generation != _generation) return;
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      if (!_isCurrent || generation != _generation) return;
      final FoundUsersAndGroups results;
      try {
        results = await _search.search(query.trim());
      } catch (_) {
        // Keep the query editable so the reader can retry the lookup.
        return;
      }
      if (!_isCurrent || generation != _generation) return;
      _results = results;
      _knownUsers.addAll(results.users.map((user) => user.username));
      if (_mobile) loadRecipientCounts();
      notifyListeners();
    });
  }

  void select(List<String> values) {
    if (!_isCurrent) return;
    final current = recipients;
    final accepted = values
        .where(
          (name) =>
              current.contains(name) ||
              _results.users.any((user) => user.username == name) ||
              _results.groups.any((group) => group.name == name),
        )
        .toList();
    _rejectedSelection = accepted.length != values.length;
    composer.setRecipients(accepted);
    if (_mobile) loadRecipientCounts();
  }

  void setOpen(bool open, {required bool mobile}) {
    if (!_isCurrent) return;
    _mobile = mobile;
    if (mobile) {
      _cancelPending();
      if (open) {
        loadRecipientCounts();
        search('');
      }
    } else if (open && _results.users.isEmpty && _results.groups.isEmpty) {
      search(_query);
    }
  }

  void _cancelPending() {
    _debounce?.cancel();
    _generation++;
  }

  void _retire() {
    _retired = true;
    _cancelPending();
    _query = '';
    _results = const FoundUsersAndGroups();
    _rejectedSelection = false;
    _rosters.clear();
    _knownUsers.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _retired = true;
    _cancelPending();
    _detachRetirement();
    super.dispose();
  }
}
