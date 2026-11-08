import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/linux_preferences_store.dart';
import 'package:discourse_native/src/data/request_intent.dart';
import 'package:discourse_native/src/data/site_message_bus_bootstrap.dart';
import 'package:discourse_native/src/foundation/latest_wins_queued_lookup_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  test(
    'queued lookup and delivery retain their own submitter context',
    () async {
      final release = Completer<String>();
      final contexts = <(String, Object?, bool)>[];
      final delivered = <Object?>[];
      final controller = LatestWinsQueuedLookupController<String, String>(
        lookup: (value) {
          contexts.add((
            value,
            Zone.current[#owner],
            RequestIntent.current.isInteractive,
          ));
          return value == 'first' ? release.future : Future.value(value);
        },
        onResult: (_) => delivered.add(Zone.current[#owner]),
        onError: (error, _) => fail('$error'),
      );
      addTearDown(controller.dispose);
      RequestIntent.background().run(
        () => runZoned(
          () => controller.request('first'),
          zoneValues: {#owner: 'old'},
        ),
      );
      runZoned(() => controller.request('new'), zoneValues: {#owner: 'new'});
      release.complete('first');
      await pumpEventQueue();
      expect(contexts, [('first', 'old', false), ('new', 'new', true)]);
      expect(delivered, ['new']);
    },
  );

  test(
    'queued lookup failures cross error zones and delivery failures stay with submitter',
    () async {
      final release = Completer<String>();
      final callbackFailure = StateError('callback');
      final lookupFailure = StateError('lookup');
      final uncaught = <Object>[];
      final deliveredErrors = <Object>[];
      final results = <String>[];
      late final LatestWinsQueuedLookupController<String, String> controller;
      controller = LatestWinsQueuedLookupController(
        lookup: (value) => switch (value) {
          'first' => release.future,
          'bad' => Future.error(lookupFailure),
          _ => Future.value(value),
        },
        onResult: (value) {
          results.add(value);
          if (value == 'callback') {
            controller.request('after');
            throw callbackFailure;
          }
        },
        onError: (error, _) {
          deliveredErrors.add(error);
          controller.request('callback');
        },
      );
      addTearDown(controller.dispose);
      controller.request('first');
      runZonedGuarded(
        () => controller.request('bad'),
        (error, _) => uncaught.add(error),
      );
      release.complete('old');
      await pumpEventQueue();
      expect(deliveredErrors, [same(lookupFailure)]);
      expect(uncaught, [same(callbackFailure)]);
      expect(results, ['callback', 'after']);
    },
  );

  for (final clear in [false, true]) {
    test(
      '${clear ? 'clear' : 'read'} owns Linux filter policy before filesystem admission',
      () async {
        final root = await Directory.systemTemp.createTemp('round5-filter-');
        addTearDown(() => root.delete(recursive: true));
        final file = File('${root.path}/preferences.json');
        await file.writeAsString(jsonEncode({'flutter.a': 1, 'flutter.b': 2}));
        final release = Completer<File>();
        final store = LinuxPreferencesStore(file: () => release.future);
        final accepted = {'flutter.a'};
        final filter = PreferencesFilter(
          prefix: 'flutter.',
          allowList: accepted,
        );
        final Future<Object?> result = clear
            ? store.clearWithParameters(ClearParameters(filter: filter))
            : store.getAllWithParameters(GetAllParameters(filter: filter));
        accepted
          ..clear()
          ..add('flutter.b');
        release.complete(file);
        if (clear) {
          expect(await result, isTrue);
          expect(jsonDecode(await file.readAsString()), {'flutter.b': 2});
        } else {
          expect(await result, {'flutter.a': 1});
        }
      },
    );
  }

  test(
    'bootstrap retains immutable current-user knowledge and plugin claims',
    () {
      final counts = {'mentioned': 2};
      final names = {'discourse-bbcode-color'};
      final bootstrap = SiteMessageBusBootstrap(
        currentUser: null,
        currentUserState: {
          'grouped_unread_notifications': counts,
          'nested': [counts],
        },
        topicTrackingState: null,
        topicTrackingLastIds: {},
        notificationChannelPosition: null,
        serverPluginNames: names,
      );
      counts['mentioned'] = 99;
      names.clear();
      final firstChannel =
          bootstrap.currentUserState!['grouped_unread_notifications'] as Map;
      expect(firstChannel['mentioned'], 2);
      expect(() => firstChannel['mentioned'] = 77, throwsUnsupportedError);
      final secondChannel =
          (bootstrap.currentUserState!['nested'] as List).single as Map;
      expect(secondChannel['mentioned'], 2);
      expect(bootstrap.serverPluginNames, {'discourse-bbcode-color'});
      expect(bootstrap.serverPluginNames.clear, throwsUnsupportedError);
    },
  );
}
