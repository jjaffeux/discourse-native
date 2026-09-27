import 'package:discourse_native/discourse_plugin_sdk.dart';

/// How long the site may take to answer a request that runs its language model
/// before replying. Proofreading and a summary generated without streaming are
/// both produced inside the request (upstream wraps them in `hijack`), so the
/// answer takes as long as the model does, and for a long post or topic that
/// routinely outlasts the host's ordinary write deadline. Upstream's web client
/// sets no client-side limit on these requests; this one only stops a request
/// the server never answers from holding the author indefinitely.
const aiGenerationTimeout = Duration(minutes: 2);

/// Posts a generation request under [aiGenerationTimeout] when the host can
/// extend a write's deadline, and as an ordinary write otherwise.
Future<Map<String, dynamic>> postAiGeneration(
  PluginApiTransport transport, {
  required String siteUrl,
  required String path,
  required String apiKey,
  required Map<String, Object?> body,
  String? clientId,
}) => switch (transport) {
  final PluginLongRunningWriteTransport longRunning =>
    longRunning.pluginLongRunningWriteJson(
      siteUrl: siteUrl,
      path: path,
      method: 'POST',
      apiKey: apiKey,
      body: body,
      requestTimeout: aiGenerationTimeout,
      clientId: clientId,
    ),
  _ => transport.pluginWriteJson(
    siteUrl: siteUrl,
    path: path,
    method: 'POST',
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  ),
};
