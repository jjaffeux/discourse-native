import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'ai_generation_write.dart';

const aiProofreadingPath = '/discourse-ai/ai-helper/suggest';

final class AiProofreadingApi {
  const AiProofreadingApi(this._transport);

  final PluginApiTransport _transport;

  Future<String> proofread({
    required String siteUrl,
    required String apiKey,
    required String text,
  }) async {
    final body = await postAiGeneration(
      _transport,
      siteUrl: siteUrl,
      path: aiProofreadingPath,
      apiKey: apiKey,
      // Without it the server tells the model to answer in the reader's
      // interface locale, which can translate the reply instead of fixing it.
      body: {'text': text, 'mode': 'proofread', 'force_default_locale': true},
    );
    for (final suggestion in jsonArray(body['suggestions'])) {
      if (suggestion is String && suggestion.trim().isNotEmpty) {
        return suggestion;
      }
    }
    throw FormatException(appL10n.proofreadingResponseContainedNoSuggestion);
  }
}
