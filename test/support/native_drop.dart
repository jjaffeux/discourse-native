import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real file on disk for a native drop to carry, removed after the test.
///
/// `desktop_drop` delivers paths, not bytes, so whatever takes the drop reads
/// this file the way it would read one dragged in from the desktop.
String nativeDropFile(String name) {
  final directory = Directory.systemTemp.createTempSync('native-drop-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final file = File('${directory.path}/$name')
    ..writeAsBytesSync(const [1, 2, 3]);
  return file.path;
}

/// A native file drag, delivered over `desktop_drop`'s platform channel as
/// the host sends it.
///
/// The plugin fans every event out to every enabled `DropTarget` in the app,
/// so driving the channel — rather than calling one target's callbacks — is
/// what shows which targets a real drag reaches.
final class NativeFileDrag {
  NativeFileDrag(this.tester);

  final WidgetTester tester;
  bool _entered = false;

  /// Brings the drag over [position], entering the window on the first move.
  Future<void> moveTo(Offset position) async {
    await _send(_entered ? 'updated' : 'entered', <double>[
      position.dx,
      position.dy,
    ]);
    _entered = true;
    await tester.pump();
  }

  /// Releases [paths] where the drag last moved.
  Future<void> drop(List<String> paths) async {
    await _send('performOperation', paths);
    _entered = false;
    await tester.pump();
  }

  Future<void> _send(String method, Object arguments) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'desktop_drop',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
}

/// Drags [paths] in from outside the window and releases them at [position].
Future<void> dropNativeFiles(
  WidgetTester tester,
  Offset position,
  List<String> paths,
) async {
  final drag = NativeFileDrag(tester);
  await drag.moveTo(position);
  await drag.moveTo(position);
  await drag.drop(paths);
}
