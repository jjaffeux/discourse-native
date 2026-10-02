import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'voice_agents.dart';
import 'voice_controller.dart';

/// Mounted on room and call controls; permission belongs to the authenticated
/// account, and is refreshed whenever a new room surface is opened.
class VoiceAgentInviteAction extends StatefulWidget {
  const VoiceAgentInviteAction({
    super.key,
    required this.controller,
    required this.siteUrl,
    required this.roomId,
  });

  final VoiceController controller;
  final String siteUrl;
  final int roomId;

  @override
  State<VoiceAgentInviteAction> createState() => _VoiceAgentInviteActionState();
}

class _VoiceAgentInviteActionState extends State<VoiceAgentInviteAction> {
  late bool Function() _ownsAccount;

  void _refreshPermission() {
    _ownsAccount = widget.controller.captureSiteSession(widget.siteUrl);
    unawaited(widget.controller.refreshAgentPermission(widget.siteUrl));
  }

  @override
  void initState() {
    super.initState();
    _refreshPermission();
  }

  @override
  void didUpdateWidget(VoiceAgentInviteAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.roomId != widget.roomId) {
      _refreshPermission();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.controller,
      widget.controller.agentPermissions,
    ]),
    builder: (context, _) {
      if (!_ownsAccount()) _refreshPermission();
      return widget.controller.canInviteAgent(widget.siteUrl, widget.roomId)
          ? DButton(
              variant: DButtonVariant.outline,
              label: Text(context.l10n.inviteAgent),
              onPressed: () {
                final controller = widget.controller;
                final siteUrl = widget.siteUrl;
                final roomId = widget.roomId;
                final invitation = controller.agentInvitation(
                  siteUrl,
                  roomId,
                  ifCurrent: () =>
                      mounted &&
                      widget.controller == controller &&
                      widget.siteUrl == siteUrl &&
                      widget.roomId == roomId,
                );
                unawaited(
                  showDDialog<void>(
                    context: context,
                    builder: (context, dialog) => VoiceAgentInviteDialog(
                      invitation: invitation,
                      availability: Listenable.merge([
                        controller,
                        controller.agentPermissions,
                      ]),
                      available: () =>
                          controller.canInviteAgent(siteUrl, roomId),
                    ),
                  ),
                );
              },
            )
          : const SizedBox.shrink();
    },
  );
}

/// Owns the invitation until the route's exit animation has finished.
class VoiceAgentInviteDialog extends StatefulWidget {
  const VoiceAgentInviteDialog({
    super.key,
    required this.invitation,
    required this.availability,
    required this.available,
  });

  final VoiceAgentInvitation invitation;
  final Listenable availability;
  final bool Function() available;

  @override
  State<VoiceAgentInviteDialog> createState() => _VoiceAgentInviteDialogState();
}

class _VoiceAgentInviteDialogState extends State<VoiceAgentInviteDialog> {
  final _name = TextEditingController();
  bool _manual = false;
  String? _selected;

  @override
  void initState() {
    super.initState();
    unawaited(widget.invitation.refresh(force: false));
  }

  @override
  void dispose() {
    widget.invitation.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.invitation, widget.availability]),
    builder: (context, _) {
      final state = widget.invitation;
      final available = state.isCurrent && widget.available();
      final manual = _manual || state.names.isEmpty;
      final selected = state.names.contains(_selected) ? _selected : null;
      final enabled =
          available && !state.loading && !state.sending && !state.sent;
      return DDialogContent(
        semanticLabel: context.l10n.inviteVoiceAgent,
        maxWidth: 480,
        children: [
          DDialogHeader(
            children: [
              DDialogTitle(child: Text(context.l10n.inviteAgent)),
              DDialogDescription(
                child: Text(context.l10n.voiceAgentDeployHint),
              ),
              DDialogDescription(
                child: Text(
                  context.l10n.chooseADeployedAgentOrEnterItsDispatchName,
                ),
              ),
            ],
          ),
          DDialogScrollArea(
            child: DFieldGroup(
              children: [
                if (state.sent)
                  DAlert(
                    title: DAlertTitle(
                      child: Text(context.l10n.agentInvitationSent),
                    ),
                  )
                else if (!available)
                  DAlert(
                    title: DAlertTitle(
                      child: Text(
                        context.l10n.thisInvitationIsNoLongerAvailable,
                      ),
                    ),
                  )
                else ...[
                  if (state.catalogueError case final error?)
                    DAlert(description: DAlertDescription(child: Text(error))),
                  if (manual)
                    DInput(
                      controller: _name,
                      labelText: context.l10n.agentName,
                      enabled: enabled,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: enabled
                          ? (_) => state.submit(_name.text)
                          : null,
                    )
                  else
                    DSelect<String>.controlled(
                      value: selected,
                      label: Text(context.l10n.deployedAgent),
                      placeholder: context.l10n.chooseAnAgent,
                      isExpanded: true,
                      enabled: enabled,
                      entries: [
                        for (final name in state.names)
                          DSelectOption(
                            value: name,
                            label: name,
                            child: Text(name),
                          ),
                      ],
                      onChanged: (value) => setState(() => _selected = value),
                    ),
                  Wrap(
                    spacing: DSpacing.controlGap,
                    runSpacing: DSpacing.controlGap,
                    children: [
                      if (state.names.isNotEmpty)
                        DToggle(
                          pressed: _manual,
                          enabled: enabled,
                          onPressedChanged: (value) =>
                              setState(() => _manual = value),
                          child: Text(context.l10n.typeAName),
                        ),
                      DButton(
                        label: Text(context.l10n.refreshAgents),
                        variant: DButtonVariant.outline,
                        onPressed: enabled && !state.loading
                            ? () => state.refresh()
                            : null,
                      ),
                    ],
                  ),
                  if (state.error case final error?)
                    DAlert(
                      variant: DAlertVariant.destructive,
                      description: DAlertDescription(child: Text(error)),
                    ),
                ],
              ],
            ),
          ),
          DDialogFooter(
            children: [
              DDialogClose<void>(
                builder: (context, close) => DButton(
                  label: Text(
                    state.sent ? context.l10n.done : context.l10n.cancel,
                  ),
                  variant: DButtonVariant.outline,
                  onPressed: close,
                ),
              ),
              if (!state.sent && available)
                DButton(
                  label: Text(context.l10n.sendInvitation),
                  loading: state.sending,
                  loadingSemanticLabel: context.l10n.sendingInvitation,
                  onPressed: enabled
                      ? () => state.submit(manual ? _name.text : selected ?? '')
                      : null,
                ),
            ],
          ),
        ],
      );
    },
  );
}
