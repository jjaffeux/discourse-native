import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'perf_round_three_app_workloads.dart';
import 'perf_round_three_model_workloads.dart';
import 'perf_round_three_service_workloads.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final result = {
    ...await measureRoundThreeAppPerformance(),
    ...measureRoundThreeModelPerformance(),
    ...await measureRoundThreeServicePerformance(),
  };
  // ignore: avoid_print
  print('ADDITIONAL_PERFORMANCE ${jsonEncode(result)}');
  exit(0);
}
