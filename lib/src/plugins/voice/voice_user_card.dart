import 'package:flutter/material.dart';

import '../../data/discourse_api_contracts.dart';
import '../../models/user_card.dart';
import '../../plugin_api/plugin_data.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import 'voice_icons.dart';
import 'voice_shell_service.dart';

const voiceUserCardKey = PluginDataKey<VoiceUserCardData>(
  owner: 'voice',
  name: 'user-card',
);

/// Whether the viewer may call this user: the site's own decision
/// (`voice_can_call` on the card), which folds in the caller's group, the
/// target's access, and the target's message preferences. Absent when the
/// viewer cannot start calls at all.
@immutable
final class VoiceUserCardData {
  const VoiceUserCardData({required this.canCall});

  final bool canCall;

  @override
  bool operator ==(Object other) =>
      other is VoiceUserCardData && other.canCall == canCall;

  @override
  int get hashCode => canCall.hashCode;
}

class VoiceUserCardCallButton extends StatefulWidget {
  const VoiceUserCardCallButton({
    super.key,
    required this.siteUrl,
    required this.user,
    required this.close,
  });

  final String siteUrl;
  final UserCard user;
  final VoidCallback close;

  @override
  State<VoiceUserCardCallButton> createState() =>
      _VoiceUserCardCallButtonState();
}

class _VoiceUserCardCallButtonState extends State<VoiceUserCardCallButton> {
  bool _calling = false;

  Future<void> _call() async {
    if (_calling) return;
    setState(() => _calling = true);
    try {
      final shell = PluginUiScope.require(context, voiceShellService);
      widget.close();
      await shell.callUser(
        context,
        siteUrl: widget.siteUrl,
        username: widget.user.username,
      );
    } catch (error) {
      if (!mounted) return;
      final message = switch (error) {
        final WriteException error => error.message,
        _ => "Couldn't start the call.",
      };
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: DButton(
      key: ValueKey<String>('user-card-call-${widget.user.username}'),
      label: const Text('Call'),
      onPressed: _call,
      icon: const DIcon(VoiceIcons.phone, size: 16),
      variant: DButtonVariant.primary,
      loading: _calling,
    ),
  );
}
