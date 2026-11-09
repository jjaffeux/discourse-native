import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

SingleActivator newDirectMessageShortcutForPlatform(TargetPlatform platform) =>
    primaryShortcutForPlatform(
      platform,
      LogicalKeyboardKey.keyK,
      includeRepeats: false,
    );
