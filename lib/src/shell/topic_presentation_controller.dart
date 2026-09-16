import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/topic_presentation_store.dart';
import '../models/topic_presentation.dart';

class TopicPresentationController extends ChangeNotifier {
  TopicPresentationController({this.store = const TopicPresentationStore()});

  static const minimumReaderWidth = 825.0;

  final TopicPresentationStore store;
  TopicPresentation _preference = TopicPresentation.docked;
  bool _disposed = false;
  int _revision = 0;

  TopicPresentation get preference => _preference;

  Future<void> load() async {
    final revision = _revision;
    final value = await store.read();
    if (_disposed || revision != _revision) return;
    _preference = value;
    notifyListeners();
  }

  void select(TopicPresentation value) {
    _revision++;
    _preference = value;
    notifyListeners();
    unawaited(store.write(value));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
