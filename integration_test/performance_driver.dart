import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final driver = await FlutterDriver.connect();
  final profileCpu =
      Platform.environment['PROFILE_COMPOSER_EXTERNAL_CPU'] == '1';
  final service = driver.serviceClient;
  int? startMicros;
  Map<String, Object?>? cpu;
  late final Response response;
  try {
    if (profileCpu) {
      await service.setFlag('profiler', 'true');
      await service.setFlag('profile_period', '250');
      await service.clearCpuSamples(driver.appIsolate.id!);
      startMicros = (await service.getVMTimelineMicros()).timestamp!;
    }
    response = Response.fromJson(
      await driver.requestData(null, timeout: const Duration(minutes: 20)),
    );
    if (startMicros != null) {
      final endMicros = (await service.getVMTimelineMicros()).timestamp!;
      final samples = await service.getCpuSamples(
        driver.appIsolate.id!,
        startMicros,
        endMicros - startMicros,
      );
      final functions = samples.functions!;
      final used = {for (final sample in samples.samples!) ...?sample.stack};
      cpu = {
        'sampleCount': samples.sampleCount,
        'samplePeriod': samples.samplePeriod,
        'timeOriginMicros': samples.timeOriginMicros,
        'timeExtentMicros': samples.timeExtentMicros,
        'functions': [
          for (var i = 0; i < functions.length; i++)
            if (used.contains(i)) {'index': i, ...functions[i].toJson()},
        ],
        'samples': [for (final sample in samples.samples!) sample.toJson()],
      };
      if (response.data?['composerLifecycle']
          case final Map<String, dynamic> lifecycle) {
        lifecycle['instrumented'] = true;
      }
    }
  } finally {
    await driver.close();
  }
  await writeResponseData({
    ...?response.data,
    'composerExternalCpu': ?cpu,
    'integrationTest': {
      'passed': response.allTestsPassed,
      'failureCount': response.failureDetails?.length ?? 0,
    },
  });
  if (!response.allTestsPassed) {
    stderr.writeln(response.formattedFailureDetails);
    exitCode = 1;
  }
}
