import 'package:flutter/material.dart';

import '../../theme/d_button.dart';
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
}) async {
  final confirmed = await confirmVoiceMeshPrivacy(
    context,
    controller: controller,
    room: room,
    enabled: meshPrivacyWarningEnabled,
  );
  if (!confirmed) return;
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
}) async {
  if (!enabled || room.expectedTransport != VoiceTransport.mesh) return true;
  if (await controller.meshPrivacyAcknowledged()) return true;
  if (!context.mounted || _meshPrivacyWarningOpen) return false;
  _meshPrivacyWarningOpen = true;
  try {
    final result = await showDialog<VoiceMeshPrivacyDecision>(
      context: context,
      builder: (context) => const VoiceMeshPrivacyDialog(),
    );
    if (result == null || !result.join) return false;
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
  const VoiceMeshPrivacyDialog({super.key});

  @override
  State<VoiceMeshPrivacyDialog> createState() => _VoiceMeshPrivacyDialogState();
}

class _VoiceMeshPrivacyDialogState extends State<VoiceMeshPrivacyDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    constraints: const BoxConstraints(maxWidth: 560),
    scrollable: true,
    title: const Text('Before you join this room'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'This room connects participants directly to each other, so while '
          'you are in the call other participants may be able to see your IP '
          'address. This is how peer-to-peer calls work and is usually '
          'harmless, but join only if you are comfortable with it.',
        ),
        const SizedBox(height: 12),
        CheckboxListTile.adaptive(
          value: _dontShowAgain,
          onChanged: (value) => setState(() => _dontShowAgain = value ?? false),
          title: const Text("Don't show this again"),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    ),
    actions: [
      DButton(
        onPressed: () => Navigator.pop(context),
        label: const Text('Cancel'),
      ),
      DButton(
        onPressed: () => Navigator.pop(
          context,
          VoiceMeshPrivacyDecision(join: true, dontShowAgain: _dontShowAgain),
        ),
        label: const Text('Join room'),
        variant: DButtonVariant.primary,
      ),
    ],
  );
}
