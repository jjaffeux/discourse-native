import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'composer_controller.dart';
import 'composer_marks.dart';
import 'rich_composer_field.dart';
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
    final controller = ShellScope.of(context);

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
                _Header(
                  target: target,
                  mode: composer.mode,
                  // Offered only for text a document model returns unchanged.
                  // Refusing is the feature: the alternative is silently
                  // rewriting someone's post.
                  onToggleMode:
                      composer.mode == ComposerMode.rich ||
                          composer.canUseRichMode
                      ? composer.toggleMode
                      : null,
                  onClose: controller.closeComposer,
                ),
                _Toolbar(composer: composer),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: composer.mode == ComposerMode.rich
                        ? RichComposerField(composer: composer)
                        : TextField(
                            controller: composer.text,
                            focusNode: composer.focus,
                            autofocus: true,
                            // The three together are what fills a bounded box;
                            // `maxLines: null` alone grows from one line instead.
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences,
                            style: theme.textTheme.bodyMedium,
                            decoration: InputDecoration.collapsed(
                              hintText: switch (target) {
                                _ when composer.loadingBody =>
                                  'Loading that post…',
                                _ when target.isEdit => 'Edit this post…',
                                _ when target.replyToUsername != null =>
                                  'Reply to @${target.replyToUsername}…',
                                _ => 'Write a reply…',
                              },
                              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.target,
    required this.mode,
    required this.onToggleMode,
    required this.onClose,
  });

  final ComposerTarget target;
  final ComposerMode mode;
  final VoidCallback? onToggleMode;
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
              onPressed: onToggleMode,
              // The pair Discourse puts on its own composer toggle switch: the
              // markdown mark for the raw side, a letter A for the rich one.
              icon: DIcon(
                mode == ComposerMode.rich ? DIcons.fabMarkdown : DIcons.a,
                size: 18,
              ),
              tooltip: switch ((mode, onToggleMode)) {
                (ComposerMode.rich, _) => 'Edit the markdown',
                (_, null) => 'Rich editing is not available for this post',
                _ => 'Edit richly',
              },
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
/// One button per mark, whichever surface is showing — the difference between
/// wrapping text in `**` and applying an attribution belongs in the composer,
/// not in the button.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) {
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
