import 'package:discourse_native/src/plugins/discourse_lazy_videos/lazy_embed.dart';
import 'package:discourse_native/src/shell/oneboxes/embedded.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  test('lazy Vimeo keeps private query parameters and external destination', () {
    final element = html
        .parseFragment(
          '<div class="vimeo-onebox lazy-video-container" data-provider-name="vimeo" data-video-id="123?h=secret&amp;app_id=122963" data-video-title="Recording"><a href="https://vimeo.com/123/secret"></a></div>',
        )
        .children
        .single;
    final original = element.outerHtml;
    final widget = lazyEmbeddedVideoWidgetBuilder(element) as EmbeddedOnebox;
    expect(
      widget.data.uri.toString(),
      'https://player.vimeo.com/video/123?h=secret&app_id=122963',
    );
    expect(widget.data.externalUri.toString(), 'https://vimeo.com/123/secret');
    expect(widget.data.title, 'Recording');
    expect(element.outerHtml, original);
  });
  test('lazy TikTok uses its numeric provider ID', () {
    final widget =
        lazyEmbeddedVideoWidgetBuilder(
              html
                  .parseFragment(
                    '<div class="tiktok-onebox lazy-video-container" data-provider-name="tiktok" data-video-id="123"></div>',
                  )
                  .children
                  .single,
            )
            as EmbeddedOnebox;
    expect(widget.data.uri.toString(), 'https://www.tiktok.com/embed/v2/123');
    expect(widget.data.height, 560);
  });
  test('malformed provider IDs never become embed URLs', () {
    for (final id in [
      '//evil.test',
      '../123',
      '123#fragment',
      '123/456',
      '123 bad',
    ]) {
      expect(
        lazyEmbeddedVideoWidgetBuilder(
          html
              .parseFragment(
                '<div class="vimeo-onebox lazy-video-container" data-provider-name="vimeo" data-video-id="$id"></div>',
              )
              .children
              .single,
        ),
        isNull,
      );
    }
  });
}
