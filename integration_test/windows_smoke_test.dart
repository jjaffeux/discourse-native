import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/main.dart' as app;
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/windows_dpapi_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows starts and reopens user-encrypted credentials', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'discourse-native-dpapi-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/credentials.dat');
    final secret = 'private-beta-${List.filled(8000, 'x').join()}';
    final storage = WindowsDpapiStorage(file: file);
    await storage.write('smoke', secret);
    expect(await WindowsDpapiStorage(file: file).read('smoke'), secret);
    expect(
      base64Decode(await file.readAsString()),
      isNot(utf8.encode(jsonEncode({'smoke': secret}))),
    );
    await storage.delete('smoke');
    expect(await WindowsDpapiStorage(file: file).read('smoke'), isNull);
    app.main();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(DiscourseApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
