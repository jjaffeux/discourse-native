import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/composer_layout_store.dart';
import '../models/composer_placement.dart';

/// App-owned presentation preferences, independent of persisted draft content.
class ComposerPresentationController extends ChangeNotifier {
  ComposerPresentationController({this.store = const ComposerLayoutStore()});

  static const sideMinimum = 360.0;
  static const readerMinimum = 320.0;
  static const sideBreakpoint = sideMinimum + readerMinimum + 1;

  final ComposerLayoutStore store;
  ComposerLayoutPreference _preference = const ComposerLayoutPreference();
  bool _disposed = false;
  int _revision = 0;

  ComposerLayoutPreference get preference => _preference;

  Future<void> load() async {
    final revision = _revision;
    final loaded = await store.read();
    if (_disposed || revision != _revision) return;
    _preference = loaded;
    notifyListeners();
  }

  ComposerPlacement effectivePlacement({
    required bool mobile,
    required double width,
  }) => mobile || (_preference.placement.isSide && width < sideBreakpoint)
      ? ComposerPlacement.bottom
      : _preference.placement;

  void dock(ComposerPlacement placement) {
    _update(_preference.copyWith(placement: placement));
  }

  void resize({
    required ComposerPlacement placement,
    required double extent,
    required bool topic,
    bool persist = true,
  }) {
    if (!extent.isFinite || extent <= 0) {
      return;
    }
    _update(
      placement.isSide
          ? _preference.copyWith(sideWidth: extent)
          : topic
          ? _preference.copyWith(topicHeight: extent)
          : _preference.copyWith(replyHeight: extent),
      persist: persist,
    );
  }

  void _update(ComposerLayoutPreference value, {bool persist = true}) {
    _revision++;
    _preference = value;
    notifyListeners();
    if (persist) unawaited(store.write(value));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
