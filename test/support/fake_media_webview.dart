import 'package:flutter/material.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

enum MediaWebViewConfigurationStage {
  javaScript,
  background,
  navigation,
  userScript,
}

final class FakeMediaWebViewPlatform extends WebViewPlatform {
  final controllers = <FakeMediaWebViewController>[];
  (MediaWebViewConfigurationStage, Future<void>)? nextGate;
  Widget view = const SizedBox.expand();

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeMediaWebViewController(params, gate: nextGate);
    nextGate = null;
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakeMediaNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeMediaWebViewWidget(params, child: view);
}

final class FakeMediaWebViewController extends PlatformWebViewController {
  FakeMediaWebViewController(super.params, {this.gate})
    : super.implementation();

  final (MediaWebViewConfigurationStage, Future<void>)? gate;
  final operations = <MediaWebViewConfigurationStage>[];
  final documents = <({String html, String? baseUrl})>[];
  final channels = <String, JavaScriptChannelParams>{};
  final scripts = <String>[];
  final userScripts = <WebViewUserScript>[];
  FakeMediaNavigationDelegate? delegate;

  Future<void> _configure(MediaWebViewConfigurationStage stage) async {
    operations.add(stage);
    if (gate case (final heldStage, final completion) when heldStage == stage) {
      await completion;
    }
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) =>
      _configure(MediaWebViewConfigurationStage.javaScript);

  @override
  Future<void> setBackgroundColor(Color color) =>
      _configure(MediaWebViewConfigurationStage.background);

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) {
    delegate = handler as FakeMediaNavigationDelegate;
    return _configure(MediaWebViewConfigurationStage.navigation);
  }

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams channel) async {
    channels[channel.name] = channel;
  }

  @override
  Future<void> removeJavaScriptChannel(String name) async {
    channels.remove(name);
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    scripts.add(javaScript);
  }

  @override
  Future<bool> isUserScriptInjectionSupported(
    WebViewUserScriptInjectionTime injectionTime,
  ) async => injectionTime == WebViewUserScriptInjectionTime.documentStart;

  @override
  Future<String> addUserScript(WebViewUserScript userScript) async {
    userScripts.add(userScript);
    await _configure(MediaWebViewConfigurationStage.userScript);
    return 'script-${userScripts.length}';
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    documents.add((html: html, baseUrl: baseUrl));
  }
}

final class FakeMediaNavigationDelegate extends PlatformNavigationDelegate {
  FakeMediaNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;
  PageEventCallback? onPageFinished;
  WebResourceErrorCallback? onWebResourceError;
  HttpResponseErrorCallback? onHttpError;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    onNavigationRequest = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    onPageFinished = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    onWebResourceError = callback;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {
    onHttpError = callback;
  }

  Future<NavigationDecision> navigate(
    String url, {
    bool isMainFrame = true,
  }) async => await onNavigationRequest!(
    NavigationRequest(url: url, isMainFrame: isMainFrame),
  );
}

final class _FakeMediaWebViewWidget extends PlatformWebViewWidget {
  _FakeMediaWebViewWidget(super.params, {required this.child})
    : super.implementation();

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
