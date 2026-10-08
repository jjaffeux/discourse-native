import 'package:flutter/foundation.dart';

/// Session-scoped launcher layout, shared by a forum's Start tabs.
final class StartPageController extends ChangeNotifier {
  final _pins = <String, List<String>>{};

  static const _defaultPins = ['recently-closed', 'topics'];

  List<String> pinsFor(String siteUrl) {
    final pins = _pins[siteUrl] ?? _defaultPins;
    return List.unmodifiable([
      if (pins.contains('recently-closed')) 'recently-closed',
      ...pins.where((id) => id != 'recently-closed'),
    ]);
  }

  void togglePin(String siteUrl, String id) {
    final pins = _pins.putIfAbsent(siteUrl, () => [..._defaultPins]);
    if (!pins.remove(id)) pins.add(id);
    notifyListeners();
  }

  void forget(String siteUrl) {
    if (_pins.remove(siteUrl) != null) notifyListeners();
  }
}
