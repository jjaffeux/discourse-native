import 'package:flutter/widgets.dart';
import 'gamification_controller.dart';
import 'gamification_models.dart';
import 'gamification_page.dart';

class GamificationCompact extends StatefulWidget {
  const GamificationCompact({
    super.key,
    required this.site,
    required this.controller,
    this.query = const GamificationQuery(),
    this.limit = 5,
  });
  final String site;
  final GamificationController controller;
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
  Widget build(BuildContext context) =>
      GamificationResults(handle: handle, compact: true);
}
