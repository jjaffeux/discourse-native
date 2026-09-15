import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/post.dart';
import '../models/topic.dart';
import 'shell_scope.dart';

enum TopicHeaderField { title, category, tags }

/// One explicit draft beneath the reading context. The header keys this lane
/// by topic, account and field, so a retired write cannot close a newer draft.
class TopicHeaderEditor extends StatefulWidget {
  const TopicHeaderEditor({
    super.key,
    required this.siteUrl,
    required this.topic,
    required this.field,
    required this.onClose,
  });

  final String siteUrl;
  final TopicDetail topic;
  final TopicHeaderField field;
  final VoidCallback onClose;

  @override
  State<TopicHeaderEditor> createState() => _TopicHeaderEditorState();
}

class _TopicHeaderEditorState extends State<TopicHeaderEditor> {
  final _titleFocus = FocusNode(debugLabel: 'Ledger title');
  late final _title = TextEditingController(text: widget.topic.title);
  late final _tagCategoryId = widget.topic.categoryId;
  late int? _categoryId = widget.topic.categoryId;
  late List<TopicTag> _tags = List.of(widget.topic.tags);
  TopicComposerCapabilities? _capabilities;
  bool _preparing = false;
  bool _saving = false;
  String? _error;

  bool get _allowed => switch (widget.field) {
    TopicHeaderField.title => widget.topic.canEdit,
    TopicHeaderField.category =>
      widget.topic.canEdit && !widget.topic.privateMessage,
    TopicHeaderField.tags => widget.topic.canEditTags,
  };

