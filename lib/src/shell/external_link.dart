import 'package:url_launcher/url_launcher.dart';

import '../diagnostics/diagnostics_controller.dart';

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
  // A cooked link never needs URL credentials. Refuse them before handing the
  // target to another application: `trusted.example@evil.example` is easy to
  // mistake for a trusted host, and a real password would otherwise be copied
  // into launcher/browser history.
  'http' ||
  'https' => uri.hasAuthority && uri.host.isNotEmpty && uri.userInfo.isEmpty,
  'mailto' => uri.path.isNotEmpty,
  _ => false,
};
