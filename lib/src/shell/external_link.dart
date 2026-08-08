import 'package:url_launcher/url_launcher.dart';

import '../diagnostics/diagnostics_controller.dart';

/// Opens [url] in the platform browser.
///
/// Returns false when the URL is unparseable, its scheme is not safe to hand to
/// another application, or nothing on the system can handle it. This is the
/// shape [HtmlWidget.onTapUrl] wants.
Future<bool> openExternalLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !_isAllowedExternalUri(uri)) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (error, stackTrace) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: 'externalLink.open',
      source: 'platform',
      severity: DiagnosticSeverity.warning,
      handled: true,
      degraded: true,
    );
    return false;
  }
}

bool _isAllowedExternalUri(Uri uri) => switch (uri.scheme) {
  'http' || 'https' => uri.hasAuthority && uri.host.isNotEmpty,
  'mailto' => uri.path.isNotEmpty,
  _ => false,
};
