import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/site_lifecycle.dart';
import '../../models/found_group.dart';
import '../shell_controller.dart';
import 'controller.dart';

final class ComposerRecipientLookup extends ChangeNotifier {
  ComposerRecipientLookup({required this.composer, required this.shell})
    : siteUrl = composer.target.siteUrl,
      _lease = shell.lifecycle.capture(composer.target.siteUrl) {
    _detachRetirement = _lease.onRetire(_retire);
  }

  final ComposerController composer;
  final ShellController shell;
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

  bool matches(ComposerController composer, ShellController shell) =>
      !_retired &&
      _lease.isCurrent &&
      identical(this.composer, composer) &&
      identical(this.shell, shell) &&
      siteUrl == composer.target.siteUrl;

  bool get _isCurrent =>
      !_retired &&
      _lease.isCurrent &&
      !shell.accountSessionDisposed &&
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
      final results = await shell.searchMessageRecipients(
        siteUrl: siteUrl,
        term: query.trim(),
      );
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
