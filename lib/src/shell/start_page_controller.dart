import 'package:flutter/foundation.dart';

/// Session-scoped launcher layout, shared by a forum's Start tabs.
final class StartPageController extends ChangeNotifier {
  final _pins = <String, List<String>>{};

  List<String> pinsFor(String siteUrl) =>
      List.unmodifiable(_pins[siteUrl] ?? const ['recently-closed']);

  void togglePin(String siteUrl, String id) {
    final pins = _pins.putIfAbsent(siteUrl, () => ['recently-closed']);
    if (!pins.remove(id)) pins.add(id);
    notifyListeners();
  }

  void forget(String siteUrl) {
    if (_pins.remove(siteUrl) != null) notifyListeners();
  }
}
