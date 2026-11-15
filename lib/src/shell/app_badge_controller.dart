import 'package:flutter/foundation.dart';

import '../data/platform_app_badge.dart';

/// Keeps the app icon's badge equal to the unread total across signed-in
/// forums. It follows the totals notifier alone, so nothing else the shell
/// publishes reaches the platform.
final class AppBadgeController {
  AppBadgeController({
    required this._totals,
    required this._count,
    required this._badge,
  }) {
    _totals.addListener(_sync);
    _sync();
  }

  final Listenable _totals;
  final int Function() _count;
  final AppBadge _badge;
  int? _sent;
  bool _disposed = false;

  /// Sends the count again even when it has not moved: while the app was away
  /// a push payload may have drawn its own number over ours.
  void refresh() {
    _sent = null;
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    final count = _count();
    if (count == _sent) return;
    _send(count);
  }

  // The channel delivers calls in order, so the newest count is drawn last.
  void _send(int count) {
    _sent = count;
    _badge.setCount(count).ignore();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _totals.removeListener(_sync);
  }
}
