import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
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
  final dialogKey = GlobalKey<_TopicMovePostsDialogState>();
  final destinationUrl = await showDDialog<String>(
    context: context,
    dismissOnBarrier: false,
    canDismiss: () => !(dialogKey.currentState?._saving ?? false),
    builder: (context, dialog) => _TopicMovePostsDialog(
      key: dialogKey,
      controller: controller,
      onClose: dialog.close,
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
    DToast.show(
      context,
      appL10n.couldnTOpenTheDestinationTopic,
      type: DToastType.error,
    );
  }
}

enum _MoveMode { newTopic, existingTopic }

class _TopicMovePostsDialog extends StatefulWidget {
  const _TopicMovePostsDialog({
    super.key,
    required this.controller,
    required this.onClose,
    required this.target,
    required this.topic,
    required this.selectedPosts,
    required this.categories,
  });

  final ShellController controller;
  final ValueChanged<String?> onClose;
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

  // A message's posts stay in messages: its destinations are other messages,
  // never a topic anyone can read.
  bool get _message => widget.target.privateMessage;

  bool get _canCreateNew {
    if (widget.selectedPosts.isEmpty ||
        widget.selectedPosts.length == widget.topic.stream.length ||
        (_message &&
            !widget.controller.canMoveTopicPostsToNewMessage(widget.target))) {
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
    if (!_canSubmit) return;
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
    _saving = false;
    widget.onClose(result.destinationUrl);
  }

  bool get _canSubmit =>
      !_saving &&
      switch (_mode) {
        _MoveMode.newTopic => _title.text.trim().isNotEmpty,
        _MoveMode.existingTopic =>
          !_searching &&
              _destination != null &&
              _destinations.contains(_destination),
      };

  @override
  Widget build(BuildContext context) {
    final count = widget.selectedPosts.length;
    return DDialogContent(
      key: const ValueKey('topic-move-posts-dialog'),
      semanticLabel: context.l10n.movePosts,
      showCloseButton: false,
      maxWidth: 608,
      children: [
        DDialogHeader(
          children: [
            DDialogTitle(child: Text(context.l10n.movePosts)),
            DDialogDescription(child: Text(context.l10n.moveSelected(count))),
          ],
        ),
        SizedBox(
          height: 430,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DToggleGroup<_MoveMode>(
                key: const ValueKey('topic-move-posts-mode'),
                items: [
                  if (_canCreateNew)
                    DToggleGroupItem(
                      value: _MoveMode.newTopic,
                      child: Text(
                        _message
                            ? context.l10n.newMessage
                            : context.l10n.newTopic,
                      ),
                    ),
                  DToggleGroupItem(
                    value: _MoveMode.existingTopic,
                    child: Text(
                      _message
                          ? context.l10n.existingMessage
                          : context.l10n.existingTopic,
                    ),
                  ),
                ],
                values: [_mode],
                allowEmptySelection: false,
                variant: DToggleVariant.outline,
                spacing: 0,
                onChanged: _saving
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
              if (_error case final error?)
                DAlert(
                  key: const ValueKey('topic-move-posts-error'),
                  variant: DAlertVariant.destructive,
                  description: DAlertDescription(child: Text(error)),
                ),
            ],
          ),
        ),
        DDialogFooter(
          children: [
            DButton(
              label: Text(context.l10n.cancel),
              onPressed: _saving ? null : () => widget.onClose(null),
              variant: DButtonVariant.outline,
            ),
            DButton(
              key: const ValueKey('topic-move-posts-submit'),
              label: Text(
                _mode == _MoveMode.newTopic
                    ? context.l10n.createAndMove
                    : context.l10n.movePosts,
              ),
              onPressed: _canSubmit ? () => unawaited(_move()) : null,
              variant: DButtonVariant.primary,
              loading: _saving,
            ),
          ],
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
        labelText: _message ? appL10n.messageTitle : appL10n.topicTitle,
      ),
      if (!_message) ...[
        const SizedBox(height: 16),
        DSelect<int>.controlled(
          key: const ValueKey('topic-move-posts-category'),
          value: _categoryId,
          label: Text(appL10n.category),
          isExpanded: true,
          enabled: !_saving,
          entries: [
            DSelectItem<int>(
              value: null,
              textValue: appL10n.defaultCategory,
              child: Text(appL10n.defaultCategory),
            ),
            for (final category in widget.categories)
              DSelectItem(
                value: category.id,
                textValue: category.name,
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
        labelText: _message
            ? appL10n.searchByMessageTitleOrID
            : appL10n.searchByTopicTitleOrID,
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _searching
            ? const SizedBox.shrink()
            : _destinations.isEmpty
            ? Center(
                child: Text(switch ((_search.text.trim().isEmpty, _message)) {
                  (true, false) => appL10n.searchForADestinationTopic,
                  (true, true) => appL10n.searchForADestinationMessage,
                  (false, false) => appL10n.noTopicsFound,
                  (false, true) => appL10n.noMessagesFound,
                }),
              )
            : DRadioGroup<TopicMoveDestination>.controlled(
                groupValue: _destination,
                enabled: !_saving,
                onChanged: (value) {
                  // A query edit can retire a row before the next frame hides it.
                  if (_saving || _searching || !_destinations.contains(value)) {
                    return;
                  }
                  setState(() => _destination = value);
                },
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
                        description: Text(
                          appL10n.messageTopicmovepostsValue(
                            (_message).toString(),
                            ((_message) ? (appL10n.messageTopicmoveposts) : '')
                                .toString(),
                            (destination.id).toString(),
                            ((!(_message)) ? (appL10n.topic) : '').toString(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      DCheckbox(
        key: const ValueKey('topic-move-posts-chronological'),
        contentPadding: EdgeInsets.zero,
        value: _chronologicalOrder,
        onChanged: _saving
            ? null
            : (value) => setState(() => _chronologicalOrder = value ?? false),
        title: DLabel(child: Text(appL10n.preserveChronologicalOrder)),
      ),
    ],
  );
}
