part of 'account_activity_controller.dart';

final class _NotificationFeedLoad {
  _NotificationFeedLoad(this.lease);

  final SiteLease lease;
  final Completer<void> _result = Completer<void>();
  void Function()? _remove;
  void Function()? _detach;

  Future<void> get future => _result.future;
  bool get isCurrent => !_result.isCompleted && lease.isCurrent;

  void observeRetirement(void Function() remove) {
    _remove = remove;
    _detach = lease.onRetire(finish);
  }

  void finish([Object? error, StackTrace? stackTrace]) {
    if (_result.isCompleted) return;
    _detach?.call();
    _detach = null;
    _remove?.call();
    _remove = null;
    if (error == null) {
      _result.complete();
    } else {
      _result.completeError(error, stackTrace!);
    }
  }
}
