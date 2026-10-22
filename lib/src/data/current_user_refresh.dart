import 'dart:async';

import '../models/discourse_user.dart';
import 'site_lifecycle.dart';

final class CurrentUserRefresh {
  CurrentUserRefresh({required SiteLease lease, required this._read})
    : _lease = lease {
    _removeRetirementObserver = lease.onRetire(retire);
  }

  final SiteLease _lease;
  final Future<DiscourseUser?> Function() _read;
  Completer<DiscourseUser?>? _active;
  Completer<DiscourseUser?>? _pending;
  void Function()? _removeRetirementObserver;
  bool _retired = false;

  bool get isCurrent => !_retired && _lease.isCurrent;

  Future<DiscourseUser?> request({bool force = false}) {
    if (!isCurrent) return Future.value();
    final active = _active;
    if (active != null) {
      if (!force) return active.future;
      return (_pending ??= Completer<DiscourseUser?>()).future;
    }
    final task = Completer<DiscourseUser?>();
    _start(task);
    return task.future;
  }

  void _start(Completer<DiscourseUser?> task) {
    _active = task;
    unawaited(_run(task));
  }

  Future<void> _run(Completer<DiscourseUser?> task) async {
    try {
      final user = await _read();
      if (!isCurrent) return;
      task.complete(user);
    } catch (error, stackTrace) {
      if (!isCurrent) return;
      task.completeError(error, stackTrace);
    } finally {
      if (isCurrent) {
        _active = null;
        final replay = _pending;
        _pending = null;
        if (replay != null) _start(replay);
      }
    }
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _removeRetirementObserver?.call();
    _removeRetirementObserver = null;
    _active?.complete();
    _pending?.complete();
    _active = null;
    _pending = null;
  }
}
