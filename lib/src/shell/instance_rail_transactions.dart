part of 'shell_controller.dart';

final class _InstanceRailTransactions {
  _InstanceRailTransactions(this._shell);

  final ShellController _shell;
  int _revision = 0;
  bool _savingOrder = false;
  bool _retired = false;
  List<String> _durableOrder = const [];
  final List<({int revision, Completer<bool> result})> _pending = [];

  bool get _active => !_retired;

  Future<bool> settleAddition(
    DiscourseInstance added, {
    required VoidCallback rollback,
  }) async {
    try {
      await _shell.instanceStore.save(List.of(_shell._instances));
      return true;
    } catch (_) {
      if (!_active) return false;
      if (!identical(_shell._instanceAt(added.url), added)) {
        return await _repair() != null;
      }
      rollback();
      await _repair();
      return false;
    }
  }

  Future<bool> settleRemoval(
    String siteUrl, {
    required bool Function() stillOwnsRemoval,
    required VoidCallback rollback,
    required VoidCallback forgetDurableRemoval,
  }) async {
    try {
      await _shell.instanceStore.save(List.of(_shell._instances));
      if (_active && _shell._instanceAt(siteUrl) == null) {
        forgetDurableRemoval();
      }
      return true;
    } catch (_) {
      if (!_active ||
          !stillOwnsRemoval() ||
          _shell._instanceAt(siteUrl) != null) {
        return false;
      }
      rollback();
      await _repair();
      return false;
    }
  }

  Future<bool> move(DiscourseInstance instance, int newIndex) {
    final instances = _shell._instances;
    if (!_active || !_shell.loaded || instances.length < 2) {
      return Future.value(false);
    }
    final oldIndex = instances.indexWhere((item) => item.url == instance.url);
    if (oldIndex < 0) return Future.value(false);
    final destination = newIndex.clamp(0, instances.length - 1);
    if (oldIndex == destination) return Future.value(true);

    if (!_savingOrder && _pending.isEmpty) {
      _durableOrder = [for (final item in instances) item.url];
    }
    final revision = ++_revision;
    final selectedSiteUrl = _shell.currentInstance?.url;
    final moved = instances.removeAt(oldIndex);
    instances.insert(destination, moved);
    _shell._followSelectedInstance(selectedSiteUrl);
    _shell._notify();
    if (!_active) return Future.value(false);

    final result = Completer<bool>();
    _pending.add((revision: revision, result: result));
    if (!_savingOrder) {
      _savingOrder = true;
      unawaited(_drain());
    }
    return result.future;
  }

  Future<void> _drain() async {
    try {
      while (_active && _pending.isNotEmpty) {
        final savedRevision = _revision;
        final snapshot = List.of(_shell._instances);
        final savedOrder = [for (final instance in snapshot) instance.url];
        try {
          await _shell.instanceStore.save(snapshot);
        } catch (_) {
          if (!_active) return;
          if (savedRevision != _revision) continue;
          final restored = _restoreOrder();
          _completeThrough(savedRevision, false);
          final repairOrder = await _repair();
          if (_active && restored && repairOrder != null) {
            _durableOrder = repairOrder;
          }
          continue;
        }
        if (!_active) return;
        _durableOrder = savedOrder;
        _completeThrough(savedRevision, true);
      }
    } finally {
      _savingOrder = false;
      if (_active && _pending.isNotEmpty) {
        _savingOrder = true;
        unawaited(_drain());
      }
    }
  }

  Future<List<String>?> _repair() async {
    if (!_active) return null;
    final snapshot = List.of(_shell._instances);
    final order = [for (final instance in snapshot) instance.url];
    try {
      await _shell.instanceStore.save(snapshot);
      return order;
    } catch (_) {
      return null;
    }
  }

  bool _restoreOrder() {
    final instances = _shell._instances;
    if (instances.length != _durableOrder.length) return false;
    final byUrl = {for (final instance in instances) instance.url: instance};
    if (byUrl.length != _durableOrder.length ||
        _durableOrder.any((url) => !byUrl.containsKey(url))) {
      return false;
    }
    final selectedSiteUrl = _shell.currentInstance?.url;
    instances
      ..clear()
      ..addAll(_durableOrder.map((url) => byUrl[url]!));
    _shell._followSelectedInstance(selectedSiteUrl);
    _shell._notify();
    return true;
  }

  void _completeThrough(int revision, bool persisted) {
    final completed = _pending
        .where((request) => request.revision <= revision)
        .toList();
    _pending.removeWhere((request) => request.revision <= revision);
    for (final request in completed) {
      request.result.complete(persisted);
    }
  }

  void retire() {
    _retired = true;
    _completeThrough(_revision, false);
  }
}
