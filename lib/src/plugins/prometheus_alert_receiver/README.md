# Prometheus alert receiver

This bundled module supports
[discourse-prometheus-alert-receiver](https://github.com/discourse/discourse-prometheus-alert-receiver).
Its tables are generated from the topic-view serializer's `alert_data` array;
they are absent from the opening post's `cooked` HTML. `TopicRecordPlugin`
decodes that array and `PostDecorationPlugin` renders it after the opening
post. Ordinary replies and topics without alert data receive no decoration.

The native tables follow upstream's Firing, Silenced, Stale, and History order,
group by datacenter, show descriptions only where present, and retain UTC date
ranges. Groups can be collapsed; a status with more than thirty alerts also
collapses subsequent statuses by default. Explicit user choices survive topic
refreshes. Narrow windows scroll tables horizontally and all cell text remains
selectable. Recently silenced firing alerts display the ninety-day indicator.

Alertmanager, graph, and annotation links use the ordinary link-opening path.
The plugin owns its three site regex settings and their persistence. Matching
Prometheus, Grafana, and Kibana URLs receive upstream's time-window parameters;
Kibana retains the serialized fractional timestamp precision. Unsupported or
invalid URLs leave the alert readable. Quoting an alert uses the core
`PluginPostQuoteHost`, which checks the visible site, topic, post, and reply
permission before using the existing draft-preserving quote composer.

Core already refetches topics on `/topic/:id` messages with `reload_topic: true`,
which is the signal emitted by this plugin when only alert data changes. The
module therefore needs no independent API calls or live subscription.

Implementation and fixtures were checked against upstream commit
[`bd31ece26c61fd8d293c9d4b50244254c59d6065`](https://github.com/discourse/discourse-prometheus-alert-receiver/tree/bd31ece26c61fd8d293c9d4b50244254c59d6065),
in particular `plugin.rb`, `app/serializers/alert_receiver_alert.rb`,
`app/jobs/concerns/alert_post_mixin.rb`, `config/settings.yml`,
`assets/javascripts/discourse/components/alert-receiver/`, and
`test/javascripts/acceptance/alert-receiver-test.js`. No cooked-markup parser
or composer authoring syntax is registered.

Focused checks:

```sh
flutter test test/alert_data_test.dart test/alert_links_test.dart \
  test/alert_tables_test.dart test/prometheus_alert_receiver_plugin_test.dart
```
