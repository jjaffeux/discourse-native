import 'dart:collection';

/// Counts the thread records visited by list projection and badge calculations.
class CountingThreadOverview extends MapView<int, DateTime> {
  CountingThreadOverview(super.map);

  int visits = 0;

  @override
  Iterable<MapEntry<int, DateTime>> get entries sync* {
    for (final entry in super.entries) {
      visits++;
      yield entry;
    }
  }

  @override
  Iterable<DateTime> get values sync* {
    for (final value in super.values) {
      visits++;
      yield value;
    }
  }
}
