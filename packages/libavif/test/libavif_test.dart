import 'dart:typed_data';

import 'package:libavif/libavif.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('public decode contract', () {
    test(
      'decodes exact RGBA pixels and scales before returning them',
      () async {
        final original = Avif.decodeSync(whiteAvif);
        final scaled = await Avif.decode(
          whiteAvif,
          targetWidth: 2,
          targetHeight: 3,
        );

        expect((original.width, original.height), (1, 1));
        expect(original.rowBytes, 4);
        expect(original.sourceBitDepth, 8);
        expect(original.pixels, Uint8List.fromList([253, 253, 253, 255]));
        expect((scaled.width, scaled.height), (2, 3));
        expect(scaled.pixels, hasLength(2 * 3 * 4));
        expect(Avif.nativeCodecVersions, contains('dav1d'));
        expect(Avif.nativeCodecVersions, isNot(contains('aom')));
      },
    );

    test('reports malformed input with a typed error', () {
      expect(
        () => Avif.decodeSync(Uint8List.fromList([0, 1, 2, 3])),
        throwsA(
          isA<AvifException>().having(
            (error) => error.code,
            'code',
            AvifErrorCode.invalidInput,
          ),
        ),
      );
    });

    test('does not silently reduce animation to a still image', () {
      expect(
        () => Avif.decodeSync(animatedAvif),
        throwsA(
          isA<AvifException>().having(
            (error) => error.code,
            'code',
            AvifErrorCode.unsupported,
          ),
        ),
      );
    });
  });

  test('animated sequences preserve frame order, timing, and reset', () async {
    final decoder = await AvifSequenceDecoder.open(
      animatedAvif,
      targetWidth: 30,
      prefetchFirstFrame: true,
    );
    addTearDown(decoder.dispose);

    expect((decoder.info.width, decoder.info.height), (30, 30));
    expect(decoder.info.frameCount, 5);
    expect(decoder.info.isAnimated, isTrue);

    final frames = <AvifSequenceFrame>[];
    AvifSequenceFrame? frame;
    while ((frame = await decoder.nextFrame()) != null) {
      frames.add(frame!);
    }

    expect(frames.map((frame) => frame.index), [0, 1, 2, 3, 4]);
    expect(
      frames.map((frame) => frame.duration),
      everyElement(const Duration(microseconds: 33333)),
    );
    expect(
      frames.map((frame) => frame.image.pixels.length),
      everyElement(30 * 30 * 4),
    );

    await decoder.reset();
    expect((await decoder.nextFrame())?.index, 0);
  });
}
