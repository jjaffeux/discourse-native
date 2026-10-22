import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import 'event_controller.dart';
import 'event_data.dart';

typedef _ParticipantQuery = ({String filter, String? type});

sealed class _Result {
  const _Result();
}

final class _Unavailable extends _Result {
  const _Unavailable();
}

final class _Loading extends _Result {
  const _Loading();
}

final class _Ready extends _Result {
  const _Ready(this.rows);
  final List<EventInvitee> rows;
}

final class _Failed extends _Result {
  const _Failed(this.error);
  final String error;
}

final class EventParticipantSession extends ChangeNotifier {
  EventParticipantSession(this.handle, {String filter = '', String? type})
    : _query = (filter: _normalize(filter), type: type) {
    handle.changes.addListener(_availabilityChanged);
    unawaited(refresh());
  }

  final EventHandle handle;
  _ParticipantQuery _query;
  _Result _result = const _Unavailable();
  Timer? _debounce;
  int _generation = 0;
  bool _disposed = false;

  bool get available =>
      !_disposed &&
      handle.isCurrent &&
      handle.authoritative &&
      handle.event?.displayInvitees == true;
  String? get type => _query.type;
  bool get loading => _result is _Loading;
  List<EventInvitee>? get rows => switch (_result) {
    _Ready(:final rows) => rows,
    _ => null,
  };
  String? get error => switch (_result) {
    _Unavailable() => appL10n.participantDetailsAreNoLongerAvailable,
    _Failed(:final error) => error,
    _ => null,
  };

  static String _normalize(String filter) =>
      filter.trim().replaceFirst(RegExp(r'^@'), '');

  void _availabilityChanged() {
    if (_disposed) return;
    if (!available) {
      _withdraw();
    } else if (_result is _Unavailable) {
      unawaited(refresh());
    }
  }

  void _withdraw() {
    _debounce?.cancel();
    _generation++;
    _result = const _Unavailable();
    notifyListeners();
  }

  void changeSearch(String filter, {bool immediately = false}) {
    if (_disposed) return;
    _query = (filter: _normalize(filter), type: _query.type);
    if (immediately) {
      unawaited(refresh());
      return;
    }
    _debounce?.cancel();
    final generation = ++_generation;
    if (!available) {
      _withdraw();
      return;
    }
    _result = const _Loading();
    notifyListeners();
    if (_accepts(generation)) {
      _debounce = Timer(const Duration(milliseconds: 250), refresh);
    }
  }

  void selectType(String? value) {
    if (_disposed) return;
    final type = value == 'all' ? null : value;
    if (type == _query.type) return;
    _query = (filter: _query.filter, type: type);
    unawaited(refresh());
  }

  bool _accepts(int generation) =>
      !_disposed && generation == _generation && available;

  Future<void> refresh() async {
    if (_disposed) return;
    _debounce?.cancel();
    if (!available) {
      _withdraw();
      return;
    }
    final generation = ++_generation;
    final query = _query;
    _result = const _Loading();
    notifyListeners();
    if (!_accepts(generation)) return;
    try {
      final rows = await handle.controller.participants(
        handle,
        filter: query.filter,
        type: query.type,
      );
      if (!_accepts(generation)) return;
      _result = _Ready(List.unmodifiable(rows));
    } catch (error) {
      if (!_accepts(generation)) return;
      _result = _Failed(eventError(error, reading: true));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _debounce?.cancel();
    handle.changes.removeListener(_availabilityChanged);
    super.dispose();
  }
}
