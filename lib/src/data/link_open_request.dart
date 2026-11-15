import 'http_url_safety.dart';

/// The action another application invokes to show a forum page here:
/// `discourse://open?url=<percent-encoded page URL>`. It shares its scheme
/// with sign-in's `discourse://auth_redirect` callback and is told apart by
/// its host, so neither can be mistaken for the other.
const String linkOpenScheme = 'discourse';
const String linkOpenHost = 'open';
const String linkOpenParameter = 'url';

/// A page URL is bounded like every other link the shell routes; the request
/// around it adds the action and the percent-escapes of that URL.
const int maximumLinkOpenTargetLength = 2048;
const int maximumLinkOpenRequestLength = 3 * maximumLinkOpenTargetLength + 64;

/// The page a request names, or null when the request is not exactly one
/// well-formed action carrying one safe page URL.
///
/// Any application or web page can issue a request, so nothing in it is
/// trusted: it must be the bare action with a single `url` parameter, and that
/// URL must be absolute http(s) with a plain ASCII host, no credentials, and
/// plaintext only on loopback. Whether a forum the user added serves the page
/// is the shell's question, not this parser's.
Uri? parseLinkOpenRequest(String request) {
  if (request.isEmpty ||
      request.length > maximumLinkOpenRequestLength ||
      _hasUnsafeCodeUnit(request) ||
      _brokenEscape.hasMatch(request)) {
    return null;
  }
  final Uri action;
  final Map<String, List<String>> parameters;
  try {
    action = Uri.parse(request);
    parameters = action.queryParametersAll;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
  if (action.scheme != linkOpenScheme ||
      action.host != linkOpenHost ||
      action.userInfo.isNotEmpty ||
      action.hasPort ||
      action.hasFragment ||
      (action.path.isNotEmpty && action.path != '/') ||
      parameters.length != 1) {
    return null;
  }
  final values = parameters[linkOpenParameter];
  if (values == null || values.length != 1) return null;
  final value = values.single;
  if (value.isEmpty ||
      value.length > maximumLinkOpenTargetLength ||
      _hasUnsafeCodeUnit(value)) {
    return null;
  }
  try {
    final target = requireSafeHttpUrl(Uri.parse(value));
    return _plainHost.hasMatch(target.host) ? target : null;
  } on FormatException {
    return null;
  } on UnsafeHttpTransportException {
    return null;
  }
}

/// Dart reads a malformed escape as literal text, which would let one request
/// mean different URLs to this parser and to whatever produced it.
final _brokenEscape = RegExp(r'%(?![0-9A-Fa-f]{2})');

/// A registered name or an address literal. Dart percent-encodes anything
/// else into the host, where it could be shown to the person as a site name.
final _plainHost = RegExp(r'^[a-z0-9.:-]+$');

/// Whitespace and controls never belong in a URL, and a backslash is read as
/// a path separator by some URL parsers and as part of the host by others.
bool _hasUnsafeCodeUnit(String text) =>
    text.codeUnits.any((unit) => unit <= 0x20 || unit == 0x7F || unit == 0x5C);

/// What became of a request, for the application to show: the shell navigates
/// but owns neither the browser nor the toaster.
sealed class RequestedLinkOutcome {
  const RequestedLinkOutcome();
}

final class RequestedLinkOpened extends RequestedLinkOutcome {
  const RequestedLinkOpened();
}

/// A newer request or tap took over before this one finished resolving.
final class RequestedLinkSuperseded extends RequestedLinkOutcome {
  const RequestedLinkSuperseded();
}

final class RequestedLinkMalformed extends RequestedLinkOutcome {
  const RequestedLinkMalformed();
}

/// No forum the user added serves [target].
final class RequestedLinkUnknownSite extends RequestedLinkOutcome {
  const RequestedLinkUnknownSite(this.target);

  final Uri target;
}

/// An added forum serves [target], but the app has no page for it.
final class RequestedLinkUndecodable extends RequestedLinkOutcome {
  const RequestedLinkUndecodable(this.target);

  final Uri target;
}
