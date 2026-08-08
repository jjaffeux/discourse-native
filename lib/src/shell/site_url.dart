/// Resolves a URL written by Discourse against the site that produced it.
///
/// Absolute URLs and non-web schemes are returned unchanged. When no source
/// site is known, path-relative URLs remain unresolved so callers can reject
/// them rather than accidentally attributing them to another site.
String resolveSiteUrl(String url, String? siteUrl) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.hasScheme) return url;

  final base = siteUrl == null ? null : Uri.tryParse(siteUrl);
  if (base != null && base.hasScheme && base.hasAuthority) {
    return base.resolveUri(uri).toString();
  }
  if (uri.hasAuthority) {
    return Uri(scheme: 'https').resolveUri(uri).toString();
  }
  return url;
}
