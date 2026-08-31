import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resenha restores device choices asynchronously during controller
/// construction. A real platform-channel lookup can otherwise outlive a
/// widget test and leave its Flutter test process waiting during finalization.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));
  await testMain();
}
