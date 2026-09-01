import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart'
    show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';

/// Embedded media owns drag gestures once the user has explicitly activated it.
const Set<Factory<OneSequenceGestureRecognizer>> mediaPlayerGestureRecognizers =
    <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
    };

/// Platform policy shared by YouTube and uploaded-video WebViews.
PlatformWebViewControllerCreationParams mediaWebViewCreationParams() {
  const base = PlatformWebViewControllerCreationParams();
  final platform = WebViewPlatform.instance;
  if (platform is WebKitWebViewPlatform) {
    return WebKitWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
      base,
      mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      allowsInlineMediaPlayback: true,
    );
  }
  if (platform is LinuxWebViewPlatform) {
    return const LinuxWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
      base,
      mediaPlaybackRequiresUserGesture: false,
      mediaPlaybackAllowsInline: true,
    );
  }
  return base;
}
