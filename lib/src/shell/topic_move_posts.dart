import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/topic.dart';
import 'category_icon.dart';
import 'shell_controller.dart';

Future<void> showTopicMovePosts({
  required BuildContext context,
  required ShellController controller,
  required String siteUrl,
  required TopicDetail topic,
  required List<Post> selectedPosts,
}) async {
  final target = controller.captureTopicPostMoveTarget(siteUrl, topic.id);
  final categories = controller
      .topicComposerCategories(siteUrl)
      .where(
        (category) => category.permission == null || category.permission == 1,
      )
      .toList();
  final destinationUrl = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TopicMovePostsDialog(
      controller: controller,
      target: target,
      topic: topic,
      selectedPosts: selectedPosts,
      categories: categories,
    ),
  );
  if (destinationUrl == null ||
      !context.mounted ||
      !controller.isTopicPostMoveTargetCurrent(target)) {
    return;
  }
  final absoluteDestination = controller.absoluteUrl(
    destinationUrl,
    siteUrl: target.siteUrl,
  );
  if (!controller.openTopicUrl(absoluteDestination)) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text("Couldn't open the destination topic.")),
    );
  }
}

enum _MoveMode { newTopic, existingTopic }

class _TopicMovePostsDialog extends StatefulWidget {
  const _TopicMovePostsDialog({
    required this.controller,
    required this.target,
    required this.topic,
    required this.selectedPosts,
    required this.categories,
  });

  final ShellController controller;
  final TopicPostMoveTarget target;
  final TopicDetail topic;
  final List<Post> selectedPosts;
  final List<TopicCategory> categories;

  @override
  State<_TopicMovePostsDialog> createState() => _TopicMovePostsDialogState();
}

class _TopicMovePostsDialogState extends State<_TopicMovePostsDialog> {
  final _title = TextEditingController();
  final _search = TextEditingController();
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  List<TopicMoveDestination> _destinations = const [];
  TopicMoveDestination? _destination;
  int? _categoryId;
  bool _chronologicalOrder = false;
  bool _searching = false;
  bool _saving = false;
  String? _error;

  bool get _canCreateNew {
    if (widget.selectedPosts.isEmpty ||
        widget.selectedPosts.length == widget.topic.stream.length) {
      return false;
    }
    return widget.selectedPosts.first.postType == Post.regularPostType;
  }

  late _MoveMode _mode = _canCreateNew
      ? _MoveMode.newTopic
      : _MoveMode.existingTopic;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _title.dispose();
    _search.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    setState(() {
      _destination = null;
      _error = null;
      if (value.trim().isEmpty) {
        _searching = false;
        _destinations = const [];
      } else {
        _searching = true;
      }
    });
    if (value.trim().isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final result = await widget.controller.searchTopicMoveDestinations(
        widget.target,
        value,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searching = false;
        _destinations = result.destinations;
        _error = result.error;
        if (_destinations.length == 1) _destination = _destinations.single;
      });
    });
  }

  Future<void> _move() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = switch (_mode) {
      _MoveMode.newTopic => await widget.controller.moveSelectedTopicPostsToNew(
        widget.target,
        title: _title.text,
        categoryId: _categoryId,
      ),
      _MoveMode.existingTopic =>
        await widget.controller.moveSelectedTopicPostsToExisting(
          widget.target,
          _destination!.id,
          chronologicalOrder: _chronologicalOrder,
        ),
    };
    if (!mounted) return;
    if (result.error case final error?) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(result.destinationUrl);
  }

  bool get _canSubmit =>
      !_saving &&
      switch (_mode) {
        _MoveMode.newTopic => _title.text.trim().isNotEmpty,
        _MoveMode.existingTopic => _destination != null,
      };

  @override
  Widget build(BuildContext context) {
    final count = widget.selectedPosts.length;
    return AlertDialog(
      key: const ValueKey('topic-move-posts-dialog'),
      title: const Text('Move posts'),
      content: SizedBox(
        width: 560,
        height: 430,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Move $count selected ${count == 1 ? 'post' : 'posts'}.'),
            const SizedBox(height: 12),
            SegmentedButton<_MoveMode>(
              key: const ValueKey('topic-move-posts-mode'),
              segments: [
                if (_canCreateNew)
                  const ButtonSegment(
                    value: _MoveMode.newTopic,
                    label: Text('New topic'),
                  ),
                const ButtonSegment(
                  value: _MoveMode.existingTopic,
                  label: Text('Existing topic'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _saving
                  ? null
                  : (selection) => setState(() {
                      _mode = selection.single;
                      _error = null;
                    }),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: switch (_mode) {
                _MoveMode.newTopic => _newTopicFields(),
                _MoveMode.existingTopic => _existingTopicFields(),
              },
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                key: const ValueKey('topic-move-posts-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        DButton(
          label: const Text('Cancel'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        DButton(
          key: const ValueKey('topic-move-posts-submit'),
          label: Text(
            _mode == _MoveMode.newTopic ? 'Create and move' : 'Move posts',
          ),
          onPressed: _canSubmit ? () => unawaited(_move()) : null,
          variant: DButtonVariant.primary,
          loading: _saving,
        ),
      ],
    );
  }

  Widget _newTopicFields() => ListView(
    children: [
      DInput(
        key: const ValueKey('topic-move-posts-title'),
        controller: _title,
        autofocus: true,
        enabled: !_saving,
        onChanged: (_) => setState(() => _error = null),
        labelText: 'Topic title',
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int?>(
        key: const ValueKey('topic-move-posts-category'),
        initialValue: _categoryId,
        decoration: const InputDecoration(
          labelText: 'Category',
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('Default category')),
          for (final category in widget.categories)
            DropdownMenuItem(
              value: category.id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CategoryIcon(
                    category: category,
                    siteUrl: widget.target.siteUrl,
                    size: 16,
                    squareSize: 11,
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: Text(category.name)),
                ],
              ),
            ),
        ],
        onChanged: _saving
            ? null
            : (value) => setState(() => _categoryId = value),
      ),
    ],
  );

  Widget _existingTopicFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DInput(
        key: const ValueKey('topic-move-posts-search'),
        controller: _search,
        autofocus: true,
        enabled: !_saving,
        onChanged: _scheduleSearch,
        labelText: 'Search by topic title or ID',
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _searching
            ? const Center(child: DSpinner(size: DSpacing.xl))
            : _destinations.isEmpty
            ? Center(
                child: Text(
                  _search.text.trim().isEmpty
                      ? 'Search for a destination topic.'
                      : 'No topics found.',
                ),
              )
            : DRadioGroup<TopicMoveDestination>.controlled(
                groupValue: _destination,
                enabled: !_saving,
                onChanged: _saving
                    ? (_) {}
                    : (value) => setState(() => _destination = value),
                child: ListView(
                  key: const ValueKey('topic-move-posts-results'),
                  children: [
                    for (final destination in _destinations)
                      DRadioGroupItem<TopicMoveDestination>(
                        key: ValueKey(
                          'topic-move-posts-destination-${destination.id}',
                        ),
                        value: destination,
                        label: Text(destination.title),
                        description: Text('Topic #${destination.id}'),
                      ),
                  ],
                ),
              ),
      ),
      CheckboxListTile(
        key: const ValueKey('topic-move-posts-chronological'),
        contentPadding: EdgeInsets.zero,
        value: _chronologicalOrder,
        onChanged: _saving
            ? null
            : (value) => setState(() => _chronologicalOrder = value ?? false),
        title: DLabel(
          enabled: !_saving,
          child: const Text('Preserve chronological order'),
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    ],
  );
}
