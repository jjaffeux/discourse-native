import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../data/invites_api.dart';
import '../models/discourse_instance.dart';
import 'invite_editor.dart';
import 'invites_controller.dart';
import 'shell_controller.dart';
import 'shell_sheet.dart';

/// Opens the invite editor for [topicId], so the invitee lands in that topic.
Future<void> showTopicInviteSheet({
  required BuildContext context,
  required ShellController shell,
  required DiscourseInstance instance,
  required int topicId,
}) => showShellSheet<void>(
  context: context,
  title: appL10n.inviteToTopicTitle,
  dialogOnDesktop: true,
  // The form has inputs taller than a phone's sheet; fill the viewport above
  // the keyboard and scroll the body.
  fillAvailableHeight: true,
  builder: (context) =>
      _TopicInviteHost(shell: shell, instance: instance, topicId: topicId),
);

class _TopicInviteHost extends StatefulWidget {
  const _TopicInviteHost({
    required this.shell,
    required this.instance,
    required this.topicId,
  });

  final ShellController shell;
  final DiscourseInstance instance;
  final int topicId;

  @override
  State<_TopicInviteHost> createState() => _TopicInviteHostState();
}

class _TopicInviteHostState extends State<_TopicInviteHost> {
  late final InvitesController _controller = InvitesController(
    api: InvitesApi(widget.shell.api.pluginTransport),
    credentials: widget.shell.credentials,
    instance: widget.instance,
    lifecycle: widget.shell.lifecycle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InviteEditor(
    controller: _controller,
    topicId: widget.topicId,
    onClose: () => DDialogClose.close<void>(context),
  );
}
