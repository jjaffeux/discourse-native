import 'dart:async';

import 'package:flutter/material.dart';

import '../models/found_user.dart';
import '../models/post.dart';
import 'avatar_image.dart';
import 'shell_controller.dart';

Future<void> showTopicChangeOwner({
  required BuildContext context,
  required ShellController controller,
  required String siteUrl,
  required int topicId,
  required List<Post> selectedPosts,
  bool usesTopicSelection = true,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _TopicChangeOwnerDialog(
    controller: controller,
    siteUrl: siteUrl,
    topicId: topicId,
    selectedPosts: selectedPosts,
    usesTopicSelection: usesTopicSelection,
  ),
);

class _TopicChangeOwnerDialog extends StatefulWidget {
  const _TopicChangeOwnerDialog({
    required this.controller,
    required this.siteUrl,
    required this.topicId,
    required this.selectedPosts,
    required this.usesTopicSelection,
  });

  final ShellController controller;
  final String siteUrl;
  final int topicId;
  final List<Post> selectedPosts;
  final bool usesTopicSelection;

  @override
  State<_TopicChangeOwnerDialog> createState() =>
      _TopicChangeOwnerDialogState();
}

class _TopicChangeOwnerDialogState extends State<_TopicChangeOwnerDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  List<FoundUser> _users = const [];
  FoundUser? _selected;
  bool _searching = false;
  bool _saving = false;
  String? _error;

  String get _oldUsername => widget.selectedPosts.first.username;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _selected = null;
      _error = null;
      if (value.trim().isEmpty) {
        _users = const [];
        _searching = false;
      } else {
        _searching = true;
      }
    });
    if (value.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final users = await widget.controller.searchUsers(
        siteUrl: widget.siteUrl,
        topicId: widget.topicId,
        term: value,
      );
      if (!mounted || generation != _generation) return;
      final available = users
          .where((user) => user.username != _oldUsername)
          .toList();
      setState(() {
        _searching = false;
        _users = List.unmodifiable(available);
        if (_users.length == 1) _selected = _users.single;
      });
    });
  }

  Future<void> _changeOwner() async {
    final selected = _selected;
    if (_saving || selected == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = widget.usesTopicSelection
        ? await widget.controller.changeSelectedTopicPostOwner(
            widget.siteUrl,
            widget.topicId,
            selected.username,
          )
        : await widget.controller.changeTopicPostOwner(
            widget.selectedPosts.single,
            selected.username,
          );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.selectedPosts.length;
    return AlertDialog(
      key: const ValueKey('topic-change-owner-dialog'),
      title: const Text('Change post owner'),
      content: SizedBox(
        width: 480,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Assign $count ${count == 1 ? 'post' : 'posts'} by '
              '@$_oldUsername to another account.',
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('topic-change-owner-search'),
              controller: _search,
              autofocus: true,
              enabled: !_saving,
              onChanged: _scheduleSearch,
              decoration: const InputDecoration(
                labelText: 'Search users',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : _users.isEmpty
                  ? Center(
                      child: Text(
                        _search.text.trim().isEmpty
                            ? 'Search for the new owner.'
                            : 'No users found.',
                      ),
                    )
                  : RadioGroup<FoundUser>(
                      groupValue: _selected,
                      onChanged: _saving
                          ? (_) {}
                          : (value) => setState(() => _selected = value),
                      child: ListView(
                        key: const ValueKey('topic-change-owner-results'),
                        children: [
                          for (final user in _users)
                            RadioListTile<FoundUser>(
                              key: ValueKey(
                                'topic-change-owner-user-${user.username}',
                              ),
                              value: user,
                              secondary: ClipOval(
                                child: SizedBox.square(
                                  dimension: 32,
                                  child: AvatarImage(
                                    url: user.avatarUrl,
                                    size: 32,
                                    fallback: ColoredBox(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      child: Center(
                                        child: Text(
                                          user.username.characters.first
                                              .toUpperCase(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(user.name ?? user.username),
                              subtitle: user.name == null
                                  ? null
                                  : Text('@${user.username}'),
                            ),
                        ],
                      ),
                    ),
            ),
            if (_error case final error?)
              Text(
                error,
                key: const ValueKey('topic-change-owner-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('topic-change-owner-submit'),
          onPressed: !_saving && _selected != null
              ? () => unawaited(_changeOwner())
              : null,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Text('Change owner'),
        ),
      ],
    );
  }
}
