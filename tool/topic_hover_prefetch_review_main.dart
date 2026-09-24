import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/styleguide/examples/item_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

// Offline native review. Requests take 600 ms so hover/click handoff and
// cancellation can be inspected without contacting a forum.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = _ReviewApi();
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('hover-review.invalid')]),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  runApp(_Review(shell: shell, api: api));
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
}

class _Review extends StatefulWidget {
  const _Review({required this.shell, required this.api});
  final ShellController shell;
  final _ReviewApi api;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
    child: MaterialApp(
      theme: _dark ? AppTheme.dark : AppTheme.light,
      home: DPageSurface(
        header: Padding(
          padding: const EdgeInsets.all(DSpacing.md),
          child: Row(
            spacing: DSpacing.md,
            children: [
              const Expanded(
                child: Text('Topic hover prefetch · offline review'),
              ),
              DButton(
                onPressed: () => setState(() => _dark = !_dark),
                label: Text(_dark ? 'Light theme' : 'Dark theme'),
              ),
              DButton(
                onPressed: () =>
                    widget.shell.handleBack(canReturnToSidebar: false),
                label: const Text('Back to list'),
              ),
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: widget.shell,
                builder: (context, _) {
                  final detail = widget.shell.store.read<TopicDetail>(
                    'https://hover-review.invalid',
                    widget.shell.currentContent?.topicId ?? -1,
                  );
                  if (widget.shell.currentContent?.isTopic == true) {
                    return Center(
                      child: detail == null
                          ? const DSpinner()
                          : Text('Opened ${detail.title}'),
                    );
                  }
                  final feed = widget.shell.currentFeed;
                  return feed == null
                      ? const DSpinner()
                      : TopicListView(feed: feed);
                },
              ),
            ),
            const DSeparator(orientation: Axis.vertical),
            SizedBox(
              width: 350,
              child: Padding(
                padding: const EdgeInsets.all(DSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: DSpacing.md,
                  children: [
                    const Text('Item styleguide · hover callback'),
                    Builder(builder: itemExamples.examples.first.builder),
                    const DSeparator(),
                    const Text('Request log (600 ms simulated response)'),
                    Expanded(
                      child: DScrollArea(
                        child: ValueListenableBuilder(
                          valueListenable: widget.api.events,
                          builder: (_, events, _) => Text(events.join('\n')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReviewApi extends FakeDiscourseApi {
  _ReviewApi()
    : super(
        feeds: {
          '/latest.json': [
            for (var id = 1; id <= 8; id++)
              Topic(
                id: id,
                title: 'Topic $id — hover, then click',
                slug: 'topic-$id',
              ),
          ],
        },
      );

  final events = ValueNotifier<List<String>>([]);
  void record(String event) => events.value = [...events.value, event];

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async {
    record('Start $id (${abortTrigger == null ? 'click' : 'hover'})');
    final response = Completer<TopicPayload>();
    final timer = Timer(const Duration(milliseconds: 600), () {
      record('Complete $id');
      response.complete(topicPayload(id: id, title: 'topic $id'));
    });
    unawaited(
      abortTrigger?.then((_) {
        if (response.isCompleted) return;
        timer.cancel();
        record('Cancel $id');
        response.completeError(StateError('Cancelled'));
      }),
    );
    return response.future;
  }
}
