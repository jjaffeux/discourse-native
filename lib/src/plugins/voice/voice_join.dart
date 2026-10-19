import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'voice_controller.dart';
import 'voice_models.dart';

/// Guards against a repeat join request (double tap, sidebar plus room page)
/// replacing the warning out from under the first one.
bool _meshPrivacyWarningOpen = false;

/// Joins [room] the way every surface should: a peer-to-peer room first gets
/// the IP exposure warning, unless the site turned it off or this device
/// accepted it before. Cancelling the warning leaves nothing to unwind — no
/// join state is touched until it is accepted.
Future<void> joinVoiceRoom(
  BuildContext context, {
  required VoiceController controller,
  required String siteUrl,
  required String siteName,
  required VoiceRoom room,
  required bool meshPrivacyWarningEnabled,
  bool Function()? ifCurrent,
}) async {
  if (ifCurrent?.call() == false) return;
  final confirmed = await confirmVoiceMeshPrivacy(
    context,
    controller: controller,
    room: room,
    enabled: meshPrivacyWarningEnabled,
    ifCurrent: ifCurrent,
  );
  if (!confirmed || !context.mounted || ifCurrent?.call() == false) return;
  await controller.join(siteUrl: siteUrl, siteName: siteName, room: room);
}

/// Whether the join may proceed. Mesh joins connect participants directly,
/// so everyone in the room can learn everyone else's IP address; the server
/// predicts the transport in `expected_transport` and the pin set at join
/// stays authoritative, so a prediction that flips mesh → LiveKit only makes
/// the warning over-cautious. Mirrors the web client's `confirmMeshPrivacy`.
Future<bool> confirmVoiceMeshPrivacy(
  BuildContext context, {
  required VoiceController controller,
  required VoiceRoom room,
  required bool enabled,
  bool Function()? ifCurrent,
}) async {
  if (ifCurrent?.call() == false) return false;
  if (!enabled || room.expectedTransport != VoiceTransport.mesh) return true;
  final acknowledged = await controller.meshPrivacyAcknowledged();
  if (!context.mounted || ifCurrent?.call() == false) return false;
  if (acknowledged) return true;
  if (_meshPrivacyWarningOpen) return false;
  _meshPrivacyWarningOpen = true;
  try {
    final result = await showDDialog<VoiceMeshPrivacyDecision>(
      context: context,
      useRootNavigator: true,
      builder: (context, dialog) =>
          VoiceMeshPrivacyDialog(onClose: dialog.close),
    );
    if (result == null || !result.join || ifCurrent?.call() == false) {
      return false;
    }
    if (result.dontShowAgain) await controller.acknowledgeMeshPrivacy();
    return true;
  } finally {
    _meshPrivacyWarningOpen = false;
  }
}

@immutable
final class VoiceMeshPrivacyDecision {
  const VoiceMeshPrivacyDecision({
    required this.join,
    required this.dontShowAgain,
  });

  final bool join;
  final bool dontShowAgain;
}

class VoiceMeshPrivacyDialog extends StatefulWidget {
  const VoiceMeshPrivacyDialog({super.key, required this.onClose});

  final ValueChanged<VoiceMeshPrivacyDecision?> onClose;

  @override
  State<VoiceMeshPrivacyDialog> createState() => _VoiceMeshPrivacyDialogState();
}

class _VoiceMeshPrivacyDialogState extends State<VoiceMeshPrivacyDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) => DDialogContent(
    showCloseButton: false,
    maxWidth: 560,
    children: [
      DDialogHeader(
        children: [
          DDialogTitle(child: Text(context.l10n.beforeYouJoinThisRoom)),
        ],
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context
                .l10n
                .thisRoomConnectsParticipantsDirectlyToEachOtherSoWhileYou,
          ),
          const SizedBox(height: 12),
          DCheckbox(
            value: _dontShowAgain,
            onChanged: (value) =>
                setState(() => _dontShowAgain = value ?? false),
            title: DLabel(child: Text(context.l10n.donTShowThisAgain)),

            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      DDialogFooter(
        children: [
          DButton(
            onPressed: () => widget.onClose(null),
            label: Text(context.l10n.cancel),
          ),
          DButton(
            onPressed: () => widget.onClose(
              VoiceMeshPrivacyDecision(
                join: true,
                dontShowAgain: _dontShowAgain,
              ),
            ),
            label: Text(context.l10n.joinRoom),
            variant: DButtonVariant.primary,
          ),
        ],
      ),
    ],
  );
}
