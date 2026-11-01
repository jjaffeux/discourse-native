import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'post_voting_actions.dart';
import 'post_voting_data.dart';
import 'post_voting_services.dart';

Future<void> showPostVotingCommentFlag(
  BuildContext context,
  PluginTopicReader reader,
  PostVotingComment comment,
  PostVotingServices services,
) async {
  if (!reader.isCurrent) return;
  final dsaRequested = await showDDialog<bool>(
    context: context,
    builder: (context, dialog) => DDialogContent(
      children: [
        DDialogTitle(child: Text(context.l10n.postVotingFlagComment)),
        _FlagForm(
          reader: reader,
          comment: comment,
          services: services,
          close: () => dialog.close(false),
          reportIllegal: () => dialog.close(true),
        ),
      ],
    ),
  );
  if (dsaRequested == true && context.mounted && reader.isCurrent) {
    await showIllegalContentReport(
      context: context,
      siteUrl: reader.siteUrl,
      contentUrl:
          '${reader.siteUrl}/p/${comment.parentPostId}#post-voting-comment-${comment.id}',
      title: reader.topic?.title ?? context.l10n.postVotingTitle,
    );
  }
}

class _FlagForm extends StatefulWidget {
  const _FlagForm({
    required this.reader,
    required this.comment,
    required this.services,
    required this.close,
    required this.reportIllegal,
  });
  final PluginTopicReader reader;
  final PostVotingComment comment;
  final PostVotingServices services;
  final VoidCallback close;
  final VoidCallback reportIllegal;
  @override
  State<_FlagForm> createState() => _FlagFormState();
}

class _FlagFormState extends State<_FlagForm> {
  final _message = TextEditingController();
  PostFlagType? _choice;
  bool _warning = false, _takeAction = false, _queue = false, _saving = false;
  Object? _error;
  List<PostFlagType> get _choices => widget.services
      .flagCatalog(widget.reader.siteUrl)
      .where(
        (type) =>
            widget.comment.availableFlags.contains(type.nameKey) &&
            type.enabled &&
            (!widget.services
                    .settingsFor(widget.reader.siteUrl)
                    .dsaReportingEnabled ||
                type.nameKey != 'illegal'),
      )
      .toList();
  Future<void> _submit() async {
    final choice = _choice;
    if (_saving ||
        choice == null ||
        !_choices.any((item) => item.id == choice.id) ||
        !widget.reader.isCurrent) {
      return;
    }
    final latest = widget.services.actions
        .record(widget.reader.siteUrl, widget.comment.parentPostId)
        ?.initialComments
        ?.where((item) => item.id == widget.comment.id)
        .firstOrNull;
    if (latest == null || !latest.availableFlags.contains(choice.nameKey)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final staff = widget.reader.currentUserStaff;
    final result = await widget.services.actions.mutateComment(
      reader: widget.reader,
      postId: widget.comment.parentPostId,
      send: (credentials) async {
        await widget.services.api.flagComment(
          siteUrl: widget.reader.siteUrl,
          credentials: credentials,
          command: PostVotingFlagCommand(
            commentId: widget.comment.id,
            flagTypeId: choice.id,
            message: _message.text.trim().isEmpty ? null : _message.text.trim(),
            isWarning: staff && choice.nameKey == 'notify_user' && _warning,
            takeAction: staff && choice.nameKey != 'notify_user' && _takeAction,
            queueForReview: staff && choice.nameKey != 'notify_user' && _queue,
          ),
        );
        return null;
      },
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = result.error;
    });
    if (result.accepted && widget.reader.isCurrent) widget.close();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dsa = widget.services
        .settingsFor(widget.reader.siteUrl)
        .dsaReportingEnabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (_choices.isNotEmpty)
          DSelect<PostFlagType>.controlled(
            value: _choice,
            semanticLabel: context.l10n.reason,
            entries: [
              for (final choice in _choices)
                DSelectOption(
                  value: choice,
                  label: choice.name,
                  child: Text(choice.name),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    _choice = value;
                    _warning = false;
                    _takeAction = false;
                    _queue = false;
                  }),
          ),
        if (_choice case final choice?) ...[
          Text(choice.description),
          DTextarea(
            controller: _message,
            semanticLabel: context.l10n.postVotingFlagMessage,
            labelText: context.l10n.postVotingFlagMessage,
            minLines: 2,
            maxLines: 4,
            enabled: !_saving,
            onChanged: (_) => setState(() {}),
          ),
          if (widget.reader.currentUserStaff)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (choice.nameKey == 'notify_user')
                  DToggle(
                    pressed: _warning,
                    enabled: !_saving,
                    child: Text(context.l10n.postVotingStaffWarning),
                    onPressedChanged: (value) =>
                        setState(() => _warning = value),
                  )
                else ...[
                  DToggle(
                    pressed: _takeAction,
                    enabled: !_saving,
                    child: Text(context.l10n.postVotingTakeAction),
                    onPressedChanged: (value) => setState(() {
                      _takeAction = value;
                      if (value) _queue = false;
                    }),
                  ),
                  DToggle(
                    pressed: _queue,
                    enabled: !_saving,
                    child: Text(context.l10n.postVotingQueueForReview),
                    onPressedChanged: (value) => setState(() {
                      _queue = value;
                      if (value) _takeAction = false;
                    }),
                  ),
                ],
              ],
            ),
        ],
        if (_error != null)
          DAlert(
            variant: DAlertVariant.destructive,
            description: DAlertDescription(
              child: Text(postVotingError(_error!)),
            ),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (_choice != null)
              DButton(
                label: Text(context.l10n.flag),
                loading: _saving,
                onPressed:
                    _saving ||
                        !widget.reader.isCurrent ||
                        (_choice!.requireMessage &&
                            _message.text.trim().isEmpty)
                    ? null
                    : _submit,
              ),
            if (dsa)
              DButton(
                variant: DButtonVariant.ghost,
                label: Text(context.l10n.reportIllegalContent),
                onPressed: _saving || !widget.reader.isCurrent
                    ? null
                    : widget.reportIllegal,
              ),
          ],
        ),
      ],
    );
  }
}
