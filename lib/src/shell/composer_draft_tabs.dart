import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'composer_controller.dart';
import 'composer_discard.dart';
import 'composer_presentation.dart';
import 'shell_scope.dart';

String composerDraftLabel(ComposerController composer) =>
    composer.target.createsTopic
    ? (composer.title.text.trim().isEmpty
          ? composer.target.topicTitle
          : composer.title.text.trim())
    : composer.target.topicTitle;

/// Open draft tabs borrow the live, account-scoped editors from the shell.
class ComposerDraftTabs extends StatefulWidget {
  const ComposerDraftTabs({super.key, required this.composer});
  final ComposerController composer;
  @override
  State<ComposerDraftTabs> createState() => _ComposerDraftTabsState();
}

class _ComposerDraftTabsState extends State<ComposerDraftTabs> {
  final _tabKeys = <ComposerController, GlobalKey>{};
  ComposerController get composer => widget.composer;
  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    return ListenableBuilder(
      listenable: Listenable.merge([shell, shell.draftList]),
      builder: (context, _) {
        final site = composer.target.siteUrl;
        final drafts = shell.liveComposers
            .where((c) => c.target.siteUrl == site && c.canSaveDraft)
            .toList();
        _tabKeys.removeWhere((draft, _) => !drafts.contains(draft));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _tabKeys[composer]?.currentContext;
          if (mounted && target != null) {
            unawaited(
              Scrollable.ensureVisible(
                target,
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              ),
            );
          }
        });
        final instance = shell.currentInstance;
        final feed = shell.draftList.feedFor(site);
        return Row(
          children: [
            DDropdownMenu(
              onOpenChange: (open, _) {
                if (open && instance?.url == site) {
                  unawaited(shell.draftList.load(instance!, refresh: true));
                }
              },
              content: DDropdownMenuContent(
                semanticLabel: context.l10n.allDrafts,
                children: [
                  for (final draft in drafts)
                    DDropdownMenuItem(
                      leading: const DIcon(DIcons.pen),
                      onPressed: () => shell.selectComposer(draft),
                      child: Text(composerDraftLabel(draft)),
                    ),
                  for (final draft in feed.drafts.where(
                    (d) => !drafts.any((c) => c.target.draftKey == d.key),
                  ))
                    DDropdownMenuItem(
                      onPressed: draft.canResume
                          ? () => unawaited(shell.resumeDraft(site, draft))
                          : null,
                      child: Text(draft.displayTitle),
                    ),
                  if (feed.loading)
                    DDropdownMenuLabel(
                      child: Text(context.l10n.loadingDraftsTopiccreatebutton),
                    ),
                  if (feed.error != null)
                    DDropdownMenuItem(
                      onPressed: () => unawaited(
                        shell.draftList.load(instance!, refresh: true),
                      ),
                      child: Text(context.l10n.couldnTLoadDrafts),
                    ),
                  const DDropdownMenuSeparator(),
                  DDropdownMenuItem(
                    onPressed: () {
                      ComposerPresentationHost.redockForNavigation(context);
                      shell.openDrafts(site);
                    },
                    child: Text(context.l10n.allDrafts),
                  ),
                ],
              ),
              child: DDropdownMenuTrigger(
                builder: (context, trigger) => DButton.iconOnly(
                  key: const ValueKey('composer-all-drafts'),
                  icon: const DIcon(DIcons.chevronDown),
                  tooltip: context.l10n.allDrafts,
                  hasPopup: true,
                  expanded: trigger.open,
                  focusNode: trigger.focusNode,
                  size: DControlSize.toolbar,
                  shape: DButtonShape.pill,
                  variant: DButtonVariant.ghost,
                  onPressed: trigger.toggle,
                ),
              ),
            ),
            const SizedBox(width: DSpacing.controlGap),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 6,
                  children: [
                    for (final draft in drafts)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: DDocumentTab(
                          key: _tabKeys.putIfAbsent(draft, GlobalKey.new),
                          selected: identical(draft, composer),
                          size: DControlSize.documentTab,
                          onSelect: () => shell.selectComposer(draft),
                          onClose: () => unawaited(
                            saveComposerFromPanel(
                              context: context,
                              composer: draft,
                              controller: shell,
                            ),
                          ),
                          closeLabel: context.l10n.saveAndClose,
                          closeKey: ValueKey(('composer-draft-close', draft)),
                          child: Text(
                            composerDraftLabel(draft),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
