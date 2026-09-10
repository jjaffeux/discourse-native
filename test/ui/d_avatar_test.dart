import 'dart:async';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/avatar_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedImage extends ImageProvider<_DelayedImage> {
  final completer = Completer<ImageInfo>();
  @override
  Future<_DelayedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    _DelayedImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(completer.future);
}

Future<ImageInfo> _pixel() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  picture.dispose();
  return ImageInfo(image: image);
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  ThemeData? theme,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: direction,
          child: Center(child: child),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'group preserves child sizes and propagates an explicit override',
    (tester) async {
      Widget group({DAvatarSize? size}) => DAvatarGroup(
        size: size,
        children: const [
          DAvatar(
            key: ValueKey('small'),
            size: DAvatarSize.sm,
            fallback: DAvatarFallback(child: Text('CN')),
            badge: DAvatarBadge(icon: AvatarExamplePlusIcon()),
          ),
          DAvatar(
            key: ValueKey('large'),
            size: DAvatarSize.lg,
            dimension: 44,
            fallback: DAvatarFallback(child: Text('ER')),
          ),
          DAvatarGroupCount(child: Text('+3')),
        ],
      );
      await _pump(tester, group());
      expect(
        tester.getSize(find.byKey(const ValueKey('small'))),
        const Size.square(24),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('large'))),
        const Size.square(44),
      );
      expect(
        tester.getSize(find.byType(DAvatarGroupCount)),
        const Size.square(24),
      );
      expect(tester.getSize(find.byType(DAvatarBadge)), const Size.square(8));
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('CN'))
            .text
            .style!
            .fontSize,
        12,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('+3'))
            .text
            .style!
            .fontSize,
        14,
      );
      await _pump(tester, group(size: DAvatarSize.lg));
      expect(
        tester.getSize(find.byKey(const ValueKey('small'))),
        const Size.square(40),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('large'))),
        const Size.square(44),
      );
      expect(
        tester.getSize(find.byType(DAvatarGroupCount)),
        const Size.square(40),
      );
      expect(tester.getSize(find.byType(DAvatarBadge)), const Size.square(12));
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('CN'))
            .text
            .style!
            .fontSize,
        14,
      );
      expect(find.byType(AvatarExamplePlusIcon), findsOneWidget);
    },
  );
  testWidgets('standalone count has intrinsic reference bounds in a row', (
    tester,
  ) async {
    await _pump(
      tester,
      const Row(
        children: [
          DAvatarGroupCount(child: Text('+3')),
          Text('members'),
        ],
      ),
    );
    expect(
      tester.getSize(find.byType(DAvatarGroupCount)),
      const Size.square(32),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('reference sizes and fallback typography follow tokens', (
    tester,
  ) async {
    for (final size in DAvatarSize.values) {
      await _pump(
        tester,
        DAvatar(
          size: size,
          fallback: const DAvatarFallback(child: Text('CN')),
        ),
      );
      expect(tester.getSize(find.byType(DAvatar)), Size.square(size.dimension));
      final style = tester
          .renderObject<RenderParagraph>(find.text('CN'))
          .text
          .style!;
      expect(style.fontSize, size == DAvatarSize.sm ? 12 : 14);
      expect(style.fontWeight, FontWeight.w400);
      expect(
        style.color,
        DTokens.of(tester.element(find.text('CN'))).mutedForeground,
      );
    }
  });
  testWidgets('ring matches core geometry, live colors and semantics', (
    tester,
  ) async {
    const ringKey = ValueKey('ring');
    const fallbackKey = ValueKey('ring-fallback');
    await _pump(
      tester,
      const DAvatar(
        key: ringKey,
        ring: true,
        ringSemanticLabel: 'Online',
        semanticLabel: 'Chris',
        fallback: DAvatarFallback(key: fallbackKey, child: Text('CN')),
      ),
    );

    expect(tester.getSize(find.byKey(ringKey)), const Size.square(32));
    expect(tester.getSize(find.byKey(fallbackKey)), const Size.square(28));
    final decoration =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
            as BoxDecoration;
    final tokens = DTokens.of(tester.element(find.byKey(ringKey)));
    expect(decoration.color, tokens.background);
    expect((decoration.border! as Border).top.color, tokens.success);
    expect((decoration.border! as Border).top.width, 1);

    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Chris, Online'), findsOneWidget);
    semantics.dispose();
  });
  testWidgets('ring preserves an intrinsic frame extent', (tester) async {
    const childKey = ValueKey('framed-ring-child');
    await _pump(
      tester,
      const DAvatar.frame(
        ring: true,
        ringSemanticLabel: 'Online',
        child: SizedBox.square(
          key: childKey,
          dimension: 28,
          child: ColoredBox(color: Colors.blue),
        ),
      ),
    );

    expect(tester.getSize(find.byType(DAvatar)), const Size.square(28));
    expect(tester.getSize(find.byKey(childKey)), const Size.square(24));
  });
  testWidgets('provider replacement discards late frames and keeps identity', (
    tester,
  ) async {
    final old = _DelayedImage();
    final current = _DelayedImage();
    final statuses = <DAvatarImageStatus>[];
    Widget avatar(ImageProvider provider) => DAvatar(
      semanticLabel: 'Chris',
      image: DAvatarImage(image: provider, onStatusChanged: statuses.add),
      fallback: const DAvatarFallback(child: Text('CN')),
    );
    await _pump(tester, avatar(old));
    expect(find.text('CN'), findsOneWidget);
    await _pump(tester, avatar(current));
    final oldPixel = await tester.runAsync(_pixel);
    old.completer.complete(oldPixel);
    await tester.pump();
    expect(find.text('CN'), findsOneWidget);
    final newPixel = await tester.runAsync(_pixel);
    current.completer.complete(newPixel);
    await tester.pump();
    expect(find.text('CN'), findsNothing);
    expect(statuses.last, DAvatarImageStatus.ready);
    expect(tester.getSize(find.byType(DAvatar)), const Size.square(32));
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Chris'), findsOneWidget);
    semantics.dispose();
  });
  testWidgets('decode errors show delayed fallback and report status safely', (
    tester,
  ) async {
    final provider = _DelayedImage();
    final statuses = <DAvatarImageStatus>[];
    await _pump(
      tester,
      DAvatar(
        image: DAvatarImage(image: provider, onStatusChanged: statuses.add),
        fallback: const DAvatarFallback(
          delay: Duration(milliseconds: 200),
          child: Text('CN'),
        ),
      ),
    );
    expect(find.text('CN'), findsNothing);
    provider.completer.completeError(StateError('invalid image'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('CN'), findsOneWidget);
    expect(statuses, [DAvatarImageStatus.loading, DAvatarImageStatus.error]);
    await _pump(tester, const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets('real local raster replaces fallback without network', (
    tester,
  ) async {
    await _pump(
      tester,
      DAvatar(
        image: DAvatarImage(image: avatarExampleImage),
        fallback: const DAvatarFallback(child: Text('CN')),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        avatarExampleImage,
        tester.element(find.byType(DAvatar)),
      );
    });
    await tester.pump();
    expect(find.text('CN'), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });
  testWidgets('decorative identity is silent but status retains its name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      const DAvatar(
        decorative: true,
        fallback: DAvatarFallback(child: Text('CN')),
        badge: DAvatarBadge(semanticLabel: 'Online'),
      ),
    );
    expect(find.bySemanticsLabel('CN'), findsNothing);
    expect(find.bySemanticsLabel('Online'), findsOneWidget);
    semantics.dispose();
  });
  for (final direction in TextDirection.values) {
    testWidgets('group geometry and narrow wrapping in ${direction.name}', (
      tester,
    ) async {
      const children = [
        DAvatar(
          key: ValueKey('first'),
          fallback: DAvatarFallback(child: Text('CN')),
        ),
        DAvatar(
          key: ValueKey('second'),
          fallback: DAvatarFallback(child: Text('ER')),
        ),
        DAvatarGroupCount(child: Text('+3')),
      ];
      await _pump(
        tester,
        const DAvatarGroup(children: children),
        direction: direction,
      );
      expect(tester.getSize(find.byType(DAvatarGroup)), const Size(80, 32));
      final a = tester.getTopLeft(find.byKey(const ValueKey('first')));
      final b = tester.getTopLeft(find.byKey(const ValueKey('second')));
      expect(b.dx - a.dx, direction == TextDirection.ltr ? 24 : -24);
      await _pump(
        tester,
        const SizedBox(width: 48, child: DAvatarGroup(children: children)),
        direction: direction,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('second'))).dy -
            tester.getTopLeft(find.byKey(const ValueKey('first'))).dy,
        36,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    '200 percent initials grow while fixed adapter frames stay fixed',
    (tester) async {
      await _pump(
        tester,
        const DAvatar(
          size: DAvatarSize.sm,
          fallback: DAvatarFallback(child: Text('CN')),
        ),
        scale: 2,
      );
      expect(tester.getSize(find.byType(DAvatar)), const Size.square(48));
      expect(
        tester.renderObject<RenderParagraph>(find.text('CN')).didExceedMaxLines,
        isFalse,
      );
      await _pump(
        tester,
        const DAvatar.frame(
          child: SizedBox.square(dimension: 28, child: Text('X')),
        ),
        scale: 2,
      );
      expect(tester.getSize(find.byType(DAvatar)), const Size.square(28));
    },
  );
  testWidgets('badge sizes hide the small icon and mirror trailing placement', (
    tester,
  ) async {
    for (final size in DAvatarSize.values) {
      await _pump(
        tester,
        DAvatar(
          size: size,
          fallback: const DAvatarFallback(child: Text('CN')),
          badge: const DAvatarBadge(icon: AvatarExamplePlusIcon()),
        ),
        direction: TextDirection.rtl,
      );
      expect(
        tester.getSize(find.byType(DAvatarBadge)),
        Size.square(switch (size) {
          DAvatarSize.sm => 8,
          DAvatarSize.standard => 10,
          DAvatarSize.lg => 12,
        }),
      );
      expect(
        find.byType(AvatarExamplePlusIcon),
        size == DAvatarSize.sm ? findsNothing : findsOneWidget,
      );
      expect(
        tester.getBottomLeft(find.byType(DAvatarBadge)),
        tester.getBottomLeft(find.byType(DAvatar)),
      );
    }
  });
}
