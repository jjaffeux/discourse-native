import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/site_lifecycle.dart';
import '../../models/found_group.dart';
import 'controller.dart';

final class ComposerRecipientSearch {
  const ComposerRecipientSearch({
    required this.siteUrl,
    required this.sourceIdentity,
    required this.lease,
    required this.isSourceCurrent,
    required this.search,
  });

  final String siteUrl;
  final Object sourceIdentity;
  final SiteLease lease;
  final bool Function() isSourceCurrent;
  final Future<FoundUsersAndGroups> Function(String term) search;

  bool get isCurrent => lease.isCurrent && isSourceCurrent();
}

final class ComposerRecipientLookup extends ChangeNotifier {
  ComposerRecipientLookup({
    required this.composer,
    required ComposerRecipientSearch search,
  }) : _search = search,
       siteUrl = composer.target.siteUrl,
       _lease = search.lease {
    _detachRetirement = _lease.onRetire(_retire);
  }

  final ComposerController composer;
  final ComposerRecipientSearch _search;
  final String siteUrl;
  final SiteLease _lease;
  late final VoidCallback _detachRetirement;
  Timer? _debounce;
  int _generation = 0;
  bool _retired = false;
  bool _rejectedSelection = false;
  String _query = '';
  FoundUsersAndGroups _results = const FoundUsersAndGroups();

  String get query => _query;
  FoundUsersAndGroups get results => _results;
  List<String> get recipients => composer.target.targetRecipients!
      .split(',')
      .where((name) => name.isNotEmpty)
      .toList();

  bool matches(ComposerController composer, ComposerRecipientSearch search) =>
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
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      if (!_isCurrent) return;
      final results = await _search.search(query.trim());
      if (!_isCurrent || generation != _generation) return;
      _results = results;
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
  }

  void setOpen(bool open, {required bool mobile}) {
    if (!_isCurrent) return;
    if (mobile) {
      _cancelPending();
      if (open) search('');
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
