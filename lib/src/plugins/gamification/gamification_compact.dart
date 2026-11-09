import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'gamification_controller.dart';
import 'gamification_models.dart';
import 'gamification_navigation.dart';
import 'gamification_page.dart';
import 'gamification_route.dart';

class GamificationCompact extends StatefulWidget {
  const GamificationCompact({
    super.key,
    required this.site,
    required this.controller,
    required this.navigation,
    this.query = const GamificationQuery(),
    this.limit = 10,
  });
  final String site;
  final GamificationController controller;
  final GamificationNavigation navigation;
  final GamificationQuery query;
  final int limit;
  @override
  State<GamificationCompact> createState() => _GamificationCompactState();
}

class _GamificationCompactState extends State<GamificationCompact> {
  late GamificationHandle handle;
  void _acquire() {
    handle = widget.controller.acquire(
      widget.site,
      widget.query,
      previewUserLimit: widget.limit,
    );
    handle.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _acquire();
  }

  @override
  void didUpdateWidget(GamificationCompact oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        oldWidget.query != widget.query ||
        oldWidget.limit != widget.limit ||
        oldWidget.controller != widget.controller) {
      handle.removeListener(_changed);
      handle.release();
      _acquire();
    }
  }

  @override
  void dispose() {
    handle.removeListener(_changed);
    handle.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = handle.state;
    final snapshot = state is GamificationReady ? state.snapshot : null;
    return DCard(
      children: [
        DCardHeader(
          title: DCardTitle(
            child: DButton(
              variant: DButtonVariant.inline,
              label: Text(
                snapshot?.board.name ?? context.l10n.gamificationTitle,
              ),
              onPressed: snapshot == null
                  ? null
                  : () => widget.navigation.openForSite(
                      widget.site,
                      GamificationRoute(
                        boardId: snapshot.board.id,
                        period:
                            handle.query.period ?? snapshot.board.defaultPeriod,
                      ),
                    ),
            ),
          ),
        ),
        DCardContent(child: GamificationResults(handle: handle, compact: true)),
      ],
    );
  }
}