  @override
  void initState() {
    super.initState();
    if (widget.field == TopicHeaderField.title) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _titleFocus.requestFocus();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.field == TopicHeaderField.tags && !_preparing) {
      _preparing = true;
      unawaited(_prepareTags());
    }
  }

  Future<void> _prepareTags() async {
    final shell = ShellScope.read(context);
    final lease = shell.lifecycle.capture(widget.siteUrl);
    final capabilities = await shell.prepareTopicTagEditor(widget.siteUrl);
    if (!mounted ||
        !lease.isCurrent ||
        !identical(shell, ShellScope.read(context))) {
      return;
    }
    setState(() => _capabilities = capabilities);
  }

  Future<void> _save() async {
    if (_saving ||
        !_allowed ||
        widget.field == TopicHeaderField.category && _categoryId == null) {
      return;
    }
    final shell = ShellScope.read(context);
    final lease = shell.lifecycle.capture(widget.siteUrl);
    if (widget.field == TopicHeaderField.tags) {
      if (_capabilities == null) return;
      // Moving a topic can change which tags are allowed. Reopen against the
      // new category rather than submitting a draft from its old search scope.
      final current = shell.store.read<TopicDetail>(
        widget.siteUrl,
        widget.topic.id,
      );
      if (current?.categoryId != _tagCategoryId) {
        setState(
          () => _error =
              'The category changed. Reopen Edit tags to use its available tags.',
        );
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await switch (widget.field) {
      TopicHeaderField.title => shell.saveTopicTitle(
        siteUrl: widget.siteUrl,
        topicId: widget.topic.id,
        title: _title.text,
      ),
      TopicHeaderField.category => shell.saveTopicCategory(
        siteUrl: widget.siteUrl,
        topicId: widget.topic.id,
        categoryId: _categoryId!,
      ),
      TopicHeaderField.tags => shell.updateTopicTagsFromSidebar(
        siteUrl: widget.siteUrl,
        topicId: widget.topic.id,
        tags: _tags,
      ),
    };
    if (!mounted ||
        !lease.isCurrent ||
        !identical(shell, ShellScope.read(context))) {
      return;
    }
    if (error == null) {
      widget.onClose();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
      if (widget.field == TopicHeaderField.title) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _titleFocus.requestFocus();
        });
      }
    }
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final shell = ShellScope.read(context);
    final category = shell.categoryFor(_categoryId, siteUrl: widget.siteUrl);
    final editor = switch (field) {
      TopicHeaderField.title => Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter &&
              _title.value.composing.isCollapsed) {
            unawaited(_save());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DInput(
          key: const ValueKey('topic-header-title-field'),
          controller: _title,
          focusNode: _titleFocus,
          semanticLabel: 'Topic title',
          autofocus: true,
          enabled: !_saving && _allowed,
          onSubmitted: (_) => unawaited(_save()),
        ),
      ),
      TopicHeaderField.category => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TopicCategorySelector(
          key: const ValueKey('topic-header-category-field'),
          siteUrl: widget.siteUrl,
          categories: const [],
          selected: category,
          keyPrefix: 'topic-category-picker',
          placeholder: 'Choose category',
          labelFor: (category) =>
              shell.topicCategoryPathLabel(category, siteUrl: widget.siteUrl),
          search: (query) => shell.searchTopicCategoriesForEditor(
            siteUrl: widget.siteUrl,
            term: query,
          ),
          onSelected: !_allowed || _saving
              ? null
              : (category) => setState(() => _categoryId = category?.id),
        ),
      ),
      TopicHeaderField.tags =>
        _capabilities == null
            ? const Align(
                alignment: AlignmentDirectional.centerStart,
                child: DSpinner(semanticLabel: 'Loading tag permissions'),
              )
            : TopicTagSelector(
                key: ValueKey(_tagCategoryId),
                valueKey: const ValueKey('topic-header-tag-field'),
                keyPrefix: 'topic-tag-picker',
                selectedTags: _tags,
                showChips: true,
                capabilities: _capabilities!,
                search: (query) => shell.searchTopicTagsForEditor(
                  siteUrl: widget.siteUrl,
                  categoryId: _tagCategoryId,
                  selectedTags: _tags,
                  term: query,
                ),
                onChanged: !_allowed || _saving
                    ? null
                    : (tags) => setState(() => _tags = tags),
              ),
    };
    final cancel = DButton(
      key: const ValueKey('topic-header-cancel'),
      label: const Text('Cancel'),
      variant: DButtonVariant.ghost,
      size: DButtonSize.small,
      onPressed: _saving ? null : widget.onClose,
    );
    final save = DButton(
      key: const ValueKey('topic-header-save'),
      label: const Text('Save'),
      size: DButtonSize.small,
      loading: _saving,
      loadingSemanticLabel: 'Saving ${field.name}',
      onPressed:
          !_allowed ||
              _saving ||
              field == TopicHeaderField.tags && _capabilities == null ||
              field == TopicHeaderField.category && _categoryId == null
          ? null
          : () => unawaited(_save()),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_saving) widget.onClose();
        },
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_save()),
      },
      child: DecoratedBox(
        key: const ValueKey('topic-header-editor'),
        decoration: BoxDecoration(
          color: DTokens.of(context).muted.withValues(alpha: .35),
          border: Border(top: BorderSide(color: DTokens.of(context).border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_allowed) ...[
                const DFieldError(
                  child: Text('This field can no longer be edited.'),
                ),
                Align(alignment: AlignmentDirectional.centerEnd, child: cancel),
              ] else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow =
                        constraints.maxWidth <
                        540 * MediaQuery.textScalerOf(context).scale(12) / 12;
                    final label = Text(switch (field) {
                      TopicHeaderField.title => 'Title',
                      TopicHeaderField.category => 'Category',
                      TopicHeaderField.tags => 'Tags',
                    }, style: Theme.of(context).textTheme.labelMedium);
                    return narrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            spacing: DSpacing.sm,
                            children: [
                              label,
                              editor,
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                spacing: DSpacing.sm,
                                children: [cancel, save],
                              ),
                            ],
                          )
                        : Row(
                            spacing: DSpacing.sm,
                            children: [
                              label,
                              Expanded(child: editor),
                              cancel,
                              save,
                            ],
                          );
                  },
                ),
              if (_error != null) ...[
                const SizedBox(height: DSpacing.xs),
                DFieldError(errors: [_error]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
