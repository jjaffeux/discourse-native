import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
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
}) {
  final target = controller.captureTopicPostOwnerTarget(
    siteUrl: siteUrl,
    topicId: topicId,
    postId: usesTopicSelection ? null : selectedPosts.single.id,
  );
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TopicChangeOwnerDialog(
      controller: controller,
      target: target,
      selectedPosts: selectedPosts,
      usesTopicSelection: usesTopicSelection,
    ),
  );
}

class _TopicChangeOwnerDialog extends StatefulWidget {
  const _TopicChangeOwnerDialog({
    required this.controller,
    required this.target,
    required this.selectedPosts,
    required this.usesTopicSelection,
  });

  final ShellController controller;
  final TopicPostOwnerTarget target;
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
      final users = await widget.controller.searchTopicPostOwnerUsers(
        widget.target,
        value,
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
            widget.target,
            selected.username,
          )
        : await widget.controller.changeTopicPostOwner(
            widget.target,
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
      title: Text(context.l10n.changePostOwner),
      content: SizedBox(
        width: 480,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.assignByToAnotherAccount(
                count,
                (_oldUsername).toString(),
              ),
            ),
            const SizedBox(height: 14),
            DInput(
              key: const ValueKey('topic-change-owner-search'),
              controller: _search,
              autofocus: true,
              enabled: !_saving,
              onChanged: _scheduleSearch,

              labelText: context.l10n.searchUsers,
              prefix: const Icon(Icons.search),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _searching
                  ? const SizedBox.shrink()
                  : _users.isEmpty
                  ? Center(
                      child: Text(
                        _search.text.trim().isEmpty
                            ? context.l10n.searchForTheNewOwner
                            : context.l10n.noUsersFound,
                      ),
                    )
                  : DRadioGroup<FoundUser>.controlled(
                      groupValue: _selected,
                      enabled: !_saving,
                      onChanged: _saving
                          ? (_) {}
                          : (value) => setState(() => _selected = value),
                      child: ListView(
                        key: const ValueKey('topic-change-owner-results'),
                        children: [
                          for (final user in _users)
                            DRadioGroupItem<FoundUser>(
                              key: ValueKey(
                                'topic-change-owner-user-${user.username}',
                              ),
                              value: user,
                              trailing: DAvatar.frame(
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
                              label: Text(user.name ?? user.username),
                              description: user.name == null
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
        DButton(
          label: Text(context.l10n.cancel),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        DButton(
          key: const ValueKey('topic-change-owner-submit'),
          label: Text(context.l10n.changeOwner),
          onPressed: !_saving && _selected != null
              ? () => unawaited(_changeOwner())
              : null,
          variant: DButtonVariant.primary,
          loading: _saving,
        ),
      ],
    );
  }
}
