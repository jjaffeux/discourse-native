import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/foundation/private_file_document.dart';

Future<void> main(List<String> arguments) async {
  await File('${arguments[0]}.${arguments[1]}.ready').writeAsString('ready');
  final waiting = Stopwatch()..start();
  for (final series in ['first', 'second']) {
    while (!await File('${arguments[0]}.$series.ready').exists()) {
      if (waiting.elapsed > const Duration(seconds: 10)) {
        throw StateError('The other document writer did not start.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
  final document = PrivateFileDocument<Map<String, String>>(
    target: () => File(arguments[0]),
    empty: () => <String, String>{},
    decode: (contents) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return Map<String, String>.from(
        jsonDecode(contents) as Map<String, Object?>,
      );
    },
    encode: (values) async => jsonEncode(values),
  );
  for (var index = 0; index < 12; index++) {
    await document.update<void>((values) {
      values['${arguments[1]}-$index'] = '$index';
      return PrivateFileResult.done;
    });
  }
}
