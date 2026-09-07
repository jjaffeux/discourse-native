import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_data.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_links.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/alert_fixtures.dart';

void main() {
  final now = DateTime.utc(2020, 7, 27, 18);
  final alert = PrometheusAlert.decode(alertJson(status: 'resolved'))!;
  const settings = AlertLinkSettings(grafana: r'/d/');

  test(
    'Prometheus uses the alert range with five minutes padding on each side',
    () {
      final uri = settings.process(alert.generatorUrl, alert, now: now)!;
      expect(uri.queryParameters, {
        'g0.expr': 'mymetric',
        'g0.tab': '0',
        'g0.range_input': '1127s',
        'g0.end_input': '2020-07-27T17:40:35.870Z',
      });
    },
  );

  test(
    'Grafana preserves dashboard variables and applies millisecond bounds',
    () {
      final uri = settings.process(
        'https://metrics.example.com/d/db?var-host=one&var-host=two',
        alert,
        now: now,
      )!;
      expect(uri.queryParametersAll, {
        'var-host': ['one', 'two'],
        'from': ['${alert.start!.millisecondsSinceEpoch}'],
        'to': ['${alert.end!.millisecondsSinceEpoch}'],
      });
      final firing = PrometheusAlert.decode(alertJson())!;
      expect(
        settings
            .process(uri.toString(), firing, now: now)!
            .queryParameters['to'],
        '${now.millisecondsSinceEpoch}',
      );
    },
  );

  test('Kibana retains its view and nanosecond precision in the fragment', () {
    final uri = settings.process(alert.linkUrl, alert, now: now)!;
    expect(uri.fragment.split('?').first, '/discover');
    expect(Uri.splitQueryString(uri.fragment.split('?').last), {
      '_a': '(columns:!())',
      '_g':
          "(time:(from:'2020-07-27T17:26:49.526234411Z',mode:absolute,to:'2020-07-27T17:35:35.870002386Z'))",
    });
  });

  test(
    'invalid URLs are disabled and unrelated links or invalid regexes fall back',
    () {
      for (final url in [
        null,
        '',
        'javascript:alert(1)',
        'file:///etc/hosts',
        'https://user:pass@example.com/',
        'https://',
        '/relative',
        'http://[',
      ]) {
        expect(settings.process(url, alert, now: now), isNull, reason: '$url');
      }
      const unrelated = 'https://example.com/runbook?from=relative#section';
      expect(
        settings.process(unrelated, alert, now: now).toString(),
        unrelated,
      );
      const invalid = AlertLinkSettings(
        prometheus: '[',
        grafana: '(',
        kibana: '*',
      );
      expect(
        invalid.process(alert.generatorUrl, alert, now: now).toString(),
        alert.generatorUrl,
      );
      final missingTime = PrometheusAlert.decode(
        alertJson()..['starts_at'] = 'invalid',
      )!;
      expect(
        settings.process(alert.generatorUrl, missingTime, now: now).toString(),
        alert.generatorUrl,
      );
      expect(
        settings.process(
          'https://logs.example.com/app/kibana#/discover?_g=%FF',
          alert,
          now: now,
        ),
        isNotNull,
      );
    },
  );

  test(
    'site regexes survive persistence and explicit blank settings disable rewriting',
    () {
      const codec = AlertLinkSettingsCodec();
      expect(codec.decode(codec.encode(settings)), settings);
      final blank = AlertLinkSettings.decode({
        'prometheus_alert_receiver_prometheus_regex': '',
      });
      expect(
        blank.process(alert.generatorUrl, alert, now: now).toString(),
        alert.generatorUrl,
      );
      expect(codec.decode(false), isNull);
    },
  );
}
