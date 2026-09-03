import 'dart:async';

import 'package:flutter/material.dart';

import 'voice_controller.dart';

/// Shows each [VoiceNotice] once, as a snackbar, wherever the shell is: a
/// role change, a dismissed request to speak, a recording starting. The
/// controller emits them regardless of which surface is open, so the host
/// sits with the shell overlays rather than inside the room page.
class VoiceNoticeHost extends StatefulWidget {
  const VoiceNoticeHost({super.key, required this.notices});

  final Stream<VoiceNotice> notices;

  @override
  State<VoiceNoticeHost> createState() => _VoiceNoticeHostState();
}

class _VoiceNoticeHostState extends State<VoiceNoticeHost> {
  StreamSubscription<VoiceNotice>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(VoiceNoticeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notices, widget.notices)) _listen();
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription = widget.notices.listen(_show);
  }

  void _show(VoiceNotice notice) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(notice.message)));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
