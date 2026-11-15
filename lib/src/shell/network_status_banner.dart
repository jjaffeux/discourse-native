import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../foundation/icons/d_icons.dart';
import 'shell_scope.dart';

/// Lays a notice over [child] while the current site cannot be connected to.
///
/// It floats rather than taking a row of its own, so losing and regaining the
/// connection never moves what the reader is looking at. It listens to the
/// reachability notifier directly: an origin going away redraws this notice
/// and nothing else.
class NetworkStatusBanner extends StatelessWidget {
  const NetworkStatusBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      const PositionedDirectional(
        top: 8,
        start: 16,
        end: 16,
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: _UnreachableSiteNotice(),
          ),
        ),
      ),
    ],
  );
}

class _UnreachableSiteNotice extends StatelessWidget {
  const _UnreachableSiteNotice();

  @override
  Widget build(BuildContext context) => ShellSelector<(String?, String?)>(
    select: (controller) {
      final instance = controller.currentInstance;
      return (instance?.url, instance?.host);
    },
    builder: (context, site, _) {
      final (url, host) = site;
      final recovery = ShellScope.read(context).networkRecovery;
      return ListenableBuilder(
        listenable: recovery.reachability,
        builder: (context, _) => DReveal(
          visible: url != null && !recovery.isReachable(url),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DAlert(
              key: const ValueKey('network-status-banner'),
              icon: const DIcon(DIcons.triangleExclamation),
              description: DAlertDescription(
                child: Text(
                  context.l10n.canTConnectToRetryingAutomatically(host ?? ''),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
