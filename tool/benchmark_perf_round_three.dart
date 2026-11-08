import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'perf_round_three_app_workloads.dart';
import 'perf_round_three_model_workloads.dart';
import 'perf_round_three_service_workloads.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final focused = Platform.environment['PERF_FOCUS_ACTIVITY'] == '1';
  final only = focused
      ? const {
          'chat_sidebar_search_30',
          'chat_sidebar_search_cold',
          'activity_category_estimation_30',
          'activity_category_estimation_300',
        }
      : null;
  final result = {
    ...await measureRoundThreeAppPerformance(only: only),
    ...measureRoundThreeModelPerformance(only: only),
    if (!focused) ...await measureRoundThreeServicePerformance(),
  };
  // ignore: avoid_print
  print('ADDITIONAL_PERFORMANCE ${jsonEncode(result)}');
  exit(0);
}
