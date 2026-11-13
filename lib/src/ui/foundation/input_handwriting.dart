import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

final inputHandwriting = InputHandwriting();

/// Retains handwriting unless the native model confirms an unsupported iPhone.
class InputHandwriting extends ValueNotifier<bool> {
  InputHandwriting({Future<String> Function()? loadIosModel})
    : _loadIosModel = loadIosModel ?? _iosModel,
      super(true);

  final Future<String> Function() _loadIosModel;
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    if (_loading case final pending?) return pending;
    final completion = Completer<void>();
    _loading = completion.future;
    completion.complete(_load());
    return completion.future;
  }

  Future<void> _load() async {
    final String model;
    try {
      model = await _loadIosModel();
    } catch (_) {
      return;
    }
    value = model != 'iPhone';
  }

  static Future<String> _iosModel() async =>
      (await DeviceInfoPlugin().iosInfo).model;
}
