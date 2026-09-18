import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../models/user_draft.dart';
import '../theme/d_icons.dart';
import 'composer_controller.dart';
import 'shell_scope.dart';

/// A preview of the server's latest drafts, loaded when a composer opens.
class ComposerRecentDrafts extends StatefulWidget {
  const ComposerRecentDrafts({
    super.key,
    required this.composer,
    required this.heading,
  });

  final ComposerController composer;
  final Widget heading;

  @override
  State<ComposerRecentDrafts> createState() => _ComposerRecentDraftsState();
}

class _ComposerRecentDraftsState extends State<ComposerRecentDrafts> {
  bool _switching = false;

  Future<void> _resume(UserDraft draft) async {
    final shell = ShellScope.read(context);
    final composer = widget.composer;
    if (_switching || !identical(shell.visibleComposer, composer)) return;
    setState(() => _switching = true);
    try {
      await shell.resumeDraft(
        composer.target.siteUrl,
        draft,
        sourceIsCurrent: () =>
            !composer.isDisposed &&
            composer.isEditing &&
            !composer.discarding &&
            identical(shell.visibleComposer, composer),
      );
    } catch (_) {
      if (!composer.isDisposed) {
        composer.showNotice("Couldn't open that draft. Try again.");
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.identityOf(context);
    final controller = shell.recentComposerDrafts;
    final composer = widget.composer;
    if (!composer.canSaveDraft) return widget.heading;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final siteUrl = composer.target.siteUrl;
        final feed = controller.feedFor(siteUrl);
        final drafts = feed.drafts
            .take(5)
            .where((draft) => draft.key != composer.target.draftKey);
        return Row(
          key: const ValueKey('composer-recent-drafts'),
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            widget.heading,
            for (final draft in drafts)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: DButton(
                  key: ValueKey('composer-recent-draft-${draft.key}'),
                  variant: DButtonVariant.transparentBackground,
                  icon: DIcon(
                    draft.isNewTopic ? DIcons.layerGroup : DIcons.reply,
                  ),
                  label: Text(
                    draft.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  tooltip: draft.canResume
                      ? '${draft.kindLabel}: ${draft.displayTitle}'
                      : '${draft.displayTitle} — this draft cannot be resumed in the app',
                  onPressed:
                      draft.canResume &&
                          !_switching &&
                          composer.isEditing &&
                          !composer.loadingBody &&
                          !composer.discarding &&
                          !composer.hasActiveUploads
                      ? () => unawaited(_resume(draft))
                      : null,
                ),
              ),
            if (feed.loading)
              const DSpinner(size: 14, semanticLabel: 'Loading recent drafts'),
            if (feed.error != null)
              DButton(
                key: const ValueKey('composer-retry-drafts'),
                variant: DButtonVariant.transparentBackground,
                label: const Text('Retry drafts'),
                tooltip: feed.error,
                onPressed: () {
                  final instance = shell.instanceFor(siteUrl);
                  if (instance != null) {
                    unawaited(controller.load(instance, refresh: true));
                  }
                },
              ),
          ],
        );
      },
    );
  }
}
