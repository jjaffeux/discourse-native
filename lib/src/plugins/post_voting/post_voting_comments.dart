import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'post_voting_actions.dart';
import 'post_voting_comment_flags.dart';
import 'post_voting_controller.dart';
import 'post_voting_data.dart';
import 'post_voting_services.dart';

class PostVotingComments extends StatefulWidget {
  const PostVotingComments({
    super.key,
    required this.services,
    required this.siteUrl,
    required this.topicId,
    required this.postId,
  });
  final PostVotingServices services;
  final String siteUrl;
  final int topicId;
  final int postId;
  @override
  State<PostVotingComments> createState() => _PostVotingCommentsState();
}

class _PostVotingCommentsState extends State<PostVotingComments> {
  PluginTopicReader? _reader;
  final _text = TextEditingController(), _focus = FocusNode();
  final Map<int, GlobalKey> _commentKeys = {};
  bool _editing = false,
      _loading = false,
      _allLoaded = false,
      _anchorResolved = false;
  int? _editId;
  int _generation = 0;
  final Map<int, bool> _voteIntents = {};
  bool? _voted(PostVotingComment comment) =>
      _voteIntents[comment.id] ?? comment.myUpvote;
  int _score(PostVotingComment comment) {
    final desired = _voteIntents[comment.id];
    return desired == null || desired == comment.myUpvote
        ? comment.score
        : comment.score + (desired ? 1 : -1);
  }

