import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/material.dart';

import '../../theme/d_button.dart';
import 'voice_controller.dart';
import 'voice_icons.dart';
import 'voice_shell_service.dart';

/// The answer surface for a direct call: drawn over the whole shell (a ring
/// arrives whether or not any Voice surface is on screen), it names the
/// caller and offers to answer or decline, and goes away on its own when
/// the ring runs out.
class VoiceIncomingCallBanner extends StatefulWidget {
  const VoiceIncomingCallBanner({
    super.key,
    required this.controller,
    required this.shell,
  });

  final VoiceController controller;
  final VoiceShellService shell;

  @override
  State<VoiceIncomingCallBanner> createState() =>
      _VoiceIncomingCallBannerState();
}

class _VoiceIncomingCallBannerState extends State<VoiceIncomingCallBanner> {
  bool _answering = false;

  Future<void> _answer() async {
    if (_answering) return;
    setState(() => _answering = true);
    try {
      await widget.shell.answerIncomingCall(context);
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final call = widget.controller.incomingCall;
      final siteUrl = widget.controller.incomingCallSiteUrl;
      if (call == null || siteUrl == null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final caller = call.caller;
      return SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: Semantics(
            liveRegion: true,
            label: '${caller.name ?? caller.username} is calling you',
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipOval(
                        child: SizedBox.square(
                          dimension: 44,
                          child: AvatarImage(
                            url: caller.avatarUrl(siteUrl, size: 88),
                            size: 44,
                            fallback: ColoredBox(
                              color: theme.colorScheme.surfaceContainerHigh,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              caller.name ?? caller.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              'is calling you…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      DButton(
                        onPressed: _answering ? null : _answer,
                        icon: const DIcon(VoiceIcons.phone, size: 16),
                        label: const Text('Answer'),
                        variant: DButtonVariant.primary,
                        loading: _answering,
                      ),
                      const SizedBox(width: 8),
                      DButton(
                        onPressed: widget.controller.declineIncomingCall,
                        icon: const DIcon(DIcons.phoneSlash, size: 16),
                        label: const Text('Decline'),
                        variant: DButtonVariant.danger,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Re-evaluates a call room's "Calling…" tiles on a coarse clock: ring
/// windows expire by wall time, which nothing else observes.
class VoiceRingingClock extends StatefulWidget {
  const VoiceRingingClock({
    super.key,
    required this.active,
    required this.builder,
    this.interval = const Duration(seconds: 5),
  });

  final bool active;
  final Widget Function(BuildContext context, DateTime now) builder;
  final Duration interval;

  @override
  State<VoiceRingingClock> createState() => _VoiceRingingClockState();
}

class _VoiceRingingClockState extends State<VoiceRingingClock> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(VoiceRingingClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    _ticker?.cancel();
    _ticker = null;
    if (!widget.active) return;
    _ticker = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.active ? _now : DateTime.now());
}
