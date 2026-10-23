// Writes a timeline summary per traced move of `integration_test/navigation_perf_test.dart`
// to `build/<move>.timeline_summary.json`, and the time to the new page to
// `build/navigation_latency.json`. `docs/performance.md` says how to run it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      if (data == null) return;
      for (final MapEntry(:key, :value) in data.entries) {
        if (value is Map<String, dynamic> && value.containsKey('traceEvents')) {
          final summary = driver.TimelineSummary.summarize(driver.Timeline.fromJson(value));
          await summary.writeTimelineToFile(key, pretty: true, includeSummary: true);
        }
      }
      final latency = data['latency_ms'];
      if (latency != null) {
        await Directory(testOutputsDirectory).create(recursive: true);
        await File('$testOutputsDirectory/navigation_latency.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(latency));
      }
    },
  );
}
