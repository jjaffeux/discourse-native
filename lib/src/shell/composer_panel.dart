import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugins/poll/poll_composer_parser.dart';
import '../plugins/poll/poll_plugin.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'composer_controller.dart';
import 'composer_marks.dart';
import 'composer_suggestions.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';

/// The reply composer, docked under the post stream.
///
/// A panel rather than a sheet, which is the other thing the shell offers: on a
/// desktop the whole point of replying is to keep reading the topic while you
/// write about it, and a modal sheet takes the topic away.
///
/// What is typed here is what gets posted. Discourse stores raw markdown, so
/// the field's text *is* the payload — there is no document model in between to
/// normalise, escape or lose anything.
class ComposerPanel extends StatelessWidget {
  const ComposerPanel({super.key, required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);

    return ListenableBuilder(
      listenable: composer,
      builder: (context, _) {
        final target = composer.target;
        final error = composer.error;
        final notice = composer.notice;

        return Container(
          height: composerHeight,
          decoration: BoxDecoration(
            color: theme.shell.content,
            border: Border(top: BorderSide(color: theme.shell.divider)),
          ),
          child: CallbackShortcuts(
            bindings: {
              // Both, because the app runs on macOS and will run elsewhere.
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  controller.submitComposer,
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  controller.submitComposer,
              const SingleActivator(LogicalKeyboardKey.escape):
                  controller.closeComposer,
              // A bold button with no Cmd+B is a strange thing on a desktop.
              const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
                  composer.toggleMark(ComposerMark.bold),
              const SingleActivator(
                LogicalKeyboardKey.keyB,
                control: true,
              ): () =>
                  composer.toggleMark(ComposerMark.bold),
              const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
                  composer.toggleMark(ComposerMark.italic),
              const SingleActivator(
                LogicalKeyboardKey.keyI,
                control: true,
              ): () =>
                  composer.toggleMark(ComposerMark.italic),
            },
            child: Column(
              children: [
                _Header(target: target, onClose: controller.closeComposer),
                _Toolbar(composer: composer),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: _ComposerEditor(
                      composer: composer,
                      hintText: switch (target) {
                        _ when composer.loadingBody => 'Loading that post…',
                        _ when target.isEdit => 'Edit this post…',
                        _ when target.replyToUsername != null =>
                          'Reply to @${target.replyToUsername}…',
                        _ => 'Write a reply…',
                      },
                      textStyle: theme.textTheme.bodyMedium,
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                _Footer(
                  // Only ever says something when there is something to say.
                  // "Draft saved" every two seconds is noise; not being saved
                  // is worth interrupting for, because it changes what closing
                  // the composer costs.
                  message:
                      error?.message ??
                      notice ??
                      (composer.draftStatus == DraftStatus.failing ||
                              composer.draftsGaveUp
                          ? 'Not saved on the site — kept on this device only.'
                          : null),
                  isError: error != null,
                  busy:
                      composer.submitting ||
                      composer.state == ComposerState.checking ||
                      composer.loadingBody,
                  // After a failure that could not be checked, the button
                  // stops offering to send and offers to look instead.
                  label: switch (composer) {
                    _ when composer.canRecheck => 'Check again',
                    _ when target.isEdit => 'Save',
                    _ => 'Reply',
                  },
                  onSubmit: switch (composer) {
                    _ when composer.canRecheck => controller.recheckComposer,
                    _ when composer.canSubmit => controller.submitComposer,
                    _ => null,
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ComposerEditor extends StatefulWidget {
  const _ComposerEditor({
    required this.composer,
    required this.hintText,
    required this.textStyle,
    required this.hintStyle,
  });

  final ComposerController composer;
  final String hintText;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;

  @override
  State<_ComposerEditor> createState() => _ComposerEditorState();
}

class _ComposerEditorState extends State<_ComposerEditor> {
  static const _menuWidth = 88.0;
  static const _menuHeight = 44.0;
  static const _menuGap = 4.0;

  final GlobalKey _stackKey = GlobalKey();
  Offset? _pointerDown;
  PollComposerBlock? _hoveredPoll;
  Timer? _hideTimer;
  bool _menuHovered = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onHover(PointerHoverEvent event) {
    final block = widget.composer.text.collapsedPollAtGlobalPosition(
      event.position,
    );
    if (block != null) {
      _hideTimer?.cancel();
      if (_hoveredPoll?.start != block.start ||
          _hoveredPoll?.source != block.source) {
        setState(() => _hoveredPoll = block);
      }
      return;
    }
    if (!_menuHovered) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _menuHovered || _hoveredPoll == null) return;
      setState(() => _hoveredPoll = null);
    });
  }

  void _hideMenu() {
    _hideTimer?.cancel();
    _menuHovered = false;
    if (_hoveredPoll != null && mounted) {
      setState(() => _hoveredPoll = null);
    }
  }

  void _onFieldTap() {
    final pointer = _pointerDown;
    _pointerDown = null;
    if (pointer == null) return;
    final block = widget.composer.text.collapsedPollAtGlobalPosition(pointer);
    if (block == null) return;

    _hideMenu();
    widget.composer.text.expandPollAsRaw(block);
    widget.composer.focus.requestFocus();
  }

  void _editPoll() {
    final block = _hoveredPoll;
    if (block == null) return;
    _hideMenu();
    unawaited(openPollComposer(context, widget.composer, block: block));
  }

  void _removePoll() {
    final block = _hoveredPoll;
    if (block == null) return;
    _hideMenu();
    unawaited(removePollComposer(context, widget.composer, block));
  }

  (double, double)? _menuPosition(BoxConstraints constraints) {
    final block = _hoveredPoll;
    final stack = _stackKey.currentContext?.findRenderObject();
    final pillRect = block == null
        ? null
        : widget.composer.text.collapsedPollGlobalRect(block);
    if (stack is! RenderBox || !stack.hasSize || pillRect == null) return null;

    final pillTopLeft = stack.globalToLocal(pillRect.topLeft);
    final pillBottomRight = stack.globalToLocal(pillRect.bottomRight);
    final maxLeft = constraints.maxWidth > _menuWidth
        ? constraints.maxWidth - _menuWidth
        : 0.0;
    final left = pillTopLeft.dx.clamp(0.0, maxLeft);
    var top = pillTopLeft.dy - _menuHeight - _menuGap;
    if (top < 0) top = pillBottomRight.dy + _menuGap;
    final maxTop = constraints.maxHeight > _menuHeight
        ? constraints.maxHeight - _menuHeight
        : 0.0;
    return (left, top.clamp(0.0, maxTop));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final menuPosition = _menuPosition(constraints);
      return MouseRegion(
        onHover: _onHover,
        onExit: (_) => _scheduleHide(),
        child: Stack(
          key: _stackKey,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) => _pointerDown = event.position,
                child: ComposerSuggestionField(
                  composer: widget.composer,
                  field: TextField(
                    // Not decoration: a new key builds a new editable, and
                    // with it a new undo stack. It is the only way to stop undo
                    // reaching back into a reply that has already been sent.
                    key: ValueKey(widget.composer.fieldGeneration),
                    controller: widget.composer.text,
                    focusNode: widget.composer.focus,
                    autofocus: true,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    onTapAlwaysCalled: true,
                    onTap: _onFieldTap,
                    style: widget.textStyle,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hintText,
                      hintStyle: widget.hintStyle,
                    ),
                  ),
                ),
              ),
            ),
            if (menuPosition case (final left, final top))
              Positioned(
                left: left,
                top: top,
                child: MouseRegion(
                  onEnter: (_) {
                    _hideTimer?.cancel();
                    _menuHovered = true;
                  },
                  onExit: (_) {
                    _menuHovered = false;
                    _scheduleHide();
                  },
                  child: _PollComposerMenu(
                    onEdit: _editPoll,
                    onRemove: _removePoll,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _PollComposerMenu extends StatelessWidget {
  const _PollComposerMenu({required this.onEdit, required this.onRemove});

  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 4,
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: _ComposerEditorState._menuWidth,
        height: _ComposerEditorState._menuHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: onEdit,
              tooltip: 'Edit poll',
              visualDensity: VisualDensity.compact,
              icon: const DIcon(DIcons.pencil, size: 16),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove poll',
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.error,
              icon: const DIcon(DIcons.trashCan, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.target, required this.onClose});

  final ComposerTarget target;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replyTo = target.replyToUsername;

    return SizedBox(
      height: shellHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        child: Row(
          children: [
            DIcon(
              target.isEdit ? DIcons.pencil : DIcons.reply,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                switch ((target.editingPostNumber, replyTo)) {
                  (final number?, _) => 'Edit post #$number',
                  (_, final username?) => 'Reply to @$username',
                  _ => 'Reply to ${target.topicTitle}',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const DIcon(DIcons.xmark, size: 18),
              tooltip: 'Close composer',
            ),
          ],
        ),
      ),
    );
  }
}

/// The formatting actions.
///
/// One button per mark. What a mark means — which characters wrap the selection
/// — belongs in the composer, not in the button.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) => ShellSelector<bool>(
    // Plugin creation capabilities arrive independently of composer text.
    // Select the fresh Poll capability so an already-open composer gains (or
    // keeps hiding) its contributed action as soon as the session answers.
    select: (controller) =>
        controller.canCreatePollFor(composer.target.siteUrl),
    builder: (context, _, _) => _buildToolbar(context),
  );

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: Row(
        children: [
          for (final (mark, icon, label) in const [
            (ComposerMark.bold, DIcons.bold, 'Bold'),
            (ComposerMark.italic, DIcons.italic, 'Italic'),
          ])
            IconButton(
              onPressed: () => composer.toggleMark(mark),
              icon: DIcon(icon, size: 18),
              tooltip: '$label  ${_shortcutHint(label)}',
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          for (final plugin in sitePlugins)
            for (final action in plugin.composerToolbar(context, composer))
              IconButton(
                onPressed: action.onInvoke,
                icon: DIcon(action.icon, size: 18),
                tooltip: action.label,
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.onSurfaceVariant,
              ),
        ],
      ),
    );
  }

  static String _shortcutHint(String label) => label == 'Bold' ? '⌘B' : '⌘I';
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.message,
    required this.isError,
    required this.busy,
    required this.label,
    required this.onSubmit,
  });

  final String? message;
  final bool isError;
  final bool busy;
  final String label;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: message == null
                ? const SizedBox.shrink()
                : Text(
                    message!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isError
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            // Disabled while anything is in flight, because there is no way to
            // take a second post back.
            onPressed: busy ? null : onSubmit,
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label),
          ),
        ],
      ),
    );
  }
}
