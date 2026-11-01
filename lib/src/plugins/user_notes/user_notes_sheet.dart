import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'user_notes_controller.dart';
import 'user_notes_data.dart';

Future<void> showUserNotes({
  required BuildContext context,
  required UserNotesController controller,
  required String siteUrl,
  required int userId,
  String? username,
  int? postId,
}) async {
  if (!controller.canOpen(siteUrl)) return;
  final reader = controller.open(
    siteUrl: siteUrl,
    userId: userId,
    username: username,
    postId: postId,
  );
  try {
    if (context.isTouch) {
      await showDSheet<void>(
        context: context,
        side: DSheetSide.bottom,
        fillAvailableHeight: true,
        builder: (context, dialog) => DSheetContent(
          side: DSheetSide.bottom,
          fillAvailableHeight: true,
          scrollWholeSheet: false,
          semanticLabel: context.l10n.userNotesTitle,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 44, 20, 20),
                child: UserNotesPanel(session: reader, onClose: dialog.close),
              ),
            ),
          ],
        ),
      );
    } else {
      await showDDialog<void>(
        context: context,
        builder: (context, dialog) => DDialogContent(
          maxWidth: 640,
          maxHeight: 720,
          semanticLabel: context.l10n.userNotesTitle,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(top: DSpacing.xl),
                child: UserNotesPanel(session: reader, onClose: dialog.close),
              ),
            ),
          ],
        ),
      );
    }
  } finally {
    reader.close();
  }
}

class UserNotesPanel extends StatefulWidget {
  const UserNotesPanel({
    super.key,
    required this.session,
    required this.onClose,
  });
  final UserNotesSession session;
  final VoidCallback onClose;
  @override
  State<UserNotesPanel> createState() => _UserNotesPanelState();
}

