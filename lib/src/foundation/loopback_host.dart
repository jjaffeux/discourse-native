/// IPv4 must use four decimal octets without leading zeros. Platform resolvers
/// may interpret alternative numeric bases or shorthand such as `127.1`, but
/// plaintext transport must not depend on an ambiguous host's interpretation.
bool isLoopbackHost(String host) {
  var normalized = host.toLowerCase();
  if (normalized.endsWith('.')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }

  if (normalized == 'localhost' || normalized.endsWith('.localhost')) {
    return true;
  }
  if (host == '::1') return true;

  // A root dot is supported only for localhost names, not numeric addresses.
  if (host.length > 15) return false;
  final octets = host.split('.');
  if (octets.length != 4 || octets.first != '127') return false;

  for (final octet in octets.skip(1)) {
    if (octet.isEmpty ||
        octet.length > 3 ||
        (octet.length > 1 && octet.startsWith('0')) ||
        octet.codeUnits.any((unit) => unit < 0x30 || unit > 0x39)) {
      return false;
    }
    if (int.parse(octet) > 255) return false;
  }
  return true;
}
