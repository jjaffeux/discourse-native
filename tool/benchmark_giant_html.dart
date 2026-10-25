import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
// ignore: implementation_imports
import 'package:flutter_widget_from_html_core/src/internal/core_build_tree.dart';
import 'package:html/parser.dart' as parser;
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

const _timeout = Duration(seconds: 60);
final _body = ValueNotifier<Widget>(const SizedBox.shrink());
final _host = GlobalKey<HtmlWidgetState>();
final _boundary = GlobalKey();

String _source(int count, {bool paragraphs = false}) => paragraphs
    ? List.generate(
        count,
        (i) => '<p>Paragraph $i with <b>bold</b> and <i>italic</i> text.</p>',
      ).join()
    : '<p>${List.generate(count, (i) => '<b>B$i </b><i>I$i </i>').join()}</p>';

Future<void> main() async {
  final binding = _Binding();
  final rows = <Map<String, Object?>>[];
  final errors = <String>[];
  vm.VmService? service;
  final diagnostics = <Map<String, Object?>>[];
  final isolateId = developer.Service.getIsolateId(Isolate.current);
  if (Platform.environment['GIANT_PROFILE'] == '1') {
    final uri = (await developer.Service.getInfo()).serverWebSocketUri;
    if (uri != null) service = await vmServiceConnectUri(uri.toString());
  }
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  try {
    if (!kProfileMode) throw StateError('Run in profile mode.');
    runApp(
      MaterialApp(
        theme: AppTheme.light,
        home: DPageSurface(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                children: [
                  HtmlWidget('', key: _host),
                  ValueListenableBuilder<Widget>(
                    valueListenable: _body,
                    builder: (_, child, _) =>
                        SizedBox(key: _boundary, child: child),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await binding.endOfFrame.timeout(_timeout);
    for (final count in [20, 2000, 12000]) {
      final source = _source(count);
      for (var repeat = 0; repeat < 3; repeat++) {
        final factory = _Factory()..reset(_host.currentState!);
        try {
          final origin = developer.Timeline.now;
          final parse = Stopwatch()..start();
          final nodes = parser.parseFragment(source).nodes;
          parse.stop();
          final conversion = Stopwatch()..start();
          final tree = CoreBuildTree.root(
            inheritanceResolvers: _Resolvers(factory, _host.currentContext!),
            wf: factory,
          )..addBitsFromNodes(nodes);
          final rootFinalization = Stopwatch()..start();
          final placeholder = tree.build()!.wrapWith(factory.buildBodyWidget);
          rootFinalization.stop();
          conversion.stop();
          final resolution = Stopwatch()..start();
          final resolved = WidgetPlaceholder.unwrap(
            _host.currentContext!,
            placeholder,
          );
          resolution.stop();
          if (service != null && isolateId != null) {
            final cpu = await service.getCpuSamples(
              isolateId,
              origin,
              developer.Timeline.now - origin,
            );
            diagnostics.add({
              'count': count,
              'repeat': repeat,
              'sampleCount': cpu.sampleCount,
              'functions': [
                for (final f in cpu.functions ?? <vm.ProfileFunction>[])
                  {
                    'name': f.function is vm.FuncRef
                        ? (f.function as vm.FuncRef).name
                        : '${f.function}',
                    'url': f.resolvedUrl,
                    'exclusive': f.exclusiveTicks,
                    'inclusive': f.inclusiveTicks,
                  },
              ],
            });
          }
          final text = factory.spans.map((span) => span.toPlainText()).join();
          final expected =
              "${List.generate(count, (i) => 'B$i I$i').join(' ')} ";
          if (text.trimRight() != expected.trimRight()) {
            throw StateError('Resolved text order differs for $count.');
          }
          final frame = Stopwatch()..start();
          final before = binding.uiMicroseconds;
          _body.value = resolved;
          await binding.endOfFrame.timeout(_timeout);
          frame.stop();
          final size = _boundary.currentContext!.size!;
          if (size.height <= 0 || size.width <= 0) {
            throw StateError('Resolved content has no layout.');
          }
          rows.add({
            'kind': 'corePhases',
            'count': count,
            'repeat': repeat,
            'sourceUnits': source.length,
            'parseUs': parse.elapsedMicroseconds,
            'conversionUs': conversion.elapsedMicroseconds,
            'blockFinalizationUs': factory.blockFinalizationUs,
            'rootFinalizationUs': rootFinalization.elapsedMicroseconds,
            'resolutionUs': resolution.elapsedMicroseconds,
            'layoutFrameUs': binding.uiMicroseconds - before,
            'frameWaitUs': frame.elapsedMicroseconds,
            'height': size.height,
            'textUnits': text.length,
            'spans': _spanCount(factory.spans.single),
          });
          _body.value = const SizedBox.shrink();
          await binding.endOfFrame.timeout(_timeout);
        } finally {
          factory.dispose();
        }
      }
    }
    for (final (label, count, paragraphs) in [
      ('manyParagraphs', 1600, true),
      ('wrappedParagraphs', 1600, true),
      ('giantInline', 12000, false),
    ]) {
      for (var repeat = 0; repeat < 3; repeat++) {
        final contents = _source(count, paragraphs: paragraphs);
        final source = label == 'wrappedParagraphs'
            ? '<div>$contents</div>'
            : contents;
        final nodes = parser.parseFragment(source).nodes;
        final factory = _Factory()..reset(_host.currentState!);
        try {
          final tree = CoreBuildTree.root(
            inheritanceResolvers: _Resolvers(factory, _host.currentContext!),
            wf: factory,
          );
          final gaps = <int>[];
          final watch = Stopwatch()..start();
          var previous = 0;
          void tick() {
            final now = watch.elapsedMicroseconds;
            gaps.add(now - previous);
            previous = now;
          }

          final timer = Timer.periodic(
            const Duration(milliseconds: 1),
            (_) => tick(),
          );
          final completed = await tree.addBitsFromNodesAsync(
            nodes,
            isCurrent: () => true,
          );
          final rootFinalization = Stopwatch()..start();
          final placeholder = tree.build()!.wrapWith(factory.buildBodyWidget);
          rootFinalization.stop();
          final conversionUs = watch.elapsedMicroseconds;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          timer.cancel();
          tick();
          if (!completed) {
            throw StateError('Conversion cancelled unexpectedly.');
          }
          final resolution = Stopwatch()..start();
          final resolved = WidgetPlaceholder.unwrap(
            _host.currentContext!,
            placeholder,
          );
          resolution.stop();
          final beforeLayout = binding.uiMicroseconds;
          _body.value = resolved;
          await binding.endOfFrame.timeout(_timeout);
          final text = factory.spans.map((span) => span.toPlainText()).join();
          final expected = paragraphs
              ? List.generate(
                  count,
                  (i) => 'Paragraph $i with bold and italic text.',
                ).join()
              : List.generate(count, (i) => 'B$i I$i').join(' ');
          if (text.trimRight() != expected.trimRight()) {
            throw StateError('Cooperative text differs for $label.');
          }
          rows.add({
            'kind': 'cooperativeConversion',
            'label': label,
            'repeat': repeat,
            'conversionUs': conversionUs,
            'blockFinalizationUs': factory.blockFinalizationUs,
            'rootFinalizationUs': rootFinalization.elapsedMicroseconds,
            'resolutionUs': resolution.elapsedMicroseconds,
            'maxEventGapUs': gaps.reduce((a, b) => a > b ? a : b),
            'layoutFrameUs': binding.uiMicroseconds - beforeLayout,
            'resolutionScope':
                'WidgetPlaceholder.unwrap; later widget builds remain in layoutFrameUs',
            'heartbeatTicks': gaps.length,
            'textUnits': text.length,
            'height': _boundary.currentContext!.size!.height,
          });
          _body.value = const SizedBox.shrink();
          await binding.endOfFrame.timeout(_timeout);
        } finally {
          factory.dispose();
        }
      }
    }
    for (final (label, count, paragraphs) in [
      ('ordinary', 20, true),
      ('manyParagraphs', 1600, true),
      ('wrappedParagraphs', 1600, true),
      ('giantInline', 12000, false),
    ]) {
      for (var repeat = 0; repeat < 2; repeat++) {
        final contents = _source(count, paragraphs: paragraphs);
        final source = label == 'wrappedParagraphs'
            ? '<div>$contents</div>'
            : contents;
        final frameCosts = <int>[];
        final completions = <Future<void>>{};
        var pending = 0;
        var inspectionUs = 0;
        final elapsed = Stopwatch()..start();
        var before = binding.uiMicroseconds;
        _body.value = NotificationListener<HtmlBodyMountingNotification>(
          onNotification: (notification) {
            if (completions.add(notification.completion)) {
              pending++;
              unawaited(notification.completion.whenComplete(() => pending--));
            }
            return false;
          },
          child: CookedHtml(
            key: UniqueKey(),
            html: source,
            renderMode: const ProgressiveHtmlMode(),
          ),
        );
        var found = <RichText>[];
        for (var frame = 0; frame < 300; frame++) {
          await binding.endOfFrame.timeout(_timeout);
          frameCosts.add(binding.uiMicroseconds - before);
          if (pending == 0) {
            final inspection = Stopwatch()..start();
            found = _texts(_boundary.currentContext! as Element)
                .where(
                  (w) => w.text.toPlainText().startsWith(
                    paragraphs ? 'Paragraph' : 'B0',
                  ),
                )
                .toList();
            inspectionUs += inspection.elapsedMicroseconds;
            if (found.length == (paragraphs ? count : 1)) break;
          }
          before = binding.uiMicroseconds;
        }
        elapsed.stop();
        if (found.length != (paragraphs ? count : 1)) {
          throw StateError('Body did not complete for $label.');
        }
        final text = found.map((w) => w.text.toPlainText()).join();
        if (!text.contains(
          paragraphs ? 'Paragraph ${count - 1}' : 'I${count - 1}',
        )) {
          throw StateError('Body tail is missing.');
        }
        rows.add({
          'kind': 'cookedBody',
          'label': label,
          'repeat': repeat,
          'sourceUnits': source.length,
          'endToEndUs': elapsed.elapsedMicroseconds - inspectionUs,
          'inspectionUs': inspectionUs,
          'uiFramesUs': frameCosts,
          'height': _boundary.currentContext!.size!.height,
          'elements': _elementCount(_boundary.currentContext! as Element),
          'textUnits': text.length,
          'textBlocks': found.length,
        });
        if (service != null && isolateId != null) {
          final heap = await service.getAllocationProfile(isolateId, gc: true);
          const names = {
            'TextSpan',
            'RichText',
            'RenderParagraph',
            'CoreBuildTree',
            'WidgetPlaceholder',
            '_GrowableList',
            '_List',
          };
          diagnostics.add({
            'label': label,
            'repeat': repeat,
            'heapScope':
                'Whole isolate after GC with completed CookedHtml mounted.',
            'classes': [
              for (final row in heap.members ?? <vm.ClassHeapStats>[])
                if (names.contains(row.classRef?.name))
                  {
                    'name': row.classRef?.name,
                    'bytes': row.bytesCurrent,
                    'instances': row.instancesCurrent,
                  },
            ],
          });
        }
        _body.value = const SizedBox.shrink();
        await binding.endOfFrame.timeout(_timeout);
      }
    }
  } catch (error, stack) {
    errors.add('$error\n$stack');
  }
  stdout.writeln(
    'GIANT_HTML_REPORT ${jsonEncode({'schema': 1, 'mode': kProfileMode ? 'profile' : 'other', 'platform': Platform.operatingSystem, 'dart': Platform.version, 'processors': Platform.numberOfProcessors, 'maxRss': ProcessInfo.maxRss, 'rows': rows, 'diagnostics': diagnostics, 'failures': errors})}',
  );
  await stdout.flush();
  await service?.dispose();
  exit(errors.isEmpty ? 0 : 1);
}

final class _Binding extends WidgetsFlutterBinding {
  int uiMicroseconds = 0;
  @override
  void drawFrame() {
    final watch = Stopwatch()..start();
    super.drawFrame();
    uiMicroseconds += watch.elapsedMicroseconds;
  }
}

final class _Resolvers extends InheritanceResolvers {
  _Resolvers(this.factory, this.context);
  final WidgetFactory factory;
  final BuildContext context;
  InheritedProperties? properties;
  @override
  InheritedProperties resolve(BuildContext _) =>
      properties ??= InheritedProperties.root(
        factory.getDependencies(context),
        const TextStyle(fontSize: 16),
      );
}

final class _Factory extends WidgetFactory {
  final spans = <InlineSpan>[];
  int blockFinalizationUs = 0;
  @override
  void parse(BuildTree tree) {
    super.parse(tree);
    if (tree.element.localName != 'p') return;
    final watch = Stopwatch();
    tree.register(
      BuildOp(
        priority: 1000000,
        onParsed: (tree) {
          watch.start();
          return tree;
        },
        onRenderedBlock: (_, _) {
          watch.stop();
          blockFinalizationUs += watch.elapsedMicroseconds;
        },
      ),
    );
  }

  @override
  Widget? buildText(
    BuildTree tree,
    InheritedProperties resolved,
    InlineSpan text,
  ) {
    spans.add(text);
    return super.buildText(tree, resolved, text);
  }
}

int _spanCount(InlineSpan span) =>
    1 +
    (span is TextSpan
        ? (span.children ?? []).fold<int>(
            0,
            (count, child) => count + _spanCount(child),
          )
        : 0);
Iterable<RichText> _texts(Element element) sync* {
  if (element.widget case final RichText text) yield text;
  final children = <Element>[];
  element.visitChildren(children.add);
  for (final child in children) {
    yield* _texts(child);
  }
}

int _elementCount(Element element) {
  var count = 1;
  element.visitChildren((child) => count += _elementCount(child));
  return count;
}
