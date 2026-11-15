import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../data/push_registration_ledger.dart';
import 'push_registration_health.dart';

/// Offers a new sign-in to each account whose forum lost this device's push
/// token. It follows [PushRegistrationHealth] alone and never signs in itself:
/// the toast stays until a sign-in answers it or the user closes it, so a
/// cancelled sign-in leaves the offer standing.
class PushReauthorizationPrompts extends StatefulWidget {
  const PushReauthorizationPrompts({
    super.key,
    required this.health,
    required this.siteTitle,
    required this.onReauthorize,
    required this.child,
  });

  final PushRegistrationHealth health;
  final String Function(String siteUrl) siteTitle;
  final Future<void> Function(String siteUrl) onReauthorize;
  final Widget child;

  @override
  State<PushReauthorizationPrompts> createState() =>
      _PushReauthorizationPromptsState();
}

class _PushReauthorizationPromptsState
    extends State<PushReauthorizationPrompts> {
  final Map<String, PushReauthorizationPrompt> _shown = {};
  DToastController? _toasts;

  @override
  void initState() {
    super.initState();
    widget.health.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _toasts = DToast.maybeOf(context);
    // Opening a toast rebuilds the toaster above, which cannot happen while
    // this subtree is itself being built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(PushReauthorizationPrompts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.health, widget.health)) return;
    oldWidget.health.removeListener(_sync);
    widget.health.addListener(_sync);
  }

  @override
  void dispose() {
    widget.health.removeListener(_sync);
    super.dispose();
  }

  static Object _id(String siteUrl) => 'push-reauthorization:$siteUrl';

  void _sync() {
    final toasts = _toasts;
    if (!mounted || toasts == null) return;
    final wanted = {
      for (final prompt in widget.health.prompts) prompt.siteUrl: prompt,
    };
    for (final siteUrl in _shown.keys.toList()) {
      if (wanted[siteUrl] == _shown[siteUrl]) continue;
      _shown.remove(siteUrl);
      toasts.close(_id(siteUrl));
    }
    for (final prompt in wanted.values) {
      if (_shown.containsKey(prompt.siteUrl)) continue;
      _shown[prompt.siteUrl] = prompt;
      toasts.add(_options(prompt), id: _id(prompt.siteUrl));
    }
  }

  DToastOptions _options(PushReauthorizationPrompt prompt) {
    final l10n = context.l10n;
    final site = widget.siteTitle(prompt.siteUrl);
    return DToastOptions(
      title: switch (prompt.drift) {
        PushRegistrationDrift.newlyAvailable =>
          l10n.pushReauthorizationAvailableTitle(site),
        _ => l10n.pushReauthorizationRotatedTitle(site),
      },
      description: switch (prompt.drift) {
        PushRegistrationDrift.newlyAvailable =>
          l10n.pushReauthorizationAvailableDescription,
        _ => l10n.pushReauthorizationRotatedDescription,
      },
      type: DToastType.warning,
      duration: null,
      action: DToastAction(
        label: l10n.pushReauthorizationAction,
        onPressed: () => unawaited(widget.onReauthorize(prompt.siteUrl)),
      ),
      onClose: (reason) {
        if (_shown[prompt.siteUrl] == prompt) _shown.remove(prompt.siteUrl);
        if (reason == DToastCloseReason.closeButton ||
            reason == DToastCloseReason.swipe) {
          widget.health.dismiss(prompt).ignore();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