  Object? _error;
  bool _anchorUnavailable = false;
  List<PostVotingComment> get _comments =>
      widget.services.actions
          .record(widget.siteUrl, widget.postId)
          ?.initialComments ??
      const [];
  int get _count =>
      widget.services.actions
          .record(widget.siteUrl, widget.postId)
          ?.commentsCount ??
      0;
  @override
  void initState() {
    super.initState();
    _reader = widget.services.readers.forVisibleTopic(
      widget.siteUrl,
      widget.topicId,
    )?..addListener(_changed);
    widget.services.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveAnchor());
  }

  void _changed() {
    if (mounted) {
      setState(() {});
      _resolveAnchor();
    }
  }

  bool get _current =>
      mounted &&
      _reader?.isCurrent == true &&
      widget.services.settingsFor(widget.siteUrl).commentsEnabled;
  bool get _closed =>
      _reader?.topic?.closed == true || _reader?.topic?.archived == true;
  bool get _canCreate =>
      _current &&
      !_closed &&
      _reader?.currentUserId != null &&
      _reader?.topic?.canCreatePost == true &&
      _count < widget.services.settingsFor(widget.siteUrl).commentLimitPerPost;

  Future<void> _remainder() async {
    final reader = _reader;
    if (!_current || reader == null || _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final held = _comments;
      final cursor = held.isEmpty ? 0 : held.last.id;
      final batch = await widget.services.actions.loadComments(
        reader,
        widget.postId,
        afterId: cursor,
      );
      if (!_current || generation != _generation || batch == null) return;
      final values = {
        for (final item in held) item.id: item,
        for (final item in batch.comments) item.id: item,
      };
      final comments = values.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      widget.services.actions.publishComments(
        reader,
        widget.postId,
        comments,
        total: comments.length,
      );
      _allLoaded = true;
    } catch (error) {
      if (_current && generation == _generation) _error = error;
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open([PostVotingComment? comment]) async {
    if (!_current ||
        _loading ||
        (comment == null ? !_canCreate : !_canEdit(comment))) {
      return;
    }
    if (!_allLoaded && _comments.length < _count) await _remainder();
    if (!_current) return;
    setState(() {
      _editing = true;
      _editId = comment?.id;
      _text.text = comment?.raw ?? '';
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current) _focus.requestFocus();
    });
  }

  String? get _lengthError {
    final settings = widget.services.settingsFor(widget.siteUrl),
        length = _text.text.trim().runes.length;
    if (length < settings.commentMinRawLength) {
      return context.l10n.postVotingCommentTooShort;
    }
    if (length > settings.commentMaxRawLength) {
      return context.l10n.postVotingCommentTooLong;
    }
    return null;
  }

  Future<void> _save() async {
    final reader = _reader;
    if (!_current || reader == null || _lengthError != null) return;
    if (_editId == null && !_canCreate) return;
    final raw = _text.text;
    final editing = _editId;
    if (editing != null) {
      final comment = _comments
          .where((entry) => entry.id == editing)
          .firstOrNull;
      if (comment == null || !_canEdit(comment)) return;
    }
    final result = await widget.services.actions.mutateComment(
      reader: reader,
      postId: widget.postId,
      send: (credentials) => editing == null
          ? widget.services.api.createComment(
              siteUrl: widget.siteUrl,
              postId: widget.postId,
              raw: raw,
              credentials: credentials,
            )
          : widget.services.api.editComment(
              siteUrl: widget.siteUrl,
              parentPostId: widget.postId,
              commentId: editing,
              raw: raw,
              credentials: credentials,
            ),
    );
    if (!_current) return;
    setState(() {
      _error = result.error;
      if (result.accepted) {
        _editing = false;
        _editId = null;
        _text.clear();
        _allLoaded = true;
      }
    });
  }

  bool _canEdit(PostVotingComment comment) =>
      _reader?.currentUserId != null &&
      (_reader!.currentUserStaff ||
          !_closed &&
              comment.authorId == _reader!.currentUserId &&
              _reader!.topic?.canCreatePost == true);
  bool _canDelete(PostVotingComment comment) =>
      _reader?.currentUserId != null &&
      (_reader!.currentUserStaff ||
          !_closed && comment.authorId == _reader!.currentUserId);
  bool _canFlag(PostVotingComment comment) =>
      (!_closed || _reader?.currentUserStaff == true) &&
      comment.authorId != null &&
      comment.authorId != _reader?.currentUserId &&
      (comment.availableFlags.isNotEmpty ||
          widget.services.settingsFor(widget.siteUrl).dsaReportingEnabled &&
              widget.services.canFlag(widget.siteUrl));
  Future<void> _delete(PostVotingComment comment) async {
    if (!_current || !_canDelete(comment)) return;
    final confirmed = await showDAlertDialog<bool>(
      context: context,
      builder: (context, dialog) => DAlertDialogContent(
        children: [
          DAlertDialogTitle(
            child: Text(context.l10n.postVotingConfirmDeleteComment),
          ),
          DAlertDialogFooter(
            children: [
              DButton(
                variant: DButtonVariant.ghost,
                label: Text(context.l10n.cancel),
                onPressed: () => dialog.close(false),
              ),
              DButton(
                variant: DButtonVariant.destructive,
                label: Text(context.l10n.delete),
                onPressed: () => dialog.close(true),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !_current || !_canDelete(comment)) return;
    final result = await widget.services.actions.mutateComment(
      reader: _reader!,
      postId: widget.postId,
      send: (credentials) async {
        await widget.services.api.deleteComment(
          siteUrl: widget.siteUrl,
          commentId: comment.id,
          credentials: credentials,
        );
        return null;
      },
    );
    if (_current) setState(() => _error = result.error);
  }

  Future<void> _vote(PostVotingComment comment) async {
    final reader = _reader;
    if (!_current ||
        _closed ||
        reader == null ||
        reader.currentUserId == null ||
        comment.authorId == reader.currentUserId ||
        comment.myUpvote == null) {
      return;
    }
    setState(() => _voteIntents[comment.id] = comment.myUpvote != true);
    final result = await widget.services.actions.mutateComment(
      reader: reader,
      postId: widget.postId,
      send: (credentials) async {
        if (comment.myUpvote == true) {
          await widget.services.api.undoCommentVote(
            siteUrl: widget.siteUrl,
            commentId: comment.id,
            credentials: credentials,
          );
        } else {
          await widget.services.api.upvoteComment(
            siteUrl: widget.siteUrl,
            commentId: comment.id,
            credentials: credentials,
          );
        }
        return null;
      },
    );
    if (_current) {
      setState(() {
        _voteIntents.remove(comment.id);
        _error = result.error;
      });
    }
  }

  void _resolveAnchor() {
    if (!_current || _anchorResolved || _loading) return;
    final target = int.tryParse(
      postVotingQuery(_reader?.route.topicQuery)['post-voting-comment'] ?? '',
    );
    if (target == null || target <= 0) return;
    if (_comments.any((item) => item.id == target)) {
      _anchorResolved = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _commentKeys[target]?.currentContext;
        if (_current && context != null) {
          unawaited(Scrollable.ensureVisible(context, alignment: .3));
        }
      });
    } else if (!_allLoaded && _comments.length < _count) {
      unawaited(_remainder().then((_) => _resolveAnchor()));
    } else {
      final parent = _reader?.route.postNumber;
      if (parent != null &&
          _reader?.post(widget.postId)?.postNumber != parent) {
        return;
      }
      _anchorResolved = true;
      setState(() => _anchorUnavailable = true);
    }
  }

  Widget _menu(PostVotingComment comment, bool busy) => DDropdownMenu(
    sheetOnMobile: true,
    content: DDropdownMenuContent(
      children: [
        if (_canEdit(comment))
          DDropdownMenuItem(
            leading: const DIcon(DIcons.penToSquare),
            onPressed: busy ? null : () => unawaited(_open(comment)),
            child: Text(context.l10n.postVotingEditComment),
          ),
        if (_canDelete(comment))
          DDropdownMenuItem(
            leading: const DIcon(DIcons.trashCan),
            variant: DDropdownMenuItemVariant.destructive,
            onPressed: busy ? null : () => unawaited(_delete(comment)),
            child: Text(context.l10n.postVotingDeleteComment),
          ),
        if (_reader?.currentUserStaff == true && comment.reviewableId != null)
          DDropdownMenuItem(
            leading: const DIcon(DIcons.flag),
            onPressed: () => unawaited(
              openExternalLink(
                '${widget.siteUrl}/review/${comment.reviewableId}',
              ),
            ),
            child: Text(context.l10n.postVotingReviewComment),
          ),
        if (_canFlag(comment))
          DDropdownMenuItem(
            leading: const DIcon(DIcons.flag),
            onPressed: busy
                ? null
                : () => unawaited(
                    showPostVotingCommentFlag(
                      context,
                      _reader!,
                      comment,
                      widget.services,
                    ),
                  ),
            child: Text(context.l10n.postVotingFlagComment),
          ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DButton.iconOnly(
        variant: DButtonVariant.ghost,
        icon: const DIcon(DIcons.ellipsis),
        tooltip: context.l10n.postVotingCommentLabel,
        focusNode: state.focusNode,
        hasPopup: true,
        expanded: state.open,
        onPressed: state.toggle,
      ),
    ),
  );
  @override
  void dispose() {
    ++_generation;
    widget.services.removeListener(_changed);
    _reader?.removeListener(_changed);
    _reader?.close();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return const SizedBox.shrink();
    final state = widget.services.actions.commentState(
      widget.siteUrl,
      widget.postId,
    );
    final settings = widget.services.settingsFor(widget.siteUrl);
    final busy = state.pending || state.uncertain;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (_comments.isNotEmpty) const DSeparator(),
          for (final comment in _comments)
            KeyedSubtree(
              key: _commentKeys.putIfAbsent(comment.id, GlobalKey.new),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  DToggle(
                    key: ValueKey('post-voting-comment-vote-${comment.id}'),
                    variant: DToggleVariant.inline,
                    icon: const RotatedBox(
                      quarterTurns: 2,
                      child: DIcon(DIcons.chevronDown),
                    ),
                    pressed: _voted(comment) == true,
                    enabled:
                        !_closed &&
                        !busy &&
                        _reader!.currentUserId != null &&
                        comment.authorId != _reader!.currentUserId &&
                        comment.myUpvote != null,
                    semanticLabel: _voted(comment) == true
                        ? context.l10n.postVotingRemoveUpvote
                        : context.l10n.postVotingUpvote,
                    onPressedChanged: (_) => unawaited(_vote(comment)),
                    child: Text('${_score(comment)}'),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 3,
                      children: [
                        CookedHtml(
                          html: comment.cooked,
                          siteUrl: widget.siteUrl,
                          compactParagraphs: true,
                          buildAsync: false,
                        ),
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (comment.username case final username?)
                              UserCardTarget(
                                siteUrl: widget.siteUrl,
                                username: username,
                                child: Text(
                                  comment.name?.isNotEmpty == true
                                      ? comment.name!
                                      : username,
                                ),
                              )
                            else
                              Text(context.l10n.postVotingDeletedUser),
                            RelativeTimeText(comment.createdAt),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_canEdit(comment) ||
                      _canDelete(comment) ||
                      _canFlag(comment))
                    _menu(comment, busy),
                ],
              ),
            ),
          if (_anchorUnavailable)
            DAlert(
              description: DAlertDescription(
                child: Text(context.l10n.postVotingCommentUnavailable),
              ),
            ),
          if (_error != null)
            DAlert(
              variant: DAlertVariant.destructive,
              description: DAlertDescription(
                child: Text(postVotingError(_error!)),
              ),
            ),
          if (state.uncertain)
            DAlert(
              description: DAlertDescription(
                child: Text(context.l10n.postVotingUncertain),
              ),
              action: DAlertAction(
                child: DButton(
                  label: Text(context.l10n.postVotingRefreshStatus),
                  onPressed: () => widget.services.actions.checkComments(
                    _reader!,
                    widget.postId,
                  ),
                ),
              ),
            ),
          if (_loading) const Center(child: DSpinner()),
          if (!_editing)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (_canCreate)
                  DButton(
                    variant: DButtonVariant.ghost,
                    icon: const DIcon(DIcons.comment),
                    label: Text(context.l10n.postVotingAddComment),
                    onPressed: busy || _loading
                        ? null
                        : () => unawaited(_open()),
                  ),
                if (_comments.length < _count)
                  DButton(
                    variant: DButtonVariant.ghost,
                    label: Text(
                      context.l10n.postVotingMoreComments(
                        _count - _comments.length,
                      ),
                    ),
                    onPressed: busy || _loading
                        ? null
                        : () => unawaited(_remainder()),
                  ),
              ],
            ),
          if (!_closed && _count >= settings.commentLimitPerPost && !_editing)
            DText(
              context.l10n.postVotingCommentLimit,
              variant: DTextVariant.muted,
            ),
          if (_editing)
            CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  control: true,
                ): () =>
                    unawaited(_save()),
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  meta: true,
                ): () =>
                    unawaited(_save()),
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  DTextarea(
                    key: ValueKey(
                      'post-voting-comment-editor-${widget.postId}',
                    ),
                    controller: _text,
                    focusNode: _focus,
                    semanticLabel: context.l10n.postVotingCommentLabel,
                    minLines: 2,
                    maxLines: 5,
                    enabled: !busy,
                    errorText: _text.text.isEmpty ? null : _lengthError,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_text.text.runes.length <= settings.commentMaxRawLength)
                    DText(
                      context.l10n.postVotingCharactersLeft(
                        settings.commentMaxRawLength - _text.text.runes.length,
                      ),
                      variant: DTextVariant.muted,
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      DButton(
                        key: ValueKey(
                          'post-voting-comment-submit-${widget.postId}',
                        ),
                        label: Text(
                          _editId == null
                              ? context.l10n.postVotingAddComment
                              : context.l10n.save,
                        ),
                        loading: state.pending,
                        onPressed: busy || _lengthError != null
                            ? null
                            : () => unawaited(_save()),
                      ),
                      DButton(
                        variant: DButtonVariant.ghost,
                        label: Text(context.l10n.cancel),
                        onPressed: state.pending
                            ? null
                            : () => setState(() {
                                _editing = false;
                                _text.clear();
                                _editId = null;
                                _error = null;
                              }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