class _UserNotesPanelState extends State<UserNotesPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  void _changed() {
    if (!widget.session.isCurrent) {
      _input.clear();
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onClose();
        });
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _input.text;
    if (await widget.session.add(text) &&
        mounted &&
        widget.session.isCurrent &&
        _input.text == text) {
      _input.clear();
      setState(() {});
    }
  }

  Future<void> _remove(UserNote note) async {
    final confirmed = await showDAlertDialog<bool>(
      context: context,
      builder: (context, dialog) => DAlertDialogContent(
        children: [
          DAlertDialogHeader(
            title: DAlertDialogTitle(child: Text(context.l10n.userNotesRemove)),
            description: DAlertDialogDescription(
              child: Text(context.l10n.userNotesDeleteConfirm),
            ),
          ),
          DAlertDialogFooter(
            children: [
              DAlertDialogCancel<bool>(
                label: Text(context.l10n.userNotesCancel),
              ),
              DButton(
                label: Text(context.l10n.userNotesRemove),
                variant: DButtonVariant.destructive,
                onPressed: () => dialog.close(true),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && widget.session.isCurrent) {
      await widget.session.remove(note.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session, l10n = context.l10n;
    if (!session.isCurrent) return const SizedBox.shrink();
    final ready = session.status == UserNotesReadStatus.ready;
    final editable = ready && !session.writing && !session.uncertain;
    final problem = session.failure;
    return DScrollBar(
      controller: _scroll,
      child: DPullToRefresh(
        onRefresh: session.writing ? null : session.refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DSpacing.lg,
                children: [
                  DTextarea(
                    controller: _input,
                    enabled: editable,
                    semanticLabel: l10n.userNotesField,
                    hintText: l10n.userNotesHint,
                    minLines: 3,
                    maxLines: 8,
                    onChanged: (_) => setState(() {}),
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: DSpacing.md,
                    runSpacing: DSpacing.sm,
                    children: [
                      if (session.postId case final id?)
                        DText(
                          l10n.userNotesLinkedPost(id),
                          variant: DTextVariant.muted,
                        ),
                      DButton(
                        label: Text(l10n.userNotesAdd),
                        loading: session.writing,
                        onPressed: editable && _input.text.trim().isNotEmpty
                            ? () => unawaited(_add())
                            : null,
                      ),
                    ],
                  ),
                  if (problem != null)
                    DAlert(
                      variant: DAlertVariant.destructive,
                      title: DAlertTitle(
                        child: Text(
                          session.status == UserNotesReadStatus.failed
                              ? l10n.userNotesLoadError
                              : l10n.userNotesWriteError,
                        ),
                      ),
                      description: DAlertDescription(
                        child: Text(
                          session.serverError ??
                              switch (problem) {
                                UserNotesFailure.blank => l10n.userNotesBlank,
                                UserNotesFailure.tooLong =>
                                  l10n.userNotesTooLong,
                                UserNotesFailure.uncertain =>
                                  l10n.userNotesUncertain,
                                _ => l10n.userNotesLoadError,
                              },
                        ),
                      ),
                    ),
                  if (session.status == UserNotesReadStatus.loading) ...[
                    DSpinner(semanticLabel: l10n.userNotesLoading),
                    const DSkeleton(height: 64),
                  ],
                  if (ready && session.notes.isEmpty)
                    DEmpty(
                      children: [
                        DEmptyHeader(
                          children: [
                            DEmptyTitle(l10n.userNotesEmpty),
                            DEmptyDescription(l10n.userNotesEmptyDescription),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (ready)
              SliverPadding(
                padding: const EdgeInsets.only(top: DSpacing.lg),
                sliver: SliverList.builder(
                  itemCount: session.notes.length,
                  itemBuilder: (context, index) {
                    final note = session.notes[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: DSpacing.lg),
                      child: UserNoteView(
                        key: ValueKey(note.id),
                        note: note,
                        session: session,
                        onRemove:
                            note.canDelete &&
                                !session.writing &&
                                !session.uncertain
                            ? () => unawaited(_remove(note))
                            : null,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class UserNoteView extends StatefulWidget {
  const UserNoteView({
    super.key,
    required this.note,
    required this.session,
    this.onRemove,
  });
  final UserNote note;
  final UserNotesSession session;
  final VoidCallback? onRemove;
  @override
  State<UserNoteView> createState() => _UserNoteViewState();
}

class _UserNoteViewState extends State<UserNoteView> {
  String? _html;
  bool _fallback = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_cook());
  }

  @override
  void didUpdateWidget(UserNoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.raw != widget.note.raw ||
        oldWidget.session != widget.session) {
      unawaited(_cook());
    }
  }

  Future<void> _cook() async {
    final revision = ++_revision, session = widget.session;
    _html = null;
    _fallback = false;
    if (widget.note.raw.length > 65536) {
      _fallback = true;
      return;
    }
    try {
      final cooking = session.controller.cooking;
      final request = cooking.request(
        siteUrl: session.siteUrl,
        raw: widget.note.raw,
      );
      final result = await cooking.cookTransient(
        request,
        abortTrigger: session.aborted,
      );
      if (!mounted || revision != _revision || !session.isCurrent) return;
      setState(() {
        _fallback = result.failure != null || !cooking.isCurrent(request);
        _html = _fallback ? null : result.html;
      });
    } catch (_) {
      if (mounted && revision == _revision && session.isCurrent) {
        setState(() => _fallback = true);
      }
    }
  }

  void _open(String path) {
    if (!widget.session.isCurrent) return;
    final site = DiscourseInstance.urlServes(
      widget.session.siteUrl,
      Uri.tryParse(path) ?? Uri(),
    );
    final target = path.startsWith('/')
        ? '${Uri.parse(widget.session.siteUrl).origin}$path'
        : path;
    final uri = Uri.tryParse(target);
    if (uri == null ||
        !(site || DiscourseInstance.urlServes(widget.session.siteUrl, uri))) {
      return;
    }
    unawaited(openLink(context, target));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.isCurrent) return const SizedBox.shrink();
    final note = widget.note, author = widget.note.author, l10n = context.l10n;
    final authorName = author?.username ?? l10n.userNotesUnknownAuthor;
    final avatar = DAvatar(
      fallback: DAvatarFallback(
        child: Text(authorName.characters.first.toUpperCase()),
      ),
      child: author?.avatarTemplate == null
          ? null
          : AvatarImage(
              url: resolveAvatarUrl(
                author!.avatarTemplate,
                widget.session.siteUrl,
              ),
              size: 32,
              fallback: DAvatarFallback(
                child: Text(authorName.characters.first.toUpperCase()),
              ),
            ),
    );
    Widget identity = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DSpacing.sm,
      children: [
        avatar,
        Flexible(child: Text(authorName)),
      ],
    );
    if (author != null) {
      identity = UserCardTarget(
        username: author.username,
        siteUrl: widget.session.siteUrl,
        child: identity,
      );
    }
    return DCard(
      size: DCardSize.small,
      children: [
        DCardContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DSpacing.md,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: identity,
                    ),
                  ),
                  DTooltip(
                    message: DateFormat.yMMMMd().add_jm().format(
                      note.createdAt.toLocal(),
                    ),
                    child: RelativeTimeText(note.createdAt),
                  ),
                  if (note.canDelete)
                    DButton.iconOnly(
                      icon: const DIcon(DIcons.trashCan),
                      tooltip: l10n.userNotesRemove,
                      variant: DButtonVariant.ghost,
                      onPressed: widget.onRemove,
                    ),
                ],
              ),
              if (_fallback) ...[
                DText(l10n.userNotesUnformatted, variant: DTextVariant.muted),
                SelectionArea(child: DText(note.raw)),
                if (widget.session.username case final username?)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DButton(
                      label: Text(l10n.userNotesOnWeb),
                      variant: DButtonVariant.link,
                      onPressed: () => unawaited(
                        openExternalLink(
                          '${widget.session.siteUrl}/u/${Uri.encodeComponent(username)}',
                        ),
                      ),
                    ),
                  ),
              ] else if (_html case final html?)
                CookedHtml(
                  html: html,
                  siteUrl: widget.session.siteUrl,
                  contentSized: true,
                  transient: true,
                )
              else
                const DSkeleton(height: 48),
              Wrap(
                spacing: DSpacing.sm,
                runSpacing: DSpacing.sm,
                children: [
                  if (note.post case final post?)
                    DButton(
                      label: Text(l10n.userNotesShowPost),
                      variant: DButtonVariant.outline,
                      size: DButtonSize.small,
                      onPressed: () => _open(post.url),
                    ),
                  if (note.reviewableId case final id?)
                    DButton(
                      label: Text(l10n.userNotesShowFlag),
                      variant: DButtonVariant.outline,
                      size: DButtonSize.small,
                      onPressed: () => unawaited(
                        openExternalLink(
                          '${widget.session.siteUrl}/review/$id',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
