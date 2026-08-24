import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/post.dart';
import '../models/post_flag.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'cooked_html.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

typedef PostFlagSaver =
    Future<String?> Function(PostFlagType type, {String? message});

/// Opens the reader-facing flag composer on the platform's compact surface.
Future<void> showPostFlagEditor({
  required BuildContext context,
  required String siteUrl,
  required Post post,
  required List<PostFlagType> flagTypes,
}) async {
  final controller = ShellScope.read(context);
  final minimum = controller
      .siteConfigFor(siteUrl)
      .minPersonalMessagePostLength;

  await showShellSheet<void>(
    context: context,
    title: 'Thanks for keeping our community civil!',
    dialogOnDesktop: true,
    builder: (sheetContext) => PostFlagEditor(
      siteUrl: siteUrl,
      post: post,
      flagTypes: flagTypes,
      minimumMessageLength: minimum,
      save: (type, {message}) =>
          controller.createPostFlag(siteUrl, post, type, message: message),
      onComplete: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

/// The stateful part of the flag composer, public so its validation and
/// accessibility behavior can be exercised without opening a route.
class PostFlagEditor extends StatefulWidget {
  const PostFlagEditor({
    super.key,
    required this.siteUrl,
    required this.post,
    required this.flagTypes,
    required this.minimumMessageLength,
    required this.save,
    required this.onComplete,
  });

  final String siteUrl;
  final Post post;
  final List<PostFlagType> flagTypes;
  final int minimumMessageLength;
  final PostFlagSaver save;
  final VoidCallback onComplete;

  @override
  State<PostFlagEditor> createState() => _PostFlagEditorState();
}

class _PostFlagEditorState extends State<PostFlagEditor> {
  final TextEditingController _message = TextEditingController();
  final FocusNode _messageFocus = FocusNode(debugLabel: 'Flag explanation');

  PostFlagType? _selected;
  bool _accurateAndComplete = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.flagTypes.length == 1) _selected = widget.flagTypes.single;
    _message.addListener(_messageChanged);
  }

  @override
  void dispose() {
    _message.removeListener(_messageChanged);
    _message.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  void _messageChanged() => setState(() {});

  bool get _messageValid {
    if (_selected?.requireMessage != true) return true;
    final length = _message.text.length;
    return length >= widget.minimumMessageLength &&
        length <= PostFlagType.maximumMessageLength;
  }

  bool get _valid =>
      _selected != null &&
      _messageValid &&
      (_selected?.isIllegal != true || _accurateAndComplete);

  void _select(PostFlagType? type) {
    if (_saving || type == null || type == _selected) return;
    final revealMessage =
        type.requireMessage && _selected?.requireMessage != true;
    setState(() => _selected = type);
    if (revealMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_saving) _messageFocus.requestFocus();
      });
    }
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (_saving || !_valid || selected == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final error = await widget.save(
      selected,
      message: selected.requireMessage ? _message.text : null,
    );
    if (!mounted) return;
    if (error == null) {
      setState(() => _saving = false);
      // PopScope still carries the saving lock until this rebuild lands. Pop
      // on the next frame so an authoritative success can close the route
      // without also weakening the lock while the request is in flight.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onComplete();
      });
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  String _title(PostFlagType type) => type.name
      .replaceAll('{{username}}', widget.post.username)
      .replaceAll('%{username}', widget.post.username);

  String _description(BuildContext context, PostFlagType type) {
    if (context.isTouch && type.shortDescription.isNotEmpty) {
      return type.shortDescription;
    }
    return type.description;
  }

  String get _messageLabel => switch (_selected?.nameKey) {
    'notify_user' => 'Message to @${widget.post.username}',
    'illegal' => 'Describe the illegal content',
    _ => 'Message to the moderators',
  };

  String get _messageHint => switch (_selected?.nameKey) {
    'notify_user' => 'Explain constructively how this post can be improved.',
    'illegal' => 'Explain precisely what is illegal about this post.',
    _ => 'Explain why this post needs moderator attention.',
  };

  String get _messageCounter {
    final length = _message.text.length;
    if (length < widget.minimumMessageLength) {
      return '${widget.minimumMessageLength - length} more required · '
          '${PostFlagType.maximumMessageLength - length} remaining';
    }
    return '${PostFlagType.maximumMessageLength - length} remaining';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;

    return PopScope(
      canPop: !_saving,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _submit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
        },
        child: FocusTraversalGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'All flags are received by moderators and will be reviewed '
                'as soon as possible.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              RadioGroup<PostFlagType>(
                groupValue: selected,
                onChanged: _saving ? (_) {} : _select,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final type in widget.flagTypes)
                      _FlagReasonRow(
                        key: ValueKey('post-flag-reason-${type.id}'),
                        type: type,
                        title: _title(type),
                        description: _description(context, type),
                        siteUrl: widget.siteUrl,
                        enabled: !_saving,
                        selected: selected == type,
                        onSelected: () => _select(type),
                      ),
                  ],
                ),
              ),
              if (selected?.requireMessage == true) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('post-flag-message'),
                  controller: _message,
                  focusNode: _messageFocus,
                  enabled: !_saving,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: PostFlagType.maximumMessageLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _messageLabel,
                    hintText: _messageHint,
                    alignLabelWithHint: true,
                    counterText: '',
                  ),
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _messageCounter,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _messageValid
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (selected?.isIllegal == true) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  key: const ValueKey('post-flag-illegal-confirmation'),
                  value: _accurateAndComplete,
                  enabled: !_saving,
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                          () => _accurateAndComplete = value == true,
                        ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'What I’ve written above is accurate and complete',
                  ),
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const ValueKey('post-flag-error'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey('post-flag-submit'),
                  onPressed: _valid && !_saving ? _submit : null,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const DIcon(DIcons.flag, size: 16),
                  label: Text(
                    selected?.requireMessage == true ? 'Message' : 'Flag Post',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlagReasonRow extends StatelessWidget {
  const _FlagReasonRow({
    super.key,
    required this.type,
    required this.title,
    required this.description,
    required this.siteUrl,
    required this.enabled,
    required this.selected,
    required this.onSelected,
  });

  final PostFlagType type;
  final String title;
  final String description;
  final String siteUrl;
  final bool enabled;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      checked: selected,
      enabled: enabled,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? onSelected : null,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Radio<PostFlagType>(
                    value: type,
                    enabled: enabled,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5, right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            CookedHtml(
                              html: description,
                              siteUrl: siteUrl,
                              textStyle: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              compactParagraphs: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
