import 'dart:async';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_directory.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_navigation.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_export_platform.dart';
import 'support/event_fixtures.dart';

const _calendar = 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n';
const _failure = 'Unable to load this event. Try again.';

enum _View { card, directory }

void main() {
  for (final view in _View.values) {
    group('${view.name} calendar export', () {
      late _CalendarTransport transport;
      late EventTestPorts ports;
      late List<EventTestPorts> owners;
      late EventExportFileSelector selector;
      late FileSelectorPlatform previousSelector;
      late String site;
      late int eventId;
      late bool mine;

      setUp(() {
        transport = _CalendarTransport();
        ports = EventTestPorts(transport: transport);
        owners = [ports];
        site = eventSite;
        eventId = 42;
        mine = false;
        selector = EventExportFileSelector();
        previousSelector = FileSelectorPlatform.instance;
        FileSelectorPlatform.instance = selector;
      });

      tearDown(() {
        FileSelectorPlatform.instance = previousSelector;
        for (final owner in owners) {
          owner.close();
        }
      });

      Future<void> pump(WidgetTester tester) async {
        final navigation = EventNavigation(
          host: _Routes(),
          editor: PluginPostEditorHost(open: (_, _, {focusText}) => false),
          controller: ports.controller,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: view == _View.card
                  ? SingleChildScrollView(
                      child: PostEventCard(
                        site: site,
                        event: PostEvent.decode(_event(eventId))!,
                        controller: ports.controller,
                        navigation: navigation,
                      ),
                    )
                  : EventDirectory(
                      site: site,
                      mine: mine,
                      controller: ports.controller,
                      navigation: navigation,
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      VoidCallback? export(WidgetTester tester) {
        if (view == _View.card) {
          return tester.widget<EventCard>(find.byType(EventCard)).onExport;
        }
        final finder = find.byWidgetPredicate(
          (widget) =>
              widget is PopupMenuButton && widget.tooltip == 'Calendar actions',
        );
        final menu = tester.widget<PopupMenuButton<VoidCallback>>(finder);
        final item = menu
            .itemBuilder(tester.element(finder))
            .whereType<PopupMenuItem<VoidCallback>>()
            .firstWhere(
              (item) =>
                  item.child is Text &&
                  ((item.child as Text).data ?? '').startsWith('Export'),
            );
        return item.enabled ? item.value : null;
      }

      void replace(String change) {
        switch (change) {
          case 'event':
            eventId = 43;
          case 'filter':
            mine = true;
          case 'site':
            site = 'https://other.example';
          case 'controller':
            ports = EventTestPorts(transport: transport);
            owners.add(ports);
          case 'account refresh':
            ports.controller.pluginCurrentUserRefreshed(site);
          case 'account reset':
            ports.requests.forget(site);
            ports.controller.forget(site);
          default:
            throw ArgumentError.value(change);
        }
      }

      final changes = [
        view == _View.card ? 'event' : 'filter',
        'site',
        'controller',
        'account refresh',
        'account reset',
      ];
      for (final change in changes) {
        _testDesktopWidgets('drops a fetched calendar after $change', (
          tester,
        ) async {
          await pump(tester);
          export(tester)!();
          await tester.pump();
          expect(transport.exports, hasLength(1));

          replace(change);
          await pump(tester);
          transport.exports.single.complete(_calendar);
          await tester.pumpAndSettle();

          expect(selector.filenames, isEmpty);
          expect(find.text(_failure), findsNothing);
          expect(export(tester), isNotNull);
          expect(tester.takeException(), isNull);
        });

        _testDesktopWidgets('a selected file is never written after $change', (
          tester,
        ) async {
          final writes = <(String, List<int>)>[];
          final location = Completer<String?>();
          selector.choosePath = () => location.future;
          await pump(tester);
          // Override only this operation's I/O, so the byte-write boundary is
          // observable without racing the test clock against the filesystem.
          IOOverrides.runZoned(
            export(tester)!,
            createFile: (path) => _SavedFile(path, writes),
          );
          await tester.pump();
          transport.exports.single.complete(_calendar);
          await tester.pump();
          expect(selector.filenames, hasLength(1));

          replace(change);
          await pump(tester);
          location.complete('/selected/calendar.ics');
          await tester.pumpAndSettle();
          expect(writes, isEmpty);
          expect(find.text(_failure), findsNothing);
          expect(export(tester), isNotNull);
        });
      }

      _testDesktopWidgets('writes one current export at the selected path', (
        tester,
      ) async {
        final writes = <(String, List<int>)>[];
        selector.choosePath = () async => '/selected/calendar.ics';
        await pump(tester);
        IOOverrides.runZoned(
          export(tester)!,
          createFile: (path) => _SavedFile(path, writes),
        );
        await tester.pump();
        transport.exports.single.complete(_calendar);
        await tester.pumpAndSettle();
        expect(writes, hasLength(1));
        expect(writes.single.$1, '/selected/calendar.ics');
        expect(writes.single.$2, _calendar.codeUnits);
        expect(export(tester), isNotNull);
      });

      _testDesktopWidgets('reports a current failure and allows a retry', (
        tester,
      ) async {
        await pump(tester);
        export(tester)!();
        await tester.pump();
        transport.exports.single.completeError(StateError('Current failure'));
        await tester.pumpAndSettle();
        expect(find.text(_failure), findsOneWidget);
        expect(export(tester), isNotNull);
        export(tester)!();
        await tester.pump();
        transport.exports.last.complete(_calendar);
        await tester.pumpAndSettle();
        expect(selector.filenames, hasLength(1));
      });

      if (view == _View.card) {
        for (final change in ['event', 'account refresh']) {
          _testDesktopWidgets(
            'ignores a menu callback captured before $change',
            (tester) async {
              await pump(tester);
              final oldCallback = export(tester)!;
              replace(change);
              await pump(tester);
              oldCallback();
              await tester.pumpAndSettle();
              expect(transport.exports, isEmpty);
              expect(export(tester), isNotNull);
            },
          );
        }
      }

      _testDesktopWidgets('admits only one export before the next frame', (
        tester,
      ) async {
        await pump(tester);
        final start = export(tester)!;
        start();
        start();
        await tester.pump();
        final requests = transport.exports.length;
        for (final request in transport.exports) {
          request.complete(_calendar);
        }
        await tester.pumpAndSettle();
        expect(requests, 1);
        expect(selector.filenames, [
          view == _View.card ? 'event-42.ics' : 'upcoming-events.ics',
        ]);
        expect(export(tester), isNotNull);
      });

      _testDesktopWidgets(
        'an old failure cannot publish or finish a newer export',
        (tester) async {
          await pump(tester);
          export(tester)!();
          await tester.pump();
          replace(view == _View.card ? 'event' : 'filter');
          await pump(tester);
          final next = export(tester);
          // Complete all admitted work even when a broken busy flag blocks B.
          next?.call();
          await tester.pump();
          transport.exports.first.completeError(
            StateError('Old export failed'),
          );
          await tester.pump();
          final busy = export(tester) == null;
          final oldFailure = find.text(_failure).evaluate().length;
          if (transport.exports.length > 1) {
            transport.exports.last.complete(_calendar);
          }
          await tester.pumpAndSettle();

          expect(next, isNotNull);
          expect(busy, isTrue);
          expect(oldFailure, 0);
          expect(selector.filenames, [
            view == _View.card ? 'event-43.ics' : 'my-events.ics',
          ]);
          expect(export(tester), isNotNull);
        },
      );

      for (final change in ['site', 'account refresh', 'account reset']) {
        _testDesktopWidgets(
          'a save dialog failure stays silent after $change',
          (tester) async {
            final location = Completer<String?>();
            selector.choosePath = () => location.future;
            await pump(tester);
            export(tester)!();
            await tester.pump();
            transport.exports.single.complete(_calendar);
            await tester.pump();
            expect(selector.filenames, hasLength(1));

            replace(change);
            await pump(tester);
            final next = export(tester);
            next?.call();
            await tester.pump();
            location.completeError(StateError('Old save dialog failed'));
            await tester.pump();
            final busy = export(tester) == null;
            final oldFailure = find.text(_failure).evaluate().length;
            selector.choosePath = () async => null;
            if (transport.exports.length > 1) {
              transport.exports.last.complete(_calendar);
            }
            await tester.pumpAndSettle();
            expect(next, isNotNull);
            expect(busy, isTrue);
            expect(oldFailure, 0);
            expect(find.text(_failure), findsNothing);
            expect(export(tester), isNotNull);
            expect(tester.takeException(), isNull);
          },
        );
      }

      _testDesktopWidgets('a disposed view never opens a save dialog', (
        tester,
      ) async {
        await pump(tester);
        export(tester)!();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        transport.exports.single.complete(_calendar);
        await tester.pumpAndSettle();
        expect(selector.filenames, isEmpty);
        expect(tester.takeException(), isNull);
      });
    });
  }
}

final class _SavedFile extends Fake implements File {
  _SavedFile(this.path, this.writes);

  @override
  final String path;
  final List<(String, List<int>)> writes;

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    writes.add((path, List.of(bytes)));
    return this;
  }
}

final class _CalendarTransport extends RecordingPluginTransport
    implements PluginTextTransport {
  _CalendarTransport() {
    for (final id in [42, 43]) {
      responders['GET /discourse-post-event/events/$id.json'] = (_) => {
        'event': _event(id),
      };
    }
    for (final mine in [false, true]) {
      responders['GET /discourse-post-event/events.json?include_ongoing=true&order=asc&limit=200${mine ? '&attending_user=lee' : ''}&after=2026-08-30T22%3A00%3A00.000Z&before=2026-10-04T22%3A00%3A00.000Z'] =
          (_) => {'events': <Object?>[]};
    }
  }

  final exports = <Completer<String>>[];

  @override
  Future<String> pluginGetText({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    final result = Completer<String>();
    exports.add(result);
    return result.future;
  }
}

Map<String, dynamic> _event(int id) => eventJson(
  overrides: {
    'id': id,
    'post': {
      'id': id,
      'post_number': 1,
      'topic': {'id': 700, 'title': 'Managers'},
    },
  },
);

final class _Routes implements PluginRouteNavigationHost {
  @override
  final sites = const [
    PluginRouteSite(url: eventSite, title: 'Forum', isConnected: true),
  ];
  @override
  PluginRouteSite get currentSite => sites.single;
  @override
  ContentRoute? currentContent;
  @override
  void selectInstance(int index) {}
  @override
  void pushContent(ContentRoute route) => currentContent = route;
  @override
  void replaceCurrentContent(ContentRoute route) => currentContent = route;
  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) {}
}

void _testDesktopWidgets(
  String description,
  Future<void> Function(WidgetTester) test,
) => testWidgets(
  description,
  test,
  variant: TargetPlatformVariant.only(TargetPlatform.macOS),
);
