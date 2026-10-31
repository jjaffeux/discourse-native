import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_api.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_data.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _rootPath = 'GET /n/conversation/7.json?sort=top&page=0';

void main() {
  testWidgets('pending sort keeps the displayed rows in place', (tester) async {
    final pending = Completer<Object?>();
    final transport = RecordingPluginTransport(
      responses: {'$_rootPath&track_visit=true': _roots(ignored: true)},
      responders: {
        'GET /n/conversation/7.json?sort=new&page=0&track_visit=true': (_) =>
            pending.future,
      },
    );
    final host = await PluginHostHarness.open(
      transport: transport,
      sites: [const PluginHostSite(url: _site)],
    );
    addTearDown(host.close);
    final reader = _Reader();
    addTearDown(reader.dispose);
    await tester.pumpWidget(
      host.scope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NestedRepliesReader(
              reader: reader,
              api: NestedRepliesApi(transport, reader.models),
              settings: const NestedRepliesSettings(enabled: true),
            ),
          ),
        ),
      ),
    );
    await _frames(tester);
    final row = find.byKey(const ValueKey(102));
    final position = tester.getTopLeft(row);
    final element = tester.element(row);
    await tester.tap(find.byKey(const ValueKey('nested-sort-button')));
    await _frames(tester);
    await tester.tap(find.text('Newest').hitTestable().last);
    await _frames(tester);
    expect(tester.element(row), same(element));
    expect(tester.getTopLeft(row), position);
    expect(find.byType(DSpinner), findsNothing);
    pending.complete({
      ..._roots(ignored: true),
      'sort': 'new',
      'effective_sort': 'new',
    });
    await _frames(tester);
    expect(find.text('Newest'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'phone context keeps descendants hidden until their replies are loaded',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic> node(
        int number, {
        List<Map<String, dynamic>> children = const [],
      }) => {
        'id': 100 + number,
        'post_number': number,
        'deleted_post_placeholder': true,
        'direct_reply_count': children.length,
        'total_descendant_count': children.length,
        'children': children,
      };
      final transport = RecordingPluginTransport(
        responses: {
          'GET /n/conversation/7/context/4.json?sort=top&track_visit=true': {
            'topic': {'id': 7, 'title': 'Conversation', 'is_nested_view': true},
            'target_post': node(
              4,
              children: [
                node(5, children: [node(6)]),
              ],
            ),
            'ancestor_chain': [node(2), node(3)],
            'ancestors_truncated': false,
            'siblings': <String, dynamic>{},
          },
          'GET /n/conversation/7/children/5.json?sort=top&page=0&depth=4': {
            'children': [node(6)],
            'page': 0,
            'has_more': false,
          },
        },
      );
      final host = await PluginHostHarness.open(
        transport: transport,
        sites: [const PluginHostSite(url: _site)],
      );
      addTearDown(host.close);
      final reader = _Reader(postNumber: 4, query: 'collapse_replies=true');
      addTearDown(reader.dispose);
      await tester.pumpWidget(
        host.scope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: NestedRepliesReader(
                reader: reader,
                api: NestedRepliesApi(transport, reader.models),
                settings: const NestedRepliesSettings(
                  enabled: true,
                  maxDepth: 10,
                ),
              ),
            ),
          ),
        ),
      );
      await _frames(tester);
      expect(find.byKey(const ValueKey(105)), findsOneWidget);
      expect(find.byKey(const ValueKey(106)), findsNothing);
      final child = find.byKey(const ValueKey(105));
      final load = find.descendant(
        of: child,
        matching: find.text('Load more replies'),
      );
      await tester.ensureVisible(load);
      await tester.tap(load);
      await _frames(tester);
      expect(find.byKey(const ValueKey(106)), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is DSeparator && widget.thickness == 6,
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  setUpAll(() async {
    await (FontLoader(
      'NestedRepliesReview',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'loader uses owner receipt, redaction, cursor, and metadata without replacing stream',
    () async {
      final transport = RecordingPluginTransport(
        responses: {_rootPath: _roots(ignored: true)},
      );
      final reader = _Reader(foreground: false);
      addTearDown(reader.dispose);
      final loader = NestedRepliesReaderLoader(
        reader: reader,
        api: NestedRepliesApi(transport, reader.models),
      );
      final receipt = await loader.roots(
        sort: NestedRepliesSort.top,
        page: 0,
        trackVisit: true,
      );
      expect(receipt!.acceptedPostIds, {102});
      final batch = reader.batches.single;
      expect(batch.posts.single.disposition, TopicContentDisposition.redacted);
      expect(batch.metadata!.stream, [999]);
      expect(batch.metadata!.messageBusLastId, 46);
      expect(
        transport.requests.single.path,
        '/n/conversation/7.json?sort=top&page=0',
      );
    },
  );

  test(
    'superseded request cannot publish canonical metadata or redacted posts',
    () async {
      final pending = Completer<Object?>();
      final transport = RecordingPluginTransport(
        responders: {_rootPath: (_) => pending.future},
      );
      final reader = _Reader();
      addTearDown(reader.dispose);
      var current = true;
      final loader = NestedRepliesReaderLoader(
        reader: reader,
        api: NestedRepliesApi(transport, reader.models),
      ).scoped(() => current);
      final reading = loader.roots(
        sort: NestedRepliesSort.top,
        page: 0,
        trackVisit: false,
      );
      current = false;
      final rejected = expectLater(reading, throwsStateError);
      pending.complete(_roots(ignored: true));
      await rejected;
      expect(reader.batches, isEmpty);
      expect(reader.posts, isEmpty);
    },
  );

  test(
    'foreground signed-in entry requests one visit, child paging never does',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          '$_rootPath&track_visit=true': _roots(),
          'GET /n/conversation/7/children/2.json?sort=top&page=0&depth=1': {
            'children': <Object?>[],
            'has_more': false,
            'page': 0,
          },
        },
      );
      final reader = _Reader();
      addTearDown(reader.dispose);
      final loader = NestedRepliesReaderLoader(
        reader: reader,
        api: NestedRepliesApi(transport, reader.models),
      );
      await loader.roots(
        sort: NestedRepliesSort.top,
        page: 0,
        trackVisit: true,
      );
      await loader.children(
        sort: NestedRepliesSort.top,
        parentPostNumber: 2,
        depth: 1,
        page: 0,
      );
      expect(transport.requests.first.path, contains('track_visit=true'));
      expect(transport.requests.last.path, isNot(contains('track_visit')));
    },
  );

  test(
    'terminal recommendations publish independently of omitted topic metadata',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /n/conversation/7.json?sort=top&page=1': {
            'roots': <Object?>[],
            'has_more_roots': false,
            'page': 1,
            'suggested_topics': [
              {'id': 20, 'title': 'Another conversation', 'slug': 'another'},
            ],
          },
        },
      );
      final reader = _Reader();
      addTearDown(reader.dispose);
      final loader = NestedRepliesReaderLoader(
        reader: reader,
        api: NestedRepliesApi(transport, reader.models),
      );
      await loader.roots(
        sort: NestedRepliesSort.top,
        page: 1,
        trackVisit: false,
      );
      expect(reader.batches.single.metadata!.stream, [999]);
      expect(
        reader
            .batches
            .single
            .metadata!
            .recommendations!
            .sources
            .single
            .topics
            .single
            .id,
        20,
      );
    },
  );

  testWidgets(
    'administrative invalidation preserves collapse without another visit',
    (tester) async {
      final transport = RecordingPluginTransport(
        responses: {
          '$_rootPath&track_visit=true': _roots(ignored: true, child: true),
          _rootPath: _roots(ignored: true, child: true),
        },
      );
      final host = await PluginHostHarness.open(
        transport: transport,
        sites: [const PluginHostSite(url: _site)],
      );
      addTearDown(host.close);
      final reader = _Reader();
      addTearDown(reader.dispose);
      final memory = NestedRepliesReaderMemory();
      addTearDown(memory.dispose);
      await tester.pumpWidget(
        host.scope(
          child: MaterialApp(
            theme: AppTheme.light.copyWith(
              textTheme: AppTheme.light.textTheme.apply(
                fontFamily: 'NestedRepliesReview',
              ),
            ),
            home: Scaffold(
              body: NestedRepliesReader(
                reader: reader,
                memory: memory,
                api: NestedRepliesApi(transport, reader.models),
                settings: const NestedRepliesSettings(enabled: true),
              ),
            ),
          ),
        ),
      );
      await _frames(tester);
      await tester.tap(find.text('Ignored post'));
      await _frames(tester);
      memory.invalidateTopic(_site, 7);
      await _frames(tester);
      expect(find.bySemanticsLabel(RegExp('^Expand post')), findsOneWidget);
      expect(find.text('Deleted post'), findsNothing);
      final reads = transport.requests
          .where((request) => request.path.startsWith('/n/'))
          .toList();
      expect(reads.map((request) => request.path), [
        '/n/conversation/7.json?sort=top&page=0&track_visit=true',
        '/n/conversation/7.json?sort=top&page=0',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'retired reader notifications cannot restore presentation cleared for an account change',
    (tester) async {
      final transport = RecordingPluginTransport(
        responses: {
          '$_rootPath&track_visit=true': _roots(ignored: true, child: true),
        },
      );
      final host = await PluginHostHarness.open(
        transport: transport,
        sites: [const PluginHostSite(url: _site)],
      );
      addTearDown(host.close);
      final memory = NestedRepliesReaderMemory();
      addTearDown(memory.dispose);
      Widget view(_Reader reader) => host.scope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NestedRepliesReader(
              key: ObjectKey(reader),
              reader: reader,
              memory: memory,
              api: NestedRepliesApi(transport, reader.models),
              settings: const NestedRepliesSettings(enabled: true),
            ),
          ),
        ),
      );
      final retired = _Reader();
      addTearDown(retired.dispose);
      await tester.pumpWidget(view(retired));
      await _frames(tester);
      await tester.tap(find.text('Ignored post'));
      await _frames(tester);
      expect(find.text('Deleted post'), findsNothing);
      retired.close();
      memory.forgetSite(_site);
      retired.foreground = false;
      retired.notifyListeners();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      final successor = _Reader();
      addTearDown(successor.dispose);
      await tester.pumpWidget(view(successor));
      await _frames(tester);
      expect(find.text('Deleted post'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ignored placeholder reveals only authorized cooked content and keeps replies controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final transport = RecordingPluginTransport(
        responses: {
          '$_rootPath&track_visit=true': _roots(ignored: true),
          'GET /posts/102/cooked.json': {
            'cooked': '<p>Authorized ignored content</p>',
          },
        },
      );
      final host = await PluginHostHarness.open(
        transport: transport,
        sites: [const PluginHostSite(url: _site)],
      );
      addTearDown(host.close);
      final reader = _Reader();
      addTearDown(reader.dispose);
      await tester.pumpWidget(
        host.scope(
          child: MaterialApp(
            theme: AppTheme.light.copyWith(
              textTheme: AppTheme.light.textTheme.apply(
                fontFamily: 'NestedRepliesReview',
              ),
            ),
            home: Scaffold(
              body: NestedRepliesReader(
                reader: reader,
                api: NestedRepliesApi(transport, reader.models),
                settings: const NestedRepliesSettings(enabled: true),
              ),
            ),
          ),
        ),
      );
      await _frames(tester);
      expect(find.text('Ignored post'), findsOneWidget);
      await _export(tester, 'phone-placeholder.png');
      expect(find.text('Continue this thread'), findsNothing);
      expect(find.text('Authorized ignored content'), findsNothing);
      await tester.tap(find.text('Show ignored post'));
      await _frames(tester);
      expect(
        find.textContaining('Authorized ignored content', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Show ignored post'), findsNothing);
      expect(find.byKey(const ValueKey('nested-collapse-102')), findsOneWidget);
      expect(reader.batches.last.posts, isEmpty);
      expect(reader.timings, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('post collapse hides and restores its preloaded descendants', (
    tester,
  ) async {
    final transport = RecordingPluginTransport(
      responses: {
        '$_rootPath&track_visit=true': _roots(ignored: true, child: true),
      },
    );
    final host = await PluginHostHarness.open(
      transport: transport,
      sites: [const PluginHostSite(url: _site)],
    );
    addTearDown(host.close);
    final reader = _Reader();
    addTearDown(reader.dispose);
    await tester.pumpWidget(
      host.scope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NestedRepliesReader(
              reader: reader,
              api: NestedRepliesApi(transport, reader.models),
              settings: const NestedRepliesSettings(enabled: true),
            ),
          ),
        ),
      ),
    );
    await _frames(tester);
    expect(find.text('Ignored post'), findsOneWidget);
    expect(find.text('Deleted post'), findsOneWidget);
    expect(find.text('1 reply'), findsNothing);
    expect(reader.visibleIds, {102, 103});
    await tester.tap(find.text('Ignored post'));
    await tester.pump();
    expect(reader.visibleIds, isEmpty);
    expect(find.text('Deleted post'), findsOneWidget);
    await _frames(tester);
    expect(find.text('Deleted post'), findsNothing);
    await tester.tap(find.bySemanticsLabel(RegExp('^Expand post')));
    await _frames(tester);
    expect(find.text('Ignored post'), findsOneWidget);
    expect(find.text('Deleted post'), findsOneWidget);
    expect(reader.visibleIds, {102, 103});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'return restores later root pages while sending a foreground visit',
    (tester) async {
      final firstPage = {..._roots(ignored: true), 'has_more_roots': true};
      final secondPage = <String, dynamic>{
        'roots': [
          <String, dynamic>{
            'id': 104,
            'post_number': 4,
            'deleted_post_placeholder': true,
            'direct_reply_count': 0,
            'total_descendant_count': 0,
            'children': <Object?>[],
          },
        ],
        'page': 1,
        'has_more_roots': false,
      };
      final transport = RecordingPluginTransport(
        responses: {
          '$_rootPath&track_visit=true': firstPage,
          'GET /n/conversation/7.json?sort=top&page=1': secondPage,
        },
      );
      final host = await PluginHostHarness.open(
        transport: transport,
        sites: [const PluginHostSite(url: _site)],
      );
      addTearDown(host.close);
      final memory = NestedRepliesReaderMemory();
      addTearDown(memory.dispose);
      final reader = _Reader();
      addTearDown(reader.dispose);
      Widget view() => host.scope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NestedRepliesReader(
              reader: reader,
              memory: memory,
              api: NestedRepliesApi(transport, reader.models),
              settings: const NestedRepliesSettings(enabled: true),
            ),
          ),
        ),
      );
      await tester.pumpWidget(view());
      await _frames(tester);
      await tester.tap(find.text('Load more replies'));
      await _frames(tester);
      expect(find.byKey(const ValueKey(104)), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(view());
      await _frames(tester);
      expect(find.byKey(const ValueKey(104)), findsOneWidget);
      expect(
        transport.requests
            .where((request) => request.method == 'GET')
            .map((request) => request.path),
        [
          '/n/conversation/7.json?sort=top&page=0&track_visit=true',
          '/n/conversation/7.json?sort=top&page=1',
          '/n/conversation/7.json?sort=top&page=0&track_visit=true',
          '/n/conversation/7.json?sort=top&page=1',
        ],
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'returning to a hidden reader surfaces roots missed while hidden',
    (tester) async {
      final transport = RecordingPluginTransport(
        responses: {'$_rootPath&track_visit=true': _roots(ignored: true)},
      );
      final host = await PluginHostHarness.open(
        transport: transport,
        sites: [const PluginHostSite(url: _site)],
      );
      addTearDown(host.close);
      final reader = _Reader();
      addTearDown(reader.dispose);
      await tester.pumpWidget(
        host.scope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: NestedRepliesReader(
                reader: reader,
                api: NestedRepliesApi(transport, reader.models),
                settings: const NestedRepliesSettings(enabled: true),
              ),
            ),
          ),
        ),
      );
      await _frames(tester);
      expect(find.byKey(const ValueKey(102)), findsOneWidget);
      reader.foreground = false;
      reader.notifyListeners();
      transport.responses['$_rootPath&track_visit=true'] = {
        ..._roots(ignored: true),
        'roots': [
          {
            'id': 104,
            'post_number': 4,
            'deleted_post_placeholder': true,
            'children': <Object?>[],
          },
          ..._roots(ignored: true)['roots'] as List,
        ],
      };
      reader.foreground = true;
      reader.notifyListeners();
      await _frames(tester);
      expect(find.byKey(const ValueKey(102)), findsOneWidget);
      expect(find.byKey(const ValueKey(104)), findsNothing);
      final banner = find.text('1 New replies');
      expect(banner, findsOneWidget);
      await tester.tap(banner);
      await tester.pump();
      expect(find.byKey(const ValueKey(104)), findsOneWidget);
      expect(
        transport.requests
            .where((request) => request.path.contains('track_visit=true'))
            .length,
        2,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('malformed query falls back to the default sort', (tester) async {
    final transport = RecordingPluginTransport(
      responses: {'$_rootPath&track_visit=true': _roots(ignored: true)},
    );
    final host = await PluginHostHarness.open(
      transport: transport,
      sites: [const PluginHostSite(url: _site)],
    );
    addTearDown(host.close);
    final reader = _Reader(query: 'sort=%FF');
    addTearDown(reader.dispose);
    await tester.pumpWidget(
      host.scope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NestedRepliesReader(
              reader: reader,
              api: NestedRepliesApi(transport, reader.models),
              settings: const NestedRepliesSettings(enabled: true),
            ),
          ),
        ),
      ),
    );
    await _frames(tester);
    expect(find.text('Top'), findsOneWidget);
    expect(find.byKey(const ValueKey(102)), findsOneWidget);
    expect(
      transport.requests.single.path,
      '/n/conversation/7.json?sort=top&page=0&track_visit=true',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'requested unavailable hot sort remains visible when the server uses top',
    (tester) async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /n/conversation/7.json?sort=hot&page=0&track_visit=true': {
            ..._roots(ignored: true),
            'sort': 'hot',
            'effective_sort': 'top',
          },
        },
      );
      final host = await PluginHostHarness.open(
        transport: transport,
        sites: [const PluginHostSite(url: _site)],
      );
      addTearDown(host.close);
      final reader = _Reader(query: 'sort=hot');
      addTearDown(reader.dispose);
      await tester.pumpWidget(
        host.scope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: NestedRepliesReader(
                reader: reader,
                api: NestedRepliesApi(transport, reader.models),
                settings: const NestedRepliesSettings(
                  enabled: true,
                  hotEnabled: false,
                ),
              ),
            ),
          ),
        ),
      );
      await _frames(tester);
      expect(find.text('Hot'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'collapse removes descendant placeholders and expansion restores their identity',
    (tester) async {
      final transport = RecordingPluginTransport(
        responses: {
          '$_rootPath&track_visit=true': _roots(ignored: true, child: true),
        },
      );
      final host = await PluginHostHarness.open(
        transport: transport,
        sites: [const PluginHostSite(url: _site)],
      );
      addTearDown(host.close);
      final reader = _Reader();
      addTearDown(reader.dispose);
      await tester.pumpWidget(
        host.scope(
          child: MaterialApp(
            theme: AppTheme.light.copyWith(
              textTheme: AppTheme.light.textTheme.apply(
                fontFamily: 'NestedRepliesReview',
              ),
            ),
            home: Scaffold(
              body: NestedRepliesReader(
                reader: reader,
                api: NestedRepliesApi(transport, reader.models),
                settings: const NestedRepliesSettings(enabled: true),
              ),
            ),
          ),
        ),
      );
      await _frames(tester);
      expect(find.text('Ignored post'), findsOneWidget);
      expect(find.text('Deleted post'), findsOneWidget);
      await _export(tester, 'desktop-branches.png');
      expect(find.text('Continue this thread'), findsNothing);
      await tester.tap(find.text('Ignored post'));
      await _frames(tester);
      expect(find.text('Deleted post'), findsNothing);
      await tester.tap(find.bySemanticsLabel(RegExp('^Expand post')));
      await _frames(tester);
      expect(find.text('Deleted post'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Map<String, dynamic> _roots({bool ignored = false, bool child = false}) => {
  'topic': {'id': 7, 'title': 'Conversation', 'is_nested_view': true},
  'roots': [
    {
      'id': 102,
      'post_number': 2,
      'topic_id': 7,
      'username': 'alice',
      'cooked': ignored ? '' : '<p>A root reply</p>',
      if (ignored) 'ignored_post_placeholder': true,
      'direct_reply_count': child ? 1 : 0,
      'total_descendant_count': child ? 1 : 0,
      'children': [
        if (child)
          {
            'id': 103,
            'post_number': 3,
            'reply_to_post_number': 2,
            'deleted_post_placeholder': true,
            'cooked': '',
            'raw': null,
            'direct_reply_count': 0,
            'total_descendant_count': 0,
            'children': <Object?>[],
          },
      ],
    },
  ],
  'has_more_roots': false,
  'page': 0,
  'sort': 'top',
  'effective_sort': 'top',
  'message_bus_last_id': 46,
};

final class _Reader extends ChangeNotifier implements PluginTopicReader {
  _Reader({this.foreground = true, String? query, int? postNumber})
    : route = ContentRoute.topic(
        topicId: 7,
        slug: 'conversation',
        postNumber: postNumber,
        title: 'Conversation',
        query: query,
      ),
      topic = const TopicDetail(
        id: 7,
        title: 'Conversation',
        stream: [999],
        postsCount: 2,
      );
  @override
  final String siteUrl = _site;
  @override
  final String tabId = 'tab';
  @override
  final int topicId = 7;
  @override
  ContentRoute route;
  @override
  bool isCurrent = true;
  @override
  bool foreground;
  @override
  bool isConnected = true;
  @override
  TopicDetail? topic;
  @override
  int? currentUserId = 8;
  @override
  bool currentUserStaff = false;
  @override
  final DiscourseModelCodec models = const DiscourseModelCodec.core();
  final posts = <int, Post>{};
  final batches = <TopicContentResult<Object?>>[];
  final timings = <List<int>>[];
  Set<int> visibleIds = {};
  @override
  Post? post(int postId) => posts[postId];
  @override
  Future<AcceptedTopicContent<T>?> ingest<T>(
    Future<TopicContentResult<T>> Function(PluginRequestCredentials request)
    read,
  ) async {
    if (!isCurrent) return null;
    final batch = await read(
      const PluginRequestCredentials(apiKey: 'key', clientId: 'client'),
    );
    if (!isCurrent) return null;
    batches.add(batch);
    for (final item in batch.posts) {
      posts[item.post.id] = item.post;
    }
    if (batch.metadata != null) topic = batch.metadata;
    return AcceptedTopicContent(
      value: batch.value,
      postIds: batch.posts.map((item) => item.post.id),
      revision: batches.length,
    );
  }

  @override
  void reply({int? parentPostNumber, String? username}) {}
  @override
  void edit(int postId) {}
  @override
  void navigate({int? postNumber, String? query, bool replace = false}) {}
  @override
  bool updateQuery(String? query) {
    if (!foreground || !isCurrent) return false;
    route = ContentRoute.topic(
      topicId: topicId,
      slug: route.slug ?? 'conversation',
      title: route.title,
      postNumber: route.postNumber,
      query: query,
    );
    notifyListeners();
    return true;
  }

  @override
  Future<void> observeVisible(Iterable<int> postNumbers) async {
    timings.add(postNumbers.toList());
  }

  @override
  Future<void> reconcileVisit() async {}
  @override
  Future<void> refreshMetadata() async {}
  @override
  void setVisiblePostIds(Iterable<int> postIds) => visibleIds = postIds.toSet();
  @override
  Stream<Object?> get topicEvents => const Stream.empty();
  @override
  void close() {
    isCurrent = false;
  }
}

Future<void> _export(WidgetTester tester, String name) async {
  final directory = Platform.environment['NESTED_REPLIES_EXPORT_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .ancestor(
          of: find.byType(NestedRepliesReader),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
