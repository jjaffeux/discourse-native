import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'additional_model_performance_workloads.dart';
import 'additional_selection_performance_workloads.dart';
import 'additional_service_performance_workloads.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = {
    ...measureAdditionalSelectionPerformance(),
    ...measureAdditionalModelPerformance(),
    ...await measureAdditionalServicePerformance(),
  };
  // ignore: avoid_print
  print('ADDITIONAL_PERFORMANCE ${jsonEncode(results)}');
  exit(0);
}
