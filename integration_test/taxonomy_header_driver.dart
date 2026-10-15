import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final directory = Directory(
      Platform.environment['TAXONOMY_REVIEW_DIR'] ??
          '/private/tmp/taxonomy-native-header',
    );
    await directory.create(recursive: true);
    final screenshots =
        (data?['screenshots'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    for (final screenshot in screenshots) {
      await File(
        '${directory.path}/${screenshot['screenshotName']}.png',
      ).writeAsBytes((screenshot['bytes'] as List).cast<int>());
    }
  },
);
