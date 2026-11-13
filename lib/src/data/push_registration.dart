class PushRegistration {
  const PushRegistration({required this.clientId, required this.pushUrl});

  final String clientId;

  final String pushUrl;
}

abstract interface class PushRegistrationProvider {
  Future<PushRegistration?> registration();
}
