import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../tool/performance_improvement_workloads.dart';

void main() {
  test('ten production model workloads', () async {
    final results = await measurePerformanceImprovements();
    // ignore: avoid_print
    print('PERFORMANCE_IMPROVEMENTS ${jsonEncode(results)}');
  });
}
