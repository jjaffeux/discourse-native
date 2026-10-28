import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';
import 'd_badge.dart';

@immutable
final class DReactionOverlayEntry {
  const DReactionOverlayEntry({
    required this.id,
    required this.label,
    required this.artwork,
  });

  final Object id;
  final String label;
  final Widget artwork;
}

/// Non-interactive reaction bursts inside a bounded call stage or preview.
/// The caller owns expiry; the kit owns motion, spacing and presentation.
class DReactionOverlay extends StatelessWidget {
  const DReactionOverlay({super.key, required this.entries});

  final List<DReactionOverlayEntry> entries;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) => ClipRect(
          child: Stack(
            children: [
              for (final entry in entries)
                Positioned(
                  key: ValueKey(entry.id),
                  left:
                      (constraints.maxWidth - 100).clamp(0, double.infinity) *
                      ((entry.id.hashCode & 255) / 255),
                  bottom: DSpacing.sm,
                  width: constraints.maxWidth.clamp(0, 100),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(seconds: 4),
                    builder: (context, progress, child) => Opacity(
                      opacity: reducedMotion ? 1 : 1 - progress,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          reducedMotion
                              ? 0
                              : -progress * (constraints.maxHeight * .65),
                        ),
                        child: child,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        entry.artwork,
                        const SizedBox(height: DSpacing.xs),
                        DBadge(
                          variant: DBadgeVariant.secondary,
                          child: Text(
                            entry.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
