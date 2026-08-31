import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/found_user.dart';
import 'group_page_types.dart';

final class GroupMemberFilterController extends ChangeNotifier {
  GroupMemberFilterController({
    required String filter,
    required this.onFilterChanged,
    this.debounceDuration = const Duration(milliseconds: 300),
  }) : searchController = TextEditingController(text: filter);

  final TextEditingController searchController;
  final Duration debounceDuration;
  ValueChanged<String>? onFilterChanged;
  Timer? _debounce;

  void update({
    required String filter,
    required ValueChanged<String>? onFilterChanged,
  }) {
    this.onFilterChanged = onFilterChanged;
    if (searchController.text != filter) searchController.text = filter;
  }

  void search(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      debounceDuration,
      () => onFilterChanged?.call(value.trim()),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }
}

final class GroupMemberAdditionController extends ChangeNotifier {
  GroupMemberAdditionController({
    required this.searchUsers,
    required this.addMembers,
    this.searchDebounce = const Duration(milliseconds: 250),
  });

  final Future<List<FoundUser>> Function(String query) searchUsers;
  final GroupAddMembers addMembers;
  final Duration searchDebounce;
  final Set<String> _selectedUsernames = {};
  final Set<String> _selectedEmails = {};

  Timer? _debounce;
  List<FoundUser> _results = const [];
  String _query = '';
  String? _error;
  int _sequence = 0;
  bool _searching = false;
  bool _saving = false;
  bool _disposed = false;

  List<FoundUser> get results => _results;
  String get query => _query;
  String? get error => _error;
  bool get searching => _searching;
  bool get saving => _saving;
  Set<String> get selectedUsernames => Set.unmodifiable(_selectedUsernames);
  Set<String> get selectedEmails => Set.unmodifiable(_selectedEmails);
  int get selectionCount => _selectedUsernames.length + _selectedEmails.length;
  bool get canSave => !_saving && selectionCount > 0;
  String get normalizedEmail => _query.trim().toLowerCase();
  bool get queryIsEmail =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_query.trim());

  void search(String value) {
    _query = value;
    _error = null;
    _debounce?.cancel();
    final request = ++_sequence;
    if (value.trim().length < 2) {
      _results = const [];
      _searching = false;
      notifyListeners();
      return;
    }
    notifyListeners();
    _debounce = Timer(searchDebounce, () => _runSearch(value, request));
  }

  Future<void> _runSearch(String value, int request) async {
    _searching = true;
    notifyListeners();
    final found = await searchUsers(value.trim());
    if (_disposed || request != _sequence) return;
    _results = found;
    _searching = false;
    notifyListeners();
  }

  void toggleUsername(String username, {required bool selected}) {
    selected
        ? _selectedUsernames.add(username)
        : _selectedUsernames.remove(username);
    notifyListeners();
  }

  void toggleEmail(String email, {required bool selected}) {
    selected ? _selectedEmails.add(email) : _selectedEmails.remove(email);
    notifyListeners();
  }

  Future<bool> save() async {
    if (!canSave) return false;
    _saving = true;
    _error = null;
    notifyListeners();
    final result = await addMembers(
      _selectedUsernames.toList(growable: false),
      _selectedEmails.toList(growable: false),
    );
    if (_disposed) return false;
    if (result == null) {
      _saving = false;
      _error = 'The selected members could not be added.';
      notifyListeners();
      return false;
    }
    if (result.skippedUsernames.isNotEmpty) {
      _saving = false;
      _error = 'Not added: ${result.skippedUsernames.join(', ')}';
      notifyListeners();
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _sequence++;
    _debounce?.cancel();
    super.dispose();
  }
}

enum GroupInviteSubmission { failed, sent, linkCreated }

final class GroupInviteController extends ChangeNotifier {
  GroupInviteController({required this.siteUrl, required this.createInvite}) {
    email.addListener(notifyListeners);
  }

  final String siteUrl;
  final GroupCreateInvite createInvite;
  final TextEditingController email = TextEditingController();
  final TextEditingController message = TextEditingController();

  bool _saving = false;
  String? _error;
  String? _link;
  bool _disposed = false;

  bool get saving => _saving;
  String? get error => _error;
  String? get link => _link;
  bool get hasEmail => email.text.trim().isNotEmpty;

  Future<GroupInviteSubmission> create() async {
    if (_saving) return GroupInviteSubmission.failed;
    _saving = true;
    _error = null;
    notifyListeners();
    final normalizedEmail = email.text.trim();
    final normalizedMessage = message.text.trim();
    final invite = await createInvite(
      email: normalizedEmail.isEmpty ? null : normalizedEmail,
      customMessage: normalizedMessage.isEmpty ? null : normalizedMessage,
    );
    if (_disposed) return GroupInviteSubmission.failed;
    if (invite == null) {
      _saving = false;
      _error = 'The invitation could not be created.';
      notifyListeners();
      return GroupInviteSubmission.failed;
    }
    if (normalizedEmail.isNotEmpty) {
      _saving = false;
      notifyListeners();
      return GroupInviteSubmission.sent;
    }
    final rawLink = invite.link;
    _saving = false;
    _link = rawLink == null ? null : _resolveSitePath(siteUrl, rawLink);
    _error = rawLink == null
        ? 'The server did not return an invite link.'
        : null;
    notifyListeners();
    return rawLink == null
        ? GroupInviteSubmission.failed
        : GroupInviteSubmission.linkCreated;
  }

  @override
  void dispose() {
    _disposed = true;
    email.removeListener(notifyListeners);
    email.dispose();
    message.dispose();
    super.dispose();
  }
}

String _resolveSitePath(String siteUrl, String path) {
  final base = Uri.parse(siteUrl.endsWith('/') ? siteUrl : '$siteUrl/');
  return base.resolve(path).toString();
}
