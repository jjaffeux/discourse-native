import 'dart:async';

import '../models/discourse_user.dart';
import 'request_intent.dart';
import 'site_lifecycle.dart';

final class CurrentUserRefresh {
  CurrentUserRefresh({required SiteLease lease, required this._read})
    : _lease = lease {
    _removeRetirementObserver = lease.onRetire(retire);
  }

  final SiteLease _lease;
  final Future<DiscourseUser?> Function() _read;
  _CurrentUserRead? _active;
  _CurrentUserRead? _pending;
  void Function()? _removeRetirementObserver;
  bool _retired = false;

  bool get isCurrent => !_retired && _lease.isCurrent;

  Future<DiscourseUser?> request({bool force = false}) {
    if (!isCurrent) return Future.value();
    final active = _active;
    if (active != null) {
      if (!force) return active.join();
      return (_pending ??= _CurrentUserRead()).join();
    }
    final task = _CurrentUserRead();
    _start(task);
    return task.future;
  }

  void _start(_CurrentUserRead task) {
    _active = task;
    unawaited(_run(task));
  }

  Future<void> _run(_CurrentUserRead task) async {
    try {
      final user = await task.intent.run(_read);
      if (!isCurrent) return;
      task.result.complete(user);
    } catch (error, stackTrace) {
      if (!isCurrent) return;
      task.result.completeError(error, stackTrace);
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
    _active?.result.complete();
    _pending?.result.complete();
    _active = null;
    _pending = null;
  }
}

final class _CurrentUserRead {
  final result = Completer<DiscourseUser?>();
  final intent = RequestIntentGroup(RequestIntent.current);

  Future<DiscourseUser?> get future => result.future;

  Future<DiscourseUser?> join() {
    intent.join(RequestIntent.current);
    return future;
  }
}
