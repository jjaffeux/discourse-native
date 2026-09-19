import { chatFeatures, chatRules } from '../profiles.js';

// Ruby Chat::Message.match_slash_command, source pin recorded in provenance.
// State is owned by this cook and shared only with this owner's later stages.
export function transform(raw, context, api) {
  if (api.profile !== 'chat') return raw;
  const bot = (api.context.editorId ?? api.context.authorId) < 0;
  api.options.featuresOverride = [...chatFeatures, ...api.activeFeatures, ...(bot ? ['image-grid'] : []),
    ...(api.options.siteSettings.enable_emoji_shortcuts ? ['emojiShortcuts'] : [])];
  api.options.markdownItRules = [...chatRules, ...(bot ? ['heading'] : [])];
  api.options.forceQuoteLink = true;
  api.options.hashtagTypesInPriorityOrder = api.hashtagPriorities.chat || ['channel', 'category', 'tag'];
  const author = api.context.authorUsername || '';
  const commands = [
    ['me', /^\/me[ \t]+([^\r\n]+)$/, null],
    ['shrug', /^\/shrug(?:[ \t]+([^\r\n]+))?$/, '¯\\_(ツ)_/¯'],
    ['tableflip', /^\/tableflip(?:[ \t]+([^\r\n]+))?$/, '(╯°□°)╯︵ ┻━┻'],
  ];
  for (const [name, pattern, text] of commands) {
    if (name === 'me' && !author.trim()) continue;
    const match = raw.match(pattern);
    // JavaScript $ also matches before a terminal newline; Ruby \z does not.
    if (!match || match[0].length !== raw.length) continue;
    api.state.command = {name, text, author};
    return match[1] || '';
  }
  return raw;
}
