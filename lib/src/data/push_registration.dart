class PushRegistration {
  const PushRegistration({required this.clientId, required this.pushUrl});

  final String clientId;

  final String pushUrl;
}

abstract interface class PushRegistrationProvider {
  /// The registration for a new authorization. May ask the user for
  /// notification permission.
  Future<PushRegistration?> registration();

  /// The registration this installation holds now, or null without one. Never
  /// asks for permission, so it is safe at launch and on every resume.
  Future<PushRegistration?> current();
}

/// What one authorization told a forum about this device's push identity.
final class PushAuthorization {
  const PushAuthorization({required this.registration, required this.accepted});

  /// Null when the platform offered no token while authorizing.
  final PushRegistration? registration;

  /// The forum's own answer: false when it does not allow the push URL.
  final bool accepted;
}
