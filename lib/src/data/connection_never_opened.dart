import 'dart:io';

/// Whether a socket failure proves no connection was ever opened.
bool connectionNeverOpened(Object error) => switch (error) {
  // Dart's own words, unlike an OS error's text, so no locale changes them.
  SocketException(:final message)
      when message.startsWith('Failed host lookup') =>
    true,
  SocketException(osError: OSError(:final errorCode)) =>
    _connectionNeverOpened.contains(errorCode),
  _ => false,
};

/// ECONNREFUSED answers only a connection attempt: a peer resetting an open
/// connection reports ECONNRESET. Both kernels hold ENETUNREACH, EHOSTUNREACH
/// and ENETDOWN on an open connection as soft errors, reported only when
/// retransmission gives up, minutes after any write here has timed out. The
/// numbers differ per kernel, and Darwin's EPROTO is Linux's ENETDOWN, so only
/// the running kernel's own are recognised.
final Set<int> _connectionNeverOpened = switch (Platform.operatingSystem) {
  'macos' || 'ios' => const {61, 51, 65, 50},
  'linux' || 'android' => const {111, 101, 113, 100},
  _ => const {},
};
