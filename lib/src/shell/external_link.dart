import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the platform browser.
///
/// Returns false when the URL is unparseable or nothing on the system can
/// handle it, which is the shape [HtmlWidget.onTapUrl] wants.
Future<bool> openExternalLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
