import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'performance_improvement_workloads.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = await measurePerformanceImprovements();
  // ignore: avoid_print
  print('PERFORMANCE_IMPROVEMENTS ${jsonEncode(results)}');
  exit(0);
}
