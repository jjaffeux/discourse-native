/// This intentionally accepts only the full IPv4 form. Platform resolvers may
/// understand shorthand such as `127.1`, but plaintext transport should not
/// depend on resolver-specific interpretation of an ambiguous host.
bool isLoopbackHost(String host) {
  var normalized = host.toLowerCase();
  if (normalized.endsWith('.')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }

  if (normalized == 'localhost' ||
      normalized.endsWith('.localhost') ||
      normalized == '::1') {
    return true;
  }

  final octets = normalized.split('.').map(int.tryParse).toList();
  return octets.length == 4 &&
      octets.every((octet) => octet != null && octet >= 0 && octet <= 255) &&
      octets.first == 127;
}
