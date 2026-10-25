import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final directory = Directory(
      Platform.environment['BOARDS_REVIEW_DIR'] ??
          '/private/tmp/boards-native-review',
    );
    await directory.create(recursive: true);
    for (final screenshot
        in (data?['screenshots'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[]) {
      await File(
        '${directory.path}/${screenshot['screenshotName']}.png',
      ).writeAsBytes((screenshot['bytes'] as List).cast<int>());
    }
  },
);
